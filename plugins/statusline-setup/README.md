# statusline-setup

> **Deprecated.** Use [`session-info-in-footer`](../session-info-in-footer) instead. It shows
> most of the same information, works in the Claude desktop app's Code tab as well as the
> terminal, and installs without a shell script or an edit to `settings.json`. This plugin
> stays available for the two things the mod does not show: the git branch with its
> working-tree status, and the counts of plugins, skills, agents, hooks, and MCP servers.

A skill that installs a multi-line Claude Code status line, distributed as a plugin in the
[`claude-code-stuff`](../../README.md) marketplace.

## Install

```
/plugin marketplace add justinpearson/claude-code-stuff
/plugin install statusline-setup@claude-code-stuff
```

This plugin was called `claude-code-setup` until October 2026, when Claude Code reserved plugin
names that start with `claude-`. If you installed it under the old name, switch to the new one:

```
/plugin uninstall claude-code-setup@claude-code-stuff
/plugin marketplace update claude-code-stuff
/plugin install statusline-setup@claude-code-stuff
```

## The skill

The `statusline-setup` skill installs a status line ("footer") below the prompt in the Claude
Code terminal app:

![Claude Code status line](../../images/status-line.png)

- current model + effort
- context % (bar colored by how much budget remains)
- session cost + time
- cwd + git branch & status
- counts of plugins, skills, agents, hooks, MCPs (by scope)

Invoke it with `/statusline-setup:statusline-setup`. It copies a zsh script into `~/.claude/`
and points the `statusLine` setting in `~/.claude/settings.json` at it; the script needs `jq`
and `git`. The desktop app's Code tab does not draw a status line.
