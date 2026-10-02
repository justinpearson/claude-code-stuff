// axd: a small macOS accessibility and input driver used to script the tutorial recording.
// It looks up on-screen elements through the Accessibility API, moves the real cursor with
// easing so the motion is visible in a screen recording, and posts clicks and keystrokes.
//
// Build:  swiftc -O tools/axd.swift -o tools/bin/axd
// Usage:  axd <command> [args]   (run with no arguments for the command list)
//
// When the AXD_LOG environment variable names a file, every action is appended to it with a
// system-uptime timestamp. ffmpeg's avfoundation capture stamps frames with the same clock,
// which lets the post-processing step line captions up with actions.

import Cocoa
import ApplicationServices

// MARK: - Accessibility helpers

func attr(_ e: AXUIElement, _ name: String) -> AnyObject? {
	var v: AnyObject?
	return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
}

func sattr(_ e: AXUIElement, _ name: String) -> String {
	guard let v = attr(e, name) else { return "" }
	if let s = v as? String { return s }
	if let n = v as? NSNumber { return n.stringValue }
	return ""
}

func frame(_ e: AXUIElement) -> CGRect? {
	guard let p = attr(e, "AXPosition"), let s = attr(e, "AXSize") else { return nil }
	guard CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
	var pt = CGPoint.zero
	var sz = CGSize.zero
	AXValueGetValue(p as! AXValue, .cgPoint, &pt)
	AXValueGetValue(s as! AXValue, .cgSize, &sz)
	return CGRect(origin: pt, size: sz)
}

func kids(_ e: AXUIElement) -> [AXUIElement] {
	(attr(e, "AXChildren") as? [AXUIElement]) ?? []
}

func die(_ msg: String) -> Never {
	FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
	exit(1)
}

func appElement(_ pid: pid_t) -> AXUIElement {
	let app = AXUIElementCreateApplication(pid)
	AXUIElementSetMessagingTimeout(app, 3.0)
	return app
}

func windows(_ pid: pid_t) -> [AXUIElement] {
	(attr(appElement(pid), "AXWindows") as? [AXUIElement]) ?? []
}

// A scope is "app", "focused", a window index, "title:<substring>", or "at:<x>,<y>".
func scope(_ pid: pid_t, _ sel: String) -> AXUIElement {
	if sel == "app" { return appElement(pid) }
	if sel == "focused" {
		guard let w = attr(appElement(pid), "AXFocusedWindow") else { die("no focused window") }
		return w as! AXUIElement
	}
	let ws = windows(pid)
	if let i = Int(sel) {
		guard i < ws.count else { die("no window \(i)") }
		return ws[i]
	}
	if sel.hasPrefix("title:") {
		let t = String(sel.dropFirst(6))
		guard let w = ws.first(where: { sattr($0, "AXTitle").localizedCaseInsensitiveContains(t) }) else { die("no window titled \(t)") }
		return w
	}
	if sel.hasPrefix("at:") {
		let xy = sel.dropFirst(3).split(separator: ",").compactMap { Double($0) }
		guard xy.count == 2 else { die("bad scope \(sel)") }
		guard let w = ws.first(where: { w in
			guard let f = frame(w) else { return false }
			return abs(f.minX - xy[0]) < 3 && abs(f.minY - xy[1]) < 3
		}) else { die("no window at \(sel)") }
		return w
	}
	die("bad scope \(sel)")
}

struct Query {
	var terms: [(key: String, exact: Bool, value: String)] = []
	var nth = 0

	init(_ args: [String]) {
		for a in args {
			if a.hasPrefix("nth=") { nth = Int(a.dropFirst(4)) ?? 0; continue }
			if let r = a.range(of: "~") {
				terms.append((String(a[..<r.lowerBound]), false, String(a[r.upperBound...])))
			} else if let r = a.range(of: "=") {
				terms.append((String(a[..<r.lowerBound]), true, String(a[r.upperBound...])))
			} else {
				die("bad query term \(a)")
			}
		}
	}

