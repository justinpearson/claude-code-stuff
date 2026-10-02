# Recording tools

Copy this folder into a project as `tools/`. These are the working scripts from the File
Encryption tutorial, so they double as a complete example. The layout they expect is:

```
<project>/
  tools/          this folder, plus tools/bin/axd once built
  sample-files/   made-up files the demo uses
  work/           raw captures, logs, the throwaway Chrome profile (created by the scripts)
  output/         finished videos (created by render.py)
```

## Files

| File | Purpose | What to change for a new tool |
| --- | --- | --- |
| `axd.swift` | Accessibility and input driver: find elements, glide the cursor, click, type, press keys, move and raise windows, log actions. | Nothing. Build it with `swiftc -O tools/axd.swift -o tools/bin/axd`. Run `tools/bin/axd` with no arguments for the command list. |
| `common.zsh` | Settings shared by the zsh scripts: tool URL, window title, demo folder, window and crop geometry, helper functions. | The block marked "Settings specific to the tool", and the geometry if the embed width differs. |
| `setup-scene.zsh` | Opens the backdrop, the tool window, and a Finder window; hides Finder's bars; records original settings; stacks the windows. | Remove the Finder section if the demo does not use Finder. |
| `take.zsh` | Stages and records one take. | The `stage_*` and `run_*` functions and the usage check are specific to the encrypt and decrypt takes. The helpers (`choose_file`, `run_and_save`, `type_password`), the recording functions, and the overall shape carry over. |
| `teardown-scene.zsh` | Restores settings, closes the demo windows, quits the throwaway Chrome, removes the demo folder. | Nothing, unless setup changed other settings. |
| `render.py` | Cuts, speeds up, captions, adds the title card, and encodes. `--frames` writes review stills and `--gif` writes an animated GIF. | Colors and sizes at the top if wanted. |
| `videos.json` | Title, subtitle, and captions for each take. The number of captions must equal the number of `mark step N` lines in that take. | All of it. |

## Commands

```zsh
swiftc -O tools/axd.swift -o tools/bin/axd
tools/setup-scene.zsh
tools/take.zsh encrypt --dry-run      # performs the actions without recording
tools/take.zsh encrypt
tools/take.zsh decrypt
tools/teardown-scene.zsh
python3 tools/render.py all --frames --gif
```

## axd in brief

Every command that targets an element takes a process ID, a scope, and query terms.

```zsh
axd wins $PID                                   # list windows
axd dump $PID "title:File Encryption" 14        # print the accessibility tree
axd moveto $PID "title:File Encryption" id=password-input
axd click
axd type "maple-river-42" 70
axd wait $PID at:160,150 10 role=AXImage "title=Tax Records.zip"
axd menu $PID press View "Sort By" Name
```

Scopes are `app`, `focused`, a window index, `title:<substring>`, or `at:<x>,<y>` (a window's
top-left corner). Query terms are `role=`, `subrole=`, `title=`, `desc=`, `value=`, `id=`, and
`any=`, with `~` in place of `=` for a substring match, plus `nth=N`. For web content, `id=`
matches the element's DOM id, which is the most stable way to find a control.
