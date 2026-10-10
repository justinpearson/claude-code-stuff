# session-info-in-footer

A Claude Code mod that draws two lines of session information just above the prompt, in the
terminal and in the Claude desktop app's Code tab. It is distributed as a plugin in the
[`claude-code-stuff`](../../README.md) marketplace.

<!-- screenshot here -->

## Install

```
/plugin marketplace add justinpearson/claude-code-stuff
/plugin install session-info-in-footer@claude-code-stuff
```

The band appears in sessions started after the install.

## What it shows

```
Opus 5.5 · high   █████████░ 96% ctx   $1.23 · 1h35m   cache warm until 2:47 PM   🕐 1:52 PM
📁 ~/agents/app   proj: ~/agents   repo: me/agents
```

The first line shows the model, the effort level, how much of the context window is left (a
10-cell bar that is green from 70%, orange from 40%, and red below), the session's cost, the
time since the session started, when the prompt cache expires, and the current time. The
second line shows the working directory, the project directory when it differs, and the git
repository as `owner/name` from its `origin` remote.

The cost is what the session's usage would cost at API prices, as `/cost` reports it. On a
Pro or Max plan you are not billed that amount; the usage counts against your plan's limits.

The effort level appears after the first reply, because Claude Code reports it only on each
model request. An item the session does not report, such as the repository outside a git
checkout, is left out.

## The prompt-cache warning

Each message re-sends the whole conversation, and the API serves the unchanged part from a
prompt cache at a small fraction of the input price. The cache expires after a period of
inactivity: one hour for the main conversation on a Claude subscription within plan usage, and
five minutes with an API key, a cloud provider, or once usage credits apply. After it expires,
the next message re-sends the entire context and pays the cache-write price for all of it,
which for a large session can cost as much as dozens of ordinary messages. See
[How Claude Code uses prompt caching](https://code.claude.com/docs/en/prompt-caching).

The band shows `cache warm until <time>` after each request. Five minutes before a one-hour
cache expires (one minute for a five-minute cache), the text turns orange and a toast suggests
running `/compact` if you are stepping away, since a compacted session re-sends only its
summary. Once the time passes, the band shows `cache cold since <time>`.

The expiry is an estimate from timing, because Claude Code does not report a cache's TTL to
plugins. The mod uses the `promptCacheTtl` setting when it is set; otherwise it assumes one
hour when the session reports plan usage windows that are all under 100%, and five minutes
otherwise. It does not detect cache misses with other causes, such as switching models.

## Requirements and caveats

- A Claude Code version with mods (function-hook modules). It was written against v2.1.293.
- Mods are an early-access part of Claude Code; their API "may change between releases without
  notice", so a later release can break the band. If it disappears, start Claude Code with
  `--debug` and look for lines naming `session-info-in-footer`.
- The band redraws once a minute, at the top of the minute, to keep the clock current.
- It does not replace a `statusLine` script; if you have one, the terminal shows both.

## Contents

- `hooks/hooks.json` names the hooks module.
- `hooks/register.tsx` is the mod: a `ui.render` hook that draws the band, a `turn.step` hook
  that records the effort level and the time of each request, and timers for the cache warning.
- `hooks/register.test.tsx` holds tests that run with `claude plugin test plugins/session-info-in-footer`.

## Develop

Run the checks from the repository root:

```
claude plugin validate plugins/session-info-in-footer
claude plugin test plugins/session-info-in-footer
```

To try local edits, either start Claude Code with `--plugin-dir plugins/session-info-in-footer`
or copy the folder into `~/.claude/skills/`, which Claude Code loads as a plugin because of
the `.claude-plugin/plugin.json` at its top. Remove the installed marketplace copy first, since
two copies draw two bands.
