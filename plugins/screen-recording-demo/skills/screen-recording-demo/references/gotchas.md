# Gotchas

Each entry gives what was observed, why it happens, and the fix that worked. All of these were
met on macOS 26.6 with Chrome and ffmpeg 8.0 on 2026-09-30.

## Contents

1. Controlling windows and apps
2. Finder
3. Chrome and its file dialogs
4. Input events
5. ffmpeg capture and rendering
6. Shell and safety
7. Tools that turned out not to be needed

## 1. Controlling windows and apps

**AppleScript to Finder fails with error -1743.** The terminal is not authorized to send Apple
events to Finder. The Accessibility API needs no such grant beyond Accessibility permission, so
`axd` does everything through it: window frames, menu items, element lookup.

**Opening a folder brings every Finder window to the front.** `open <folder>` activates Finder,
and activation raises all of its windows above the backdrop. Restack afterwards by raising the
backdrop, then each demo window, one at a time. `axd raise` sets the window main, performs
`AXRaise`, and calls `NSRunningApplication.activate(options: [])`; leaving out
`.activateAllWindows` brings only that one window forward. Confirm the order with `axd zorder`.

**Activating an app with `.activateAllWindows` did not raise its other windows** when called
from the command-line process. Raise each window individually instead.

**Searching a whole app's accessibility tree can take 30 seconds.** The user may have many
Finder windows open, each with a large tree. Always search a single window (`at:x,y` or
`title:`), never `app`, unless the element is a direct child of the app.

**Do not store process IDs in the state file.** A stale Chrome PID in `scene-state.zsh` once
made teardown try to kill a process that no longer existed and leave the real one running.
The scripts now look PIDs up each time with `chrome_pid` and `finder_pid`.

## 2. Finder

**The window title may show the full POSIX path.** Finder does this when
`_FXShowPosixPathInTitle` is on, and changing it requires restarting Finder, which would
disturb the user's open windows. Put the
demo folder at a short impersonal path such as `/Users/Shared/Documents` instead.

**The sidebar, path bar, and status bar leak personal details.** The sidebar lists favorite
folders, the machine name, and network devices; the path bar shows the disk name; the status
bar shows free space. Hide them with `axd menu $FPID press View "Hide Sidebar"` (and the other
two) while the demo window is frontmost. The path bar and status bar settings are global, so
record which were visible and restore them at teardown. The View menu's item titles only
refresh while Finder is active, so verify restoration with `defaults read com.apple.finder
ShowPathbar` and friends.

**New files land on top of existing icons.** In icon view with no sort order, Finder places a
new item at an offset that overlaps its neighbor. `axd menu $FPID press View "Sort By" Name`
puts the icons on a grid. The setting is stored in the folder's `.DS_Store`, so keep that file
when emptying the demo folder.

**The context menu hangs off the clicked icon.** After a right-click, the `AXMenu` is found by
searching the demo window, not the app element's direct children.

**A folder window survives its folder being replaced.** Deleting and recreating a folder at the
same path left the window showing the new folder. The staging code still navigates the window
back to the demo folder first (Command-Up) to be safe.

**Double-clicking a zip runs Archive Utility**, which briefly makes the Finder window look
inactive. Its progress window did not appear in the capture region for a small file.

## 3. Chrome and its file dialogs

**Launch flags for a clean, scriptable instance:**

```
--user-data-dir=<work>/chrome-profile --no-first-run --no-default-browser-check
--use-mock-keychain --disable-search-engine-choice-screen --force-renderer-accessibility
--app=<url>
```

`--force-renderer-accessibility` exposes web content to the Accessibility API, including each
element's DOM id. `--window-position` and `--window-size` are unreliable for the second
window, so set frames with `axd setframe`.

**A `#` in a `data:` URL starts a fragment.** A backdrop page written as
`data:text/html,<body style='background:#3b4a6b'>` renders white. Write the color as `%233b4a6b`.

**The open-file dialog is 880 points wide and will not stay smaller.** It is a sheet on the
window, wider than the demo region. Its size did not persist after an Accessibility resize, a
real drag, or `defaults write com.google.Chrome NSNavPanelExpandedSizeForOpenMode`; the value
is rewritten. The working approach is to resize the sheet with `axd setsize` as soon as it
appears (its minimum is 675 by about 230), bracket that moment with cut marks, and let the
renderer remove it. Restore the original size setting at teardown, since the preference domain
is shared with the user's everyday Chrome.

