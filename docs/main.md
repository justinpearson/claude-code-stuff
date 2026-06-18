---
title: Claude Code Tutorial
---

# Happy Justin's Claude Code Tutorial

## Introduction

- A sequel to "Grumpy Justin's Ruby Tutorial" (http://justinppearson.com/projects/ruby-tutorial.html)
- A technical intro to core AI / LLM concepts
- An "applied" intro to Claude Code


## Skills vs MCP

### MCP

MCP is basically an API to an external server. When you install an MCP into Claude Code you specify a server. CC then asks the MCP server for a list of "MCP tools" (basically API endpoints). (There's also some kind of auth.) CC caches this tool list somewhere. Like all tools, each MCP tool has a name and description, which the harness includes in the context window at the beginning of every session, so the model knows what tools it has available. When the model does a tool-call on an MCP tool, the harness basically hits that server's endpoint and feeds the result back into the context window. So: an MCP tool is an external function that the model can call.

### Skills

Now for skills. Skills are files like ~/.claude/skills/my-wolfram-skill/SKILL.md, with optional additional supporting files alongside SKILL.md. Each skill has a name (derived from the file path, eg, my-wolfram-skill) and a description (in the SKILL.md's yaml frontmatter). Like all tools, the harness includes each skill's name & description in the context window at session-start, so the model knows what tools it has available. When the model calls a skill, the harness loads the rest of SKILL.md into the context window. This gives the model additional context to help it with the task at hand. So: A skill adds context to the context window, to give the model important background knowledge, or to teach the model how to do something. Skills can also be manually invoked by the user: `/my-wolfram-skill plz OCR this pic: img.png`. You can even make a skill ONLY invokable by the user (not by the model) by setting `disable-model-invocation: true` in the SKILL.md's yaml frontmatter. This makes a skill act like a "command" (a previous Claude Code feature that got subsumed into skills).

### Skills can build on MCPs

You can combine MCP tools and skills. Example: We have a "jira" skill that teaches Claude how to work around some of the deficiencies of the official Jira MCP. Specifically, at AF, our "bug" cards have a lot of required fields, like "# of customers affected", and the Jira MCP doesn't seem to expose a way for Claude to discover these required fields. So we made a jira skill that includes in SKILL.md instructions like "To make a bug card, you first need to discover the required fields via the Atlassian CLI (`acli`) like this: ... . Then you create the bug card via the Jira MCP like this: ..."