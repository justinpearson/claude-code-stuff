# screen-recording-demo

A skill for making short, silent screen-recording demos of a tool on macOS, distributed as a
plugin in the [`claude-code-stuff`](../../README.md) marketplace.

## Install

```
/plugin marketplace add justinpearson/claude-code-stuff
/plugin install screen-recording-demo@claude-code-stuff
```

## What it does

Given a tool and the steps to show, Claude records a real screen session: a small Swift
program drives the actual cursor and keyboard through the macOS Accessibility API while ffmpeg
captures a cropped region of the screen. A Python script then cuts the capture, speeds it up,
adds a title card and numbered step captions, and encodes an MP4 (and optionally an animated
GIF for places that cannot play video, such as a GitHub README).

The skill was built to produce the two walkthrough videos embedded in the
[easy-file-encryption](https://github.com/justinpearson/easy-file-encryption) tool, and it
ships the scripts that made them as a worked example.

It is written around a few defaults: no personal information in the frame (a cropped capture,
a throwaway browser profile, a solid backdrop, made-up sample files, Finder's sidebar hidden),
videos of 15 to 25 seconds, no audio, asking before taking over the mouse, and restoring every
setting it changed.

## Requirements

- macOS with Google Chrome, ffmpeg, the Swift compiler (`swiftc`, from the Xcode command-line
  tools), and Python 3 with Pillow. Nothing else is installed.
- The terminal running Claude Code needs Screen Recording and Accessibility permission in
  System Settings.
- A recording takes over the mouse and keyboard for a few minutes, so the user has to keep
  hands off while it runs.

## Contents

- `skills/screen-recording-demo/SKILL.md` — the workflow and the defaults.
- `skills/screen-recording-demo/tools/` — the driver (`axd.swift`), the scene setup, take, and
  teardown scripts, and the renderer. Copy this folder into a project and adapt it.
- `skills/screen-recording-demo/references/gotchas.md` — macOS, Chrome, ffmpeg, and shell
  behaviors met while making the first videos, each with its fix.
- `skills/screen-recording-demo/references/publishing.md` — putting the videos in a GitHub
  README and a web page.

Invoke the skill with `/screen-recording-demo:screen-recording-demo`, or just ask for a demo
video; the skill's description is written so Claude picks it up on its own.
