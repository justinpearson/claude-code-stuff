# claude-code-stuff

Justin Pearson's personal Claude Code [plugin marketplace](https://code.claude.com/docs/en/plugin-marketplaces), plus some docs about Claude Code and LLMs + AI in general.

Docs hosted on GH Pages here: https://justinpearson.github.io/claude-code-stuff

## Install + use

Add the marketplace, then install a plugin from it:

```
/plugin marketplace add justinpearson/claude-code-stuff
/plugin install claude-code-setup@claude-code-stuff
```

The marketplace catalog lives in
[`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json).

## Plugins

### `claude-code-setup`

Recommended Claude Code configuration. It bundles the `statusline-setup` skill
(see [`plugins/claude-code-setup`](plugins/claude-code-setup)):

- **`statusline-setup`** — installs a nice multi-line Claude Code status line:

  ![Claude Code status line](images/status-line.png)

After installing, invoke a skill by its namespaced name, for example
`/claude-code-setup:statusline-setup`.

## Docs

Notes on Claude Code and LLMs / AI, in [`docs/`](docs/), published to GitHub
Pages at <https://justinpearson.github.io/claude-code-stuff>:

- [Happy Justin's Claude Code Tutorial](docs/main.md)
- [User-level Claude Code memory file (my `CLAUDE.md`)](docs/my-CLAUDE.md)

## Other contents

- [`tools/`](tools/) — standalone scripts that are not (yet) packaged as plugins.


## TODO

Things to add:

- /statusline
- CLAUDE.md snippets
- handy skills
- hidden files and folders, hard to find .claude
- handy hooks
	- notifier
- quick-start & tutorial
- disc of user vs proj settings etc
- swimline diagram -- what's an agent, harness, model, etc.
	- different models, harnesses (Pi), ai labs
- LLM Wiki?
- my POV on where software engineering is heading (as of may 2026)
	- ai code review
	- ai software development
		- do you "understand" what it's doing?
	- ai quality-assurance
	- ai security
		- zerodayclock.com, automated systems for CVE fixing
- wiki / posts
	- openclaw