	func matches(_ e: AXUIElement) -> Bool {
		for t in terms {
			let candidates: [String]
			switch t.key {
			case "role": candidates = [sattr(e, "AXRole")]
			case "subrole": candidates = [sattr(e, "AXSubrole")]
			case "title": candidates = [sattr(e, "AXTitle")]
			case "desc": candidates = [sattr(e, "AXDescription")]
			case "value": candidates = [sattr(e, "AXValue")]
			case "id": candidates = [sattr(e, "AXIdentifier"), sattr(e, "AXDOMIdentifier")]
			case "any": candidates = [sattr(e, "AXTitle"), sattr(e, "AXDescription"), sattr(e, "AXValue"), sattr(e, "AXFilename")]
			default: die("unknown query key \(t.key)")
			}
			let ok = candidates.contains { c in
				t.exact ? c == t.value : c.localizedCaseInsensitiveContains(t.value)
			}
			if !ok { return false }
		}
		return true
	}
}

func findAll(_ root: AXUIElement, _ q: Query, maxDepth: Int = 60, limit: Int = 60000) -> [AXUIElement] {
	var out: [AXUIElement] = []
	var visited = 0
	func walk(_ e: AXUIElement, _ depth: Int) {
		visited += 1
		if visited > limit || depth > maxDepth { return }
		if q.matches(e) { out.append(e) }
		for k in kids(e) { walk(k, depth + 1) }
	}
	walk(root, 0)
	return out
}

func describe(_ e: AXUIElement) -> String {
	var parts = [sattr(e, "AXRole")]
	let sub = sattr(e, "AXSubrole")
	if !sub.isEmpty { parts.append("(\(sub))") }
	for (label, name) in [("title", "AXTitle"), ("desc", "AXDescription"), ("value", "AXValue"), ("id", "AXIdentifier"), ("domid", "AXDOMIdentifier")] {
		var s = sattr(e, name)
		if s.isEmpty { continue }
		if s.count > 70 { s = String(s.prefix(70)) + "…" }
		parts.append("\(label)=\"\(s.replacingOccurrences(of: "\n", with: "⏎"))\"")
	}
	if let f = frame(e) {
		parts.append("[\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height))]")
	}
	return parts.joined(separator: " ")
}

func dump(_ e: AXUIElement, _ depth: Int, _ maxDepth: Int) {
	print(String(repeating: "  ", count: depth) + describe(e))
	if depth >= maxDepth { return }
	for k in kids(e) { dump(k, depth + 1, maxDepth) }
}

// MARK: - Logging

func uptime() -> Double { ProcessInfo.processInfo.systemUptime }

func logAction(_ text: String) {
	guard let path = ProcessInfo.processInfo.environment["AXD_LOG"], !path.isEmpty else { return }
	let line = String(format: "%.3f\t%@\n", uptime(), text)
	if let h = FileHandle(forWritingAtPath: path) {
		h.seekToEndOfFile()
		h.write(line.data(using: .utf8)!)
		h.closeFile()
	} else {
		try? line.write(toFile: path, atomically: true, encoding: .utf8)
	}
}

// MARK: - Input

let eventSource = CGEventSource(stateID: .hidSystemState)

func cursor() -> CGPoint { CGEvent(source: nil)!.location }

func postMouse(_ type: CGEventType, _ p: CGPoint, _ button: CGMouseButton = .left, clicks: Int64 = 1) {
	guard let e = CGEvent(mouseEventSource: eventSource, mouseType: type, mouseCursorPosition: p, mouseButton: button) else { return }
	e.setIntegerValueField(.mouseEventClickState, value: clicks)
	// Clear modifier flags explicitly. Otherwise a click can inherit the Command flag from an
	// earlier key combination, and Command-double-click opens a folder in a new window.
	e.flags = []
	e.post(tap: .cghidEventTap)
}

