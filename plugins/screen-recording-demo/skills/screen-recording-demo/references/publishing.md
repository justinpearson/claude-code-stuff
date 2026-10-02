# Publishing the videos

This covers the two places the File Encryption videos went on 2026-09-30: the repository's
README and the tool's own web page. The pull request is
https://github.com/justinpearson/easy-file-encryption/pull/1.

## Before starting

Find the user's existing clone before making a new one: ask, or look in their usual project
folders. Do not search the whole home folder; it is slow and makes macOS ask the user to let
Terminal read protected folders. In zsh, `ls -d a/*x* b/*x*` aborts on the first glob with no
match, so check one folder per command or use `(N)` glob qualifiers.

Open a pull request instead of pushing to `main` when `main` deploys (GitHub Pages serves the
File Encryption repository from the `main` branch root), and follow whatever pull-request
format the user's CLAUDE.md asks for.

## GitHub README

GitHub's Markdown renderer removes `<video>` tags unless the source is a file uploaded through
GitHub's web editor. Both a relative repository path and a GitHub Pages URL were tested
through the `/markdown` API and came back as an empty paragraph. There is no supported way to
upload such an attachment from the command line.

An animated GIF committed to the repository does render, so use one and make it a link to the
MP4 for viewers who want playback controls:

```md
[![Screen recording: <what it shows>](images/encrypt-demo.gif)](https://<user>.github.io/<repo>/videos/encrypt.mp4)
```

Produce the GIF with `python3 tools/render.py all --gif`. To check how GitHub will render a
snippet before pushing:

```zsh
gh api markdown -f mode=gfm -f context=<owner>/<repo> -f text='<the markdown>'
```

After pushing a branch, `gh api "repos/<owner>/<repo>/readme?ref=<branch>" -H "Accept:
application/vnd.github.html"` returns the rendered README. In a pull-request body, an image in
the branch can be shown with `https://github.com/<owner>/<repo>/blob/<commit-sha>/<path>?raw=true`.

## Embedding in a web page

The request was for the videos to be part of the page only if the page did not grow much.
The approach that kept a single-file, 18.6 KB page at 20.7 KB:

- Keep the MP4 files beside the page (`videos/`), not inline as `data:` URLs, which would have
  added more than a megabyte.
- Put each video inside a collapsed `<details>` with a plain-language summary such as "Watch
  how to encrypt a folder (20 seconds)", placed where a first-time visitor reads it.
- Use `<video controls playsinline preload="none" width height>`, so nothing is fetched until
  the viewer opens the section. A few lines of script play the video on the `toggle` event
  and pause it when the section closes. A video with no audio track may start without being
  muted.
- Give the video an `aria-label` that states the steps, since the captions are burned in.
- Handle the page being used without its videos (saved or emailed on its own): on the video's
  `error` event, replace it with a link to the hosted file.

**Content-Security-Policy.** A page with `default-src 'none'` blocks media. Adding
`media-src 'self'` is enough for both `http(s)` and `file://` copies. On a privacy tool this
is a real change to what the page may fetch, so say so plainly in the pull request and update
any sentence in the docs that promised no network requests.

## Testing the page change

Write a static test first (see `tests/page.test.mjs` in the File Encryption repository): the
video sources exist, are small MP4 files with no audio track, are not preloaded; the page
stays under a size budget; the policy directives match exactly; README link targets exist.

For behavior, the Claude-in-Chrome extension may not be connected and Playwright may not be
installed. A headless Chrome driven over the DevTools protocol needs neither, runs without
appearing on screen, and uses only Node's built-in `fetch` and `WebSocket`.
`references/check-page.mjs` is the script used; its selectors are specific to that page, and
the launch, connect, click, and console-error-collection parts carry over. Serve the folder
with `python3 -m http.server <port> --bind 127.0.0.1` and test four cases: over HTTP with and
without the videos, and as `file://` with and without them.

## Keeping copies in step

The MP4 in the page and the GIF in the README come from the same render. Regenerate both
together, and update durations mentioned in summaries ("20 seconds") if the length changes.
