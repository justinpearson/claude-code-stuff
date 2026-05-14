/statusline help me make a decent Claude Code status line "footer". I want to show things like:

- current model & effort level
- session time & cost
- % available context window, colored like this:
	- 80-100% available: green
	- 50-80% avail: orange
	- 20-50% avail: red
	- 1-20% avail: dark red
	- 0-1% avail: black (corner case at session startup)
- cwd
- project dir
- Git branch and status

I'm ok with the statusline spanning multiple lines, as long as it doesn't interfere with Claude Code's normal operation. It seems to be supported:

https://code.claude.com/docs/en/statusline#display-multiple-lines

Lastly, I'd like to display information about skills, plugins, and marketplaces, if possible.

As background, the `/reload-plugins` command displays valuable info:

"2 plugins · 0 skills · 6 agents · 0 hooks · 0 plugin MCP servers · 1 plugin LSP server"

I'd like this kind of information to be present in my statusline, because a common pitfall is that I don't have the right plugins enabled or an MCP is un-authenticated, or something. What are my options here?

For example, I'd like statusline to show:

"2/4 plugins on · 3 skills (2/0/1) · 6 agents (0/0/0/6) · 4 hooks (2/1/1) · 2 MCPs (2/0/1)"

- `2/4 plugins on`: how many enabled / total plugins are installed. FYI that info is displayed from `claude plugins list` but maybe Claude has that info available internally too.

- `3 skills (2/0/1)`: number of Claude Code non-built-in skills currently available, in the format user/proj/plugin, eg "4/0/5" means there are 4 skills provided by ~/.claude/skills, 0 skills availble from <proj_dir>/.claude/skills, and 5 skills available from currently-enabled plugins.
- `6 agents (0/0/0/6)`: number of Claude Code subagents currently available, in the same format as above, but the 4th number is the number of built-in ones that are displays via the `/agents` command, eg,

```
> /agents

...

    Built-in (always available):
    claude · inherit
    claude-code-guide · haiku
    Explore · haiku
    general-purpose · inherit
    Plan · inherit
    statusline-setup · sonnet
```

- `4 hooks (2/1/1)`: same as the "skills" bullet: user/proj/plugin

- `2 MCPs (2/0/1)`: same as the "skills" bullet: user/proj/plugin. Also the entire string is colored orange if any MCP is unauthenticated.

Let's write this into a shell script. For testing purposes, please also include a "test script" that I can run at the terminal, that pipes some example session data into our statusline shell script, the same way Claude Code would invoke the statusline shell script.