// Moves the cursor along a slightly curved path with minimum-jerk easing.
// A duration of 0 picks one from the distance.
func move(to target: CGPoint, ms: Double) {
	let from = cursor()
	let dist = hypot(target.x - from.x, target.y - from.y)
	if dist < 1 { return }
	let dur = ms > 0 ? ms / 1000 : min(0.85, max(0.35, 0.3 + dist / 1500))
	let steps = max(2, Int(dur * 60))
	let nx = -(target.y - from.y) / dist
	let ny = (target.x - from.x) / dist
	let bow = min(28, dist * 0.06)
	for i in 1...steps {
		let t = Double(i) / Double(steps)
		let s = t * t * t * (10 - 15 * t + 6 * t * t)
		let arc = sin(Double.pi * s) * bow
		let p = CGPoint(x: from.x + (target.x - from.x) * s + nx * arc, y: from.y + (target.y - from.y) * s + ny * arc)
		postMouse(.mouseMoved, p)
		usleep(useconds_t(dur / Double(steps) * 1_000_000))
	}
	postMouse(.mouseMoved, target)
}

func click(_ button: CGMouseButton = .left, count: Int = 1) {
	let p = cursor()
	let down: CGEventType = button == .left ? .leftMouseDown : .rightMouseDown
	let up: CGEventType = button == .left ? .leftMouseUp : .rightMouseUp
	for n in 1...count {
		postMouse(down, p, button, clicks: Int64(n))
		usleep(70_000)
		postMouse(up, p, button, clicks: Int64(n))
		if n < count { usleep(90_000) }
	}
}

// US-layout key codes. Typing posts real key codes (with Shift where needed) because some
// text fields, such as the one in the file dialog's Go to Folder sheet, ignore events that
// carry only a Unicode string.
let plainKeys: [Character: CGKeyCode] = [
	"a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14,
	"r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27,
	"8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41,
	"\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, " ": 49, "`": 50,
]
let shiftedKeys: [Character: Character] = [
	"!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8", "(": "9", ")": "0", "_": "-", "+": "=",
	":": ";", "\"": "'", "<": ",", ">": ".", "?": "/", "~": "`", "{": "[", "}": "]", "|": "\\",
]

func typeText(_ text: String, perCharMs: Double) {
	for ch in text {
		var code: CGKeyCode?
		var shift = false
		if let c = plainKeys[ch] {
			code = c
		} else if let base = shiftedKeys[ch], let c = plainKeys[base] {
			code = c
			shift = true
		} else if ch.isUppercase, let lower = ch.lowercased().first, let c = plainKeys[lower] {
			code = c
			shift = true
		}
		let units = Array(String(ch).utf16)
		for isDown in [true, false] {
			guard let e = CGEvent(keyboardEventSource: eventSource, virtualKey: code ?? 0, keyDown: isDown) else { continue }
			e.flags = shift ? .maskShift : []
			if code == nil { e.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units) }
			e.post(tap: .cghidEventTap)
			usleep(25_000)
		}
		usleep(useconds_t(perCharMs * 1000))
	}
}

// Named keys. Single-character keys are looked up in plainKeys.
let keyCodes: [String: CGKeyCode] = [
	"return": 36, "tab": 48, "space": 49, "escape": 53, "delete": 51, "left": 123, "right": 124, "down": 125, "up": 126,
]

// Presses a key combination such as "return" or "cmd+opt+s".
func pressKey(_ combo: String) {
	var flags: CGEventFlags = []
	var key: CGKeyCode?
	for part in combo.lowercased().split(separator: "+").map(String.init) {
		switch part {
		case "cmd": flags.insert(.maskCommand)
		case "opt", "alt": flags.insert(.maskAlternate)
		case "shift": flags.insert(.maskShift)
		case "ctrl": flags.insert(.maskControl)
		default:
			if let k = keyCodes[part] {
				key = k
			} else if part.count == 1, let k = plainKeys[part.first!] {
				key = k
			} else {
				die("unknown key \(part)")
			}
		}
	}
	guard let k = key else { die("no key in \(combo)") }
	for isDown in [true, false] {
		guard let e = CGEvent(keyboardEventSource: eventSource, virtualKey: k, keyDown: isDown) else { continue }
		e.flags = flags
		e.post(tap: .cghidEventTap)
		usleep(40_000)
	}
}

