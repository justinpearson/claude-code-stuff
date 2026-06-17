# claude-code-setup

Recommended Claude Code configuration, distributed as a plugin in the
[`claude-code-stuff`](../../README.md) marketplace.

## Install

```
/plugin marketplace add justinpearson/claude-code-stuff
/plugin install claude-code-setup@claude-code-stuff
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

Invoke it with `/claude-code-setup:statusline-setup`.

### `/learn-skills-and-mcp`

A primer on how MCP servers and skills work in Claude Code: what each one is, how
the harness surfaces it to the model, what happens on invocation, how they
differ, and how to combine an MCP with a skill.

Invoke it with `/claude-code-setup:learn-skills-and-mcp`.
