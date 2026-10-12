---
description: Install Justin's recommended multi-line Claude Code status line. It shows the model and effort level, a colored context-window budget bar, session cost and time, the cwd and git branch/status, and counts of available plugins, skills, agents, hooks, and MCP servers. Use this when setting up or customizing the Claude Code status line ("footer").
---

# Statusline setup

This skill installs a multi-line status line for Claude Code. The script and its
test harness live in [`scripts/`](scripts/) alongside this file:

- `scripts/statusline-command.sh` — the status line itself (reads session JSON on stdin, prints the footer).
- `scripts/statusline-test.sh` — a test harness that pipes representative session JSON into the script so you can eyeball every output line.

## What it shows

The footer spans three lines (multi-line status lines are
[supported](https://code.claude.com/docs/en/statusline#display-multiple-lines)):

1. **Model and effort**, a 10-cell context-window budget bar with the percentage still available, and session cost and elapsed time.
2. **Directories** (cwd, plus the project dir when it differs) and **git** branch, dirty/clean state, and ahead/behind tracking.
3. **Counts** of currently-available plugins, skills, agents, hooks, and MCP servers, broken down by scope.

The context-window bar is colored by how much budget remains: green at 80–100%
available, orange at 50–80%, red at 20–50%, dark red at 1–20%, and black in the
startup corner case before any context data exists.

The third line's counts are derived by reading local config files
(`~/.claude/settings.json`, `~/.claude/plugins/*.json`, and the `.claude`
directories), because that information is not present in the session JSON. They
are a best-effort reflection of Claude Code's internal view. The scope
breakdowns read `(user/project/plugin)`; the agents segment adds a fourth number
for built-in agents.

## Requirements

The script is `zsh` and depends on `jq` and `git` being on `PATH`. Confirm with
`jq --version` and install it (`brew install jq`) if it is missing.

## Install

The steps below assume the standard config dir `~/.claude`. If you set
`CLAUDE_CONFIG_DIR`, substitute that path. Copy the script (and, optionally, the
test harness) into the config dir, make them executable, and point the
`statusLine` setting at the installed script.

1. Copy the scripts from this skill's `scripts/` directory into `~/.claude/`:

   ```zsh
   cp scripts/statusline-command.sh ~/.claude/statusline-command.sh
   cp scripts/statusline-test.sh   ~/.claude/statusline-test.sh
   chmod +x ~/.claude/statusline-command.sh ~/.claude/statusline-test.sh
   ```

2. Add a `statusLine` entry to `~/.claude/settings.json` (create the file if it
   does not exist), merging it into any settings already present:

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "~/.claude/statusline-command.sh",
       "padding": 0
     }
   }
   ```

3. Verify the output before relying on it by running the test harness, which
   pipes sample session JSON through the script the same way Claude Code does:

   ```zsh
   ~/.claude/statusline-test.sh          # run every scenario
   ~/.claude/statusline-test.sh fresh    # run one scenario by name
   ```

   Scenario names are `fresh`, `mid`, `low`, `critical`, and `empty`. Each
   exercises a different context-color band so you can confirm the bar renders
   the way you expect.

4. Open a new Claude Code session (or reload settings) to see the status line.

## Known limitation

MCP authentication state is tracked inside Claude Code, not in any file the
script can read reliably, so unauthenticated servers cannot currently be
flagged. The orange-warning wiring is left in place in the script (set
`MCP_WARN=1` if you find a usable signal); for now the MCP segment uses its
normal color.

## Original design spec

The status line was generated from this prompt, kept here as the rationale for
what each segment is meant to convey:

> Help me make a decent Claude Code status line "footer". I want to show things like:
>
> - current model & effort level
> - session time & cost
> - % available context window, colored like this:
>     - 80-100% available: green
>     - 50-80% avail: orange
>     - 20-50% avail: red
>     - 1-20% avail: dark red
>     - 0-1% avail: black (corner case at session startup)
> - cwd
> - project dir
> - Git branch and status
>
> I'm ok with the statusline spanning multiple lines, as long as it doesn't interfere with Claude Code's normal operation.
>
> Lastly, I'd like to display information about skills, plugins, and marketplaces, if possible. As background, the `/reload-plugins` command displays valuable info: "2 plugins · 0 skills · 6 agents · 0 hooks · 0 plugin MCP servers · 1 plugin LSP server". A common pitfall is that I don't have the right plugins enabled or an MCP is un-authenticated. For example, I'd like statusline to show:
>
> "2/4 plugins on · 3 skills (2/0/1) · 6 agents (0/0/0/6) · 4 hooks (2/1/1) · 2 MCPs (2/0/1)"
>
> - `2/4 plugins on`: how many enabled / total plugins are installed.
> - `3 skills (2/0/1)`: number of non-built-in skills available, in the format user/proj/plugin.
> - `6 agents (0/0/0/6)`: number of subagents available, same format, but the 4th number is the count of built-in agents.
> - `4 hooks (2/1/1)`: same user/proj/plugin format.
> - `2 MCPs (2/0/1)`: same format; the whole string is colored orange if any MCP is unauthenticated.
>
> Let's write this into a shell script. For testing, also include a test script that pipes example session data into the statusline script the same way Claude Code would.