// MARK: - Commands

func center(_ e: AXUIElement) -> CGPoint {
	guard let f = frame(e) else { die("element has no frame") }
	return CGPoint(x: f.midX, y: f.midY)
}

func resolve(_ pid: pid_t, _ sel: String, _ terms: [String]) -> AXUIElement? {
	let q = Query(terms)
	let found = findAll(scope(pid, sel), q)
	return q.nth < found.count ? found[q.nth] : nil
}

// Returns the items of the menu reached by following `path` from the menu bar,
// e.g. ["View"] or ["View", "Sort By"].
func menuItems(_ pid: pid_t, _ path: [String]) -> [AXUIElement] {
	guard let bar = attr(appElement(pid), "AXMenuBar") else { die("no menu bar") }
	var items = kids(bar as! AXUIElement)
	for title in path {
		guard let item = items.first(where: { sattr($0, "AXTitle") == title }) else { die("no menu \(title)") }
		guard let menu = kids(item).first else { die("menu \(title) has no items") }
		items = kids(menu)
	}
	return items
}

let usage = """
axd commands:
  now                                   print system uptime in seconds
  mark <label>                          write a labelled line to the AXD_LOG file
  zorder                                list on-screen windows front to back
  wins <pid>                            list an app's windows
  title <pid> <scope>                   print a window's title
  setframe <pid> <scope> x y w h        move and resize a window
  raise <pid> <scope>                   bring one window to the front without its siblings
  activate <pid>                        bring an app and all its windows to the front
  dump <pid> <scope> [depth]            print the accessibility tree
  find <pid> <scope> <terms…>           print "cx cy x y w h" of the first matching element
  wait <pid> <scope> <seconds> <terms…> poll until an element matches, then print as find does
  gone <pid> <scope> <seconds> <terms…> poll until no element matches
  attrs <pid> <scope> <terms…>          list an element's attributes and actions
  press <pid> <scope> <terms…>          perform AXPress on an element
  setbool <pid> <scope> <attr> <0|1> <terms…>
  setsize <pid> <scope> w h <terms…>    resize an element, e.g. a file dialog sheet
  menu <pid> list <Menu> [Submenu…]     list a menu's item titles
  menu <pid> press <Menu> [Submenu…] <Item>   choose a menu item
  pos                                   print the cursor position
  move <x> <y> [ms]                     glide the cursor to a point
  moveto <pid> <scope> [ms=N] [dx=N] [dy=N] <terms…>   glide the cursor to an element
  click | rclick | dclick               click at the cursor
  drag <x1> <y1> <x2> <y2>              press at one point, drag to another, release
  type <text> [perCharMs]               type text
  key <combo>                           press a key, e.g. return or cmd+opt+s
Query terms: role= subrole= title= desc= value= id= any=, with ~ instead of = for "contains", and nth=N.
Scopes: app, focused, a window index, title:<substring>, at:<x>,<y>.
"""

var args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else { print(usage); exit(0) }
args.removeFirst()

func pidArg() -> pid_t {
	guard let s = args.first, let p = Int32(s) else { die("expected a pid") }
	args.removeFirst()
	return p
}

func next(_ what: String) -> String {
	guard let s = args.first else { die("expected \(what)") }
	args.removeFirst()
	return s
}

func printFound(_ e: AXUIElement) {
	guard let f = frame(e) else { die("element has no frame") }
	print("\(Int(f.midX)) \(Int(f.midY)) \(Int(f.minX)) \(Int(f.minY)) \(Int(f.width)) \(Int(f.height))")
}

