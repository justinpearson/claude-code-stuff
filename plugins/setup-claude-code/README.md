# setup-claude-code

Recommended Claude Code configuration, distributed as a plugin in the
[`claude-code-stuff`](../../README.md) marketplace.

## Install

```
/plugin marketplace add justinpearson/claude-code-stuff
/plugin install setup-claude-code@claude-code-stuff
```

This plugin was called `claude-code-setup` until October 2026, when Claude Code reserved plugin
names that start with `claude-`. If you installed it under the old name, switch to the new one:

```
/plugin uninstall claude-code-setup@claude-code-stuff
/plugin marketplace update claude-code-stuff
/plugin install setup-claude-code@claude-code-stuff
```

## Skills

### `/statusline-setup`

Installs a multi-line status line ("footer") to Claude Code, with various nice stats:

![Claude Code status line](../../images/status-line.png)

- current model + effort
- context % (bar colored by how much budget remains)
- session cost + time
- cwd + git branch & status
- counts of plugins, skills, agents, hooks, MCPs (by scope)

Invoke it with `/setup-claude-code:statusline-setup`.