**The save dialog opens expanded, showing a sidebar and the user's Documents folder.** Pressing the
disclosure control (`id=NS_OPEN_SAVE_DISCLOSURE_TRIANGLE`) collapses it to a compact form with
only a name, tags, and a "Where" pop-up. The collapsed state persists and is also shared with
the user's everyday Chrome (`NSNavPanelExpandedStateForSaveMode`), so restore it at teardown.
`take.zsh` refuses to continue if the "Where" pop-up does not name the demo folder.

**A fresh profile's dialogs open in the home folder.** During rehearsal, not during a take,
point each dialog at the demo folder once: press Command-Shift-G, type the path, press Return,
then complete the dialog. The profile remembers the folder afterwards, which is why
`work/chrome-profile` must be kept. This adds the demo path to the Go to Folder recents.

**A stray "No file chosen" tooltip appears about a second after a save dialog closes**, at
wherever the cursor rests. Pressing a key while the tooltip is still pending cancels it:
`take.zsh` presses Escape 0.25 seconds and 0.6 seconds after the dialog goes away.

**`showSaveFilePicker` adds "Warning: this site can see edits you make"** to the save dialog.
That is Chrome's own text and belongs in an honest recording.

**Writing the output took about 1.5 seconds even for a 50 KB file**, while Chrome finished the
save. Wait on the status text, not a fixed delay.

## 4. Input events

**Typed text was ignored by the Go to Folder field.** Key events that carry only a Unicode
string, with no real key code, did nothing there. `axd type` posts US-layout key codes with
Shift where needed and falls back to the Unicode string only for other characters.

**A double-click opened a folder in a new window.** A preceding Command-Up left the Command
flag on the event source, and Command-double-click means "open in a new window". `axd` clears
the modifier flags on every mouse event.

**Secure text fields accept posted key events**, so typing a password into a web form works.
The video shows only dots.

**ffmpeg's `-capture_mouse_clicks 1` draws a ring at each click**, which is enough click
feedback; nothing needs to be drawn in post.

## 5. ffmpeg capture and rendering

**Capture command** (from `take.zsh`):

```
ffmpeg -f avfoundation -framerate 30 -capture_cursor 1 -capture_mouse_clicks 1 \
  -pixel_format nv12 -i "Capture screen 0:none" -copyts \
  -vf "crop=W:H:X:Y" -c:v libx264 -preset ultrafast -crf 12 -pix_fmt yuv420p raw.mkv
```

Crop values are in pixels, which are twice the point values on the Retina display.

**`-copyts` makes frame timestamps equal system uptime**, the same clock as
`ProcessInfo.systemUptime`, so the container's `start_time` (from ffprobe) converts log times
to video times. With `-copyts`, an output-side `-t 2` stops immediately because timestamps are
already far past 2; stop the capture with SIGINT instead.

**The raw file stays empty for several seconds** while the encoder buffers, so waiting for a
non-empty file gives generous pre-roll. The renderer trims to the first step mark.

**`xfade` needs matching inputs.** Give both the title card and the body `fps=30`,
`format=yuv420p`, and `settb=AVTB`.

**A single PNG as an overlay input repeats by default**, so caption images need no `-loop`.

**Pillow can load the system font with weights:** `ImageFont.truetype("/System/Library/Fonts/
SFNS.ttf", size)` then `set_variation_by_name("Semibold")`.

**GIF export** uses `palettegen` and `paletteuse` with dithering off; a 20-second, 688-pixel,
10-fps GIF of flat interface content came to about 0.8 MB, against 0.4 MB for the MP4.

## 6. Shell and safety

**`rm -rf` on a path built from variables is blocked** by Claude Code's safety check. Write
`${VAR:?}` so the shell aborts when the variable is empty, and guard deletes of the demo
folder with a hidden marker file that only these scripts create.

**A bare `wait` in zsh waits for every background job, including ffmpeg.** Wait on a specific
PID.

**Searching the whole home folder is slow and intrusive.** A `find ~` ran past two minutes at
depth 4, and macOS asked the user to let Terminal read protected folders. Look in specific
folders, or ask.

**Take screenshots of the crop region only** (`screencapture -x -R x,y,w,h`) when checking the
scene, so the rest of the user's screen is never read. Delete rehearsal screenshots afterwards;
some will show real folder listings from before the dialogs were pointed at the demo folder.

## 7. Tools that turned out not to be needed

QuickTime Player was not needed, because ffmpeg captures the screen directly. No third-party
input tool is needed either: `axd` moves the cursor with a fixed duration
and easing, clicks, types, and can look elements up, using only the Accessibility permission.
The Claude-in-Chrome extension was not used for recording, because the throwaway Chrome
instance does not have it.