switch cmd {
case "now":
	print(String(format: "%.3f", uptime()))

case "mark":
	logAction("mark " + args.joined(separator: " "))

case "zorder":
	let opts = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
	let list = (CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]]) ?? []
	for w in list {
		let layer = w[kCGWindowLayer as String] as? Int ?? -1
		let owner = w[kCGWindowOwnerName as String] as? String ?? "?"
		let pid = w[kCGWindowOwnerPID as String] as? Int ?? 0
		let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
		func n(_ k: String) -> Int { Int((b[k] as? Double) ?? 0) }
		print("layer=\(layer) pid=\(pid) \(owner) [\(n("X")),\(n("Y")) \(n("Width"))x\(n("Height"))]")
	}

case "wins":
	let pid = pidArg()
	for (i, w) in windows(pid).enumerated() {
		print("\(i): \(describe(w)) main=\(sattr(w, "AXMain"))")
	}

case "title":
	let pid = pidArg()
	print(sattr(scope(pid, next("scope")), "AXTitle"))

case "setframe":
	let pid = pidArg()
	let w = scope(pid, next("scope"))
	let nums = args.compactMap { Double($0) }
	guard nums.count == 4 else { die("expected x y w h") }
	var pt = CGPoint(x: nums[0], y: nums[1])
	var sz = CGSize(width: nums[2], height: nums[3])
	// Size, then position, then size again: a window clamps its size against the screen edge
	// at its old position, so a single pass can leave it short.
	for _ in 0..<2 {
		AXUIElementSetAttributeValue(w, "AXSize" as CFString, AXValueCreate(.cgSize, &sz)!)
		AXUIElementSetAttributeValue(w, "AXPosition" as CFString, AXValueCreate(.cgPoint, &pt)!)
	}
	print(describe(w))

case "raise":
	let pid = pidArg()
	let w = scope(pid, next("scope"))
	AXUIElementSetAttributeValue(w, "AXMain" as CFString, kCFBooleanTrue)
	AXUIElementPerformAction(w, "AXRaise" as CFString)
	// No .activateAllWindows: only the main window comes forward, so the app's other windows
	// stay where they are in the window stack.
	let ok = NSRunningApplication(processIdentifier: pid)?.activate(options: []) ?? false
	logAction("raise \(pid)")
	print("activated=\(ok)")

case "activate":
	let pid = pidArg()
	let ok = NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateAllWindows]) ?? false
	print("activated=\(ok)")

case "dump":
	let pid = pidArg()
	let root = scope(pid, next("scope"))
	dump(root, 0, Int(args.first ?? "") ?? 12)

case "find":
	let pid = pidArg()
	let sel = next("scope")
	guard let e = resolve(pid, sel, args) else { die("not found: \(args.joined(separator: " "))") }
	printFound(e)

case "wait", "gone":
	let pid = pidArg()
	let sel = next("scope")
	guard let secs = Double(next("seconds")) else { die("expected seconds") }
	let deadline = Date().addingTimeInterval(secs)
	while true {
		let e = resolve(pid, sel, args)
		if cmd == "wait", let e = e, frame(e) != nil { printFound(e); break }
		if cmd == "gone", e == nil { break }
		if Date() > deadline { die("timed out waiting (\(cmd)): \(args.joined(separator: " "))") }
		usleep(80_000)
	}

case "attrs":
	let pid = pidArg()
	let sel = next("scope")
	guard let e = resolve(pid, sel, args) else { die("not found") }
	var names: CFArray?
	AXUIElementCopyAttributeNames(e, &names)
	for n in (names as? [String]) ?? [] {
		var v = "\(attr(e, n).map { "\($0)" } ?? "nil")"
		if v.count > 120 { v = String(v.prefix(120)) + "…" }
		print("\(n) = \(v.replacingOccurrences(of: "\n", with: " "))")
	}
	var actions: CFArray?
	AXUIElementCopyActionNames(e, &actions)
	print("actions: \((actions as? [String]) ?? [])")

case "press":
	let pid = pidArg()
	let sel = next("scope")
	guard let e = resolve(pid, sel, args) else { die("not found") }
	let err = AXUIElementPerformAction(e, "AXPress" as CFString)
	print("press: \(err.rawValue)")

