---
name: screen-recording-demo
description: Make short, silent, privacy-safe screen-recording demo videos (and animated GIFs) of an app or web tool on macOS, with a visibly moving cursor, numbered step captions, and title cards, using only ffmpeg, Swift, and Python already on the machine. Use this skill whenever the user asks for a screen recording, demo video, tutorial video, walkthrough, how-to clip, product demo, or animated GIF of a tool in use, or asks to "show people how to use" something they built, even if they never say "screen recording". Also use it when publishing such a video to a GitHub README or embedding it in a web page.
---

# Screen-recording demos

This skill records a real macOS screen session in which a script drives the real cursor and
keyboard, then edits the capture into a short captioned video. It was developed on 2026-09-30
for the File Encryption tool (https://github.com/justinpearson/easy-file-encryption), and the
bundled scripts are the ones that produced the videos now embedded in that tool's page and
README, so they double as a complete worked example.

## Defaults for these videos

These came from the person the skill was first built for, and each has a reason that should
guide the judgment calls a new recording will raise. Treat them as the defaults unless the
user says otherwise.

- **No personal information.** This was called "very important". The videos are public, and a
  screen recording picks up folder names, machine names, account avatars, notifications, and
  disk details without anyone noticing. Treat every pixel in the capture region as published.
- **Short and quick.** A video is a how-to embedded beside the tool, so it should run about 15
  to 25 seconds. The first File Encryption videos ran 20.6 and 17.4 seconds.
- **It looks like a screen recording.** The cursor visibly moves and clicks. Do not fake the
  interface with a mock-up.
- **No audio.** No narration and no synthesized speech. The output has no audio track.
- **Title card and numbered steps.** Each video opens with text on a solid color, and numbered
  captions let a viewer follow along.
- **One video per task, plus a joined one.** Separate encrypt and decrypt videos were preferred
  over a single long one.
- **Nothing installed.** Do not `brew install` or `pip install` anything. Everything here runs
  on ffmpeg, `swiftc`, Python 3 with Pillow, and Google Chrome, all already present.
- **Leave the machine as it was.** Any Finder or dialog setting changed for the recording is
  recorded first and restored afterwards, and the restoration is checked.
- **Teach the step a non-technical viewer would miss.** For the encryption tool that was
  zipping a folder with right-click, Compress. Ask which step that is for a new tool.

## Workflow

1. **Survey.** Check that the terminal has Screen Recording and Accessibility permission
   (`CGPreflightScreenCaptureAccess()` and `AXIsProcessTrusted()` from a Swift one-liner), read
   the tool's page or source to learn its controls, and find out where the video will be
   embedded. The embed width decides the capture size: the File Encryption page column is 460
   CSS pixels wide, so the demo windows were 640x560 points and native-size text stayed legible.
2. **Plan the steps.** Write the caption list first, five or six captions per video at most,
   each a short imperative. Decide the sample data; it must be obviously made up.
3. **Copy the tools.** Copy this skill's `tools/` folder into the project as `tools/`, then edit
   `common.zsh` (URL, window title, geometry, demo folder), `take.zsh` (the actions), and
   `videos.json` (titles and captions). Build the driver with
   `swiftc -O tools/axd.swift -o tools/bin/axd`. Read `tools/README.md` for what each file does.
4. **Ask for the screen, once.** Recording moves the real mouse and types on the real keyboard.
   Before the first action that steals focus, ask the user (with AskUserQuestion), say how long
   (the first project needed about 25 minutes including rehearsal; a repeat needs far less),
   and list what will change on screen. Do all file writing and compiling before asking.
5. **Build the scene and rehearse.** Run `tools/setup-scene.zsh`, then walk through the flow by
   hand with `axd` commands, taking cropped screenshots (`shot` in `common.zsh`) to see what
   the capture region shows. Then run `tools/take.zsh <name> --dry-run` until it passes.
6. **Record.** Run `tools/take.zsh <name>` for each video.
7. **Tear down right away.** Run `tools/teardown-scene.zsh`, verify the settings listed under
   "Teardown" below, and tell the user the machine is theirs again. Rendering does not need the
   screen, so do not hold it while rendering.
8. **Render and review.** Run `python3 tools/render.py all --frames --gif`, then look at the
   stills as contact sheets and at full-size frames around each cut. Deliver only after that.
9. **Publish** if asked. Read `references/publishing.md` first.

## How the pieces fit

`take.zsh` starts ffmpeg, which captures the screen cropped to the demo region, and then calls
`axd` for each action. `axd` finds elements through the Accessibility API, glides the cursor
to them, and appends every action to a log with a system-uptime timestamp. ffmpeg's
avfoundation capture stamps frames with the same clock when run with `-copyts`, so `render.py`
can place captions exactly at the `mark step N` lines in the log and remove the spans between
`mark cut-start` and `mark cut-end`.

Looking elements up at run time is what makes a take reliable. Hard-coded coordinates break as
soon as a label wraps or a row is added, while `axd moveto <pid> <window> id=password-input`
keeps working.

## Designing the scene

- **Crop at capture.** The ffmpeg command crops to the demo region, so the raw file never
  contains the rest of the screen. Keep the region away from the top-right corner, where
  notifications appear.
- **Throwaway browser profile.** Launch a second Chrome instance with its own
  `--user-data-dir` and `--app=<url>`, which gives a window with a title bar and nothing else:
  no tabs, bookmarks, extensions, or avatar.
- **Backdrop window.** A second app-mode window showing a solid color sits behind the demo
  windows and fills the crop margin, so the desktop and other apps never show.
- **Stack the demo windows on one rectangle.** Switching between Finder and the browser then
  reads as an ordinary app switch, and the cursor stays in frame.
- **Impersonal paths and sample files.** The demo folder was `/Users/Shared/Documents` because
  that Finder was set to show the full path in window titles. A hidden marker file guards every
  delete so an existing folder is never removed.

## Writing a take

Follow the shape of the bundled `take.zsh`: a `stage_<name>` function that prepares files and
windows without recording, and a `run_<name>` function made of `mark step N` lines, cursor
moves, clicks, and short pauses. Keep pauses short (0.15 to 0.6 seconds around clicks, about
1.2 seconds where the viewer needs to read a result); the renderer's `--speed 1.3` default
tightens the rest. Wait on conditions (`axd wait`, `axd gone`) instead of sleeping for fixed
times wherever the app does real work.

Anything ugly that must happen on screen, such as a dialog that opens too large and has to be
resized, goes between `mark cut-start` and `mark cut-end`, and the renderer removes it. The
cursor should not move inside a cut, so the edit is invisible.

macOS and Chrome have many small behaviors that cost time to rediscover. Read
`references/gotchas.md` before writing or debugging a take; it lists each one with its cause
and the fix that worked.

## Privacy checklist

Check each of these in the rendered frames, not only in the plan.

- The Finder sidebar, path bar, and status bar are hidden (they show folder names, the disk
  name, and free space).
- File dialogs show only the demo folder. The open dialog has no sidebar in this Chrome, and
  the save dialog is collapsed to its compact form.
- Window titles show an impersonal path.
- No notification, tooltip, or other app's window appears in any frame.
- Rehearsal screenshots that captured real folder listings are deleted from `work/`.

Tell the user what remains visible even when it is harmless, for example a standard menu item
such as "Import from iPhone" or a "Today at 6:42 AM" timestamp, so the decision is theirs.

## Teardown

`teardown-scene.zsh` restores what `setup-scene.zsh` recorded in `work/scene-state.zsh`. After
it runs, confirm by reading the settings, not by assuming:

```zsh
for k in ShowSidebar ShowPathbar ShowStatusBar; do defaults read com.apple.finder $k; done
defaults read com.google.Chrome | grep NSNav
pgrep -fl "user-data-dir=.*chrome-profile"    # expect no output
ls -d /Users/Shared/Documents                 # expect "No such file"
```

Keep `work/chrome-profile`: it remembers which folder the file dialogs last used, and retakes
depend on that.

## Reporting back

Report in plain full sentences: what was produced (paths, durations, sizes), how the videos
were checked, what personal-looking details remain visible, which settings were changed and
restored, anything left behind on the machine, and anything edited after its last real run.
The user will review the videos, so say when they were checked only as still frames.

## Status of the bundled scripts

`axd.swift`, `take.zsh`, and `render.py` ran for real and produced the published videos.
`setup-scene.zsh` and `teardown-scene.zsh` were edited after their last real run (to save and
restore the original dialog settings, and to read the window title from `common.zsh`), and
those edits have passed only a syntax check. Expect to debug them on the next use, and update
this section once they have run cleanly.

## Reference files

- `tools/README.md` describes each script and which parts are specific to the first project.
- `references/gotchas.md` lists the macOS, Chrome, ffmpeg, and shell behaviors met so far.
- `references/publishing.md` covers putting the videos in a GitHub README and a web page.
- `references/check-page.mjs` tests a web page in headless Chrome with no dependencies; it is
  the script used to verify the embedded videos.