case "setbool":
	let pid = pidArg()
	let sel = next("scope")
	let name = next("attribute")
	let on = next("0|1") == "1"
	guard let e = resolve(pid, sel, args) else { die("not found") }
	let err = AXUIElementSetAttributeValue(e, name as CFString, on ? kCFBooleanTrue : kCFBooleanFalse)
	print("set: \(err.rawValue)")

case "setsize":
	let pid = pidArg()
	let sel = next("scope")
	guard let w = Double(next("w")), let h = Double(next("h")) else { die("expected w h") }
	guard let e = resolve(pid, sel, args) else { die("not found") }
	var sz = CGSize(width: w, height: h)
	let err = AXUIElementSetAttributeValue(e, "AXSize" as CFString, AXValueCreate(.cgSize, &sz)!)
	print("set: \(err.rawValue) \(describe(e))")

case "menu":
	let pid = pidArg()
	let sub = next("list|press")
	if sub == "list" {
		for i in menuItems(pid, args) {
			let t = sattr(i, "AXTitle")
			if !t.isEmpty { print("\(t)\tenabled=\(sattr(i, "AXEnabled"))\tmark=\(sattr(i, "AXMenuItemMarkChar"))") }
		}
	} else {
		guard let title = args.last else { die("expected a menu path") }
		let items = menuItems(pid, Array(args.dropLast()))
		guard let item = items.first(where: { sattr($0, "AXTitle") == title }) else { die("no menu item \(title)") }
		let err = AXUIElementPerformAction(item, "AXPress" as CFString)
		print("press: \(err.rawValue)")
	}

case "pos":
	let p = cursor()
	print("\(Int(p.x)) \(Int(p.y))")

case "move":
	guard let x = Double(next("x")), let y = Double(next("y")) else { die("expected x y") }
	let ms = Double(args.first ?? "") ?? 0
	logAction("move \(Int(x)) \(Int(y))")
	move(to: CGPoint(x: x, y: y), ms: ms)

case "moveto":
	let pid = pidArg()
	let sel = next("scope")
	var ms = 0.0, dx = 0.0, dy = 0.0
	var terms: [String] = []
	for a in args {
		if a.hasPrefix("ms=") { ms = Double(a.dropFirst(3)) ?? 0 }
		else if a.hasPrefix("dx=") { dx = Double(a.dropFirst(3)) ?? 0 }
		else if a.hasPrefix("dy=") { dy = Double(a.dropFirst(3)) ?? 0 }
		else { terms.append(a) }
	}
	guard let e = resolve(pid, sel, terms) else { die("not found: \(terms.joined(separator: " "))") }
	let c = center(e)
	logAction("moveto \(terms.joined(separator: " "))")
	move(to: CGPoint(x: c.x + dx, y: c.y + dy), ms: ms)

case "drag":
	let nums = args.compactMap { Double($0) }
	guard nums.count == 4 else { die("expected x1 y1 x2 y2") }
	let from = CGPoint(x: nums[0], y: nums[1])
	let to = CGPoint(x: nums[2], y: nums[3])
	move(to: from, ms: 300)
	usleep(150_000)
	postMouse(.leftMouseDown, from)
	usleep(150_000)
	for i in 1...30 {
		let t = Double(i) / 30
		postMouse(.leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
		usleep(16_000)
	}
	usleep(150_000)
	postMouse(.leftMouseUp, to)

case "click":
	logAction("click")
	click(.left)

case "rclick":
	logAction("rclick")
	click(.right)

case "dclick":
	logAction("dclick")
	click(.left, count: 2)

case "type":
	let text = next("text")
	logAction("type")
	typeText(text, perCharMs: Double(args.first ?? "") ?? 55)

case "key":
	let combo = next("key combo")
	logAction("key \(combo)")
	pressKey(combo)

default:
	print(usage)
	exit(1)
}
