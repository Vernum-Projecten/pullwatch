# AI policy

This page covers two things: using AI tools to contribute to Pullwatch, and
what Pullwatch itself does with AI.

## Contributing with AI tools

You may use AI tools (coding assistants, agents, chat) for any part of a
contribution. What applies to every contribution applies to yours:

- **You are responsible for every line.** You submit it, so you answer for
  it in review, as if you wrote it by hand.
- **You understand it.** You can explain what each change does and why, and
  you can change it when a reviewer asks.
- **You tested it.** It passes the gates in [CONTRIBUTING.md](CONTRIBUTING.md),
  and a UI change was looked at in the running app.
- **You can license it.** Submit only what you have the right to contribute
  under the [Apache License 2.0](LICENSE). Do not submit generated code that
  copies someone else's work under terms that do not allow this.
- **It follows the project's rules**, as [CLAUDE.md](CLAUDE.md) and
  [.claude/rules/swift.md](.claude/rules/swift.md) set them out. Both are
  written to be read by people and by coding agents alike.

You do not have to say whether or how you used AI. Commits and pull
requests carry no AI attribution: no `Co-authored-by` line for a tool, no
"Generated with" line, no robot emoji. A commit describes the change, and
its author is the person who submits it. The `commit-msg` hook in
`.githooks/` removes such lines.

Pull requests, issues and comments are read by a person. Keep them short
and specific to Pullwatch, and check generated prose for the tells the
project avoids (em dashes, a middle dot as a separator, buzzwords).

## What Pullwatch does with AI

Pullwatch contains no AI model and sends nothing to an AI service. Two
features let an AI agent you already use work with what Pullwatch knows:

- **Copy for an AI Agent** puts a section of a repository page on the
  clipboard as a Markdown brief. Nothing leaves your Mac until you paste it.
- **Agents (MCP)**: an optional local server for coding agents on your Mac,
  through the `pullwatch-mcp` helper inside the app. It is
  - **off by default**: Settings, Agents turns it on, either while Pullwatch
    is open or always;
  - **read-only**: its tools list pull requests, tags, repositories, version
    reports and vulnerabilities, and nothing can comment, merge, push or
    change a setting;
  - **approved per agent**: the first time an agent connects, Pullwatch asks
    whether to allow it, and until you do, it gets no data. You can remove
    an approval or disconnect an agent at any time;
  - **local only**: a socket in Pullwatch's data folder that only the
    signed helper of your own user account can open. It shows only the
    repositories you follow, accounts as name and host, and never a token.

Pullwatch itself sends nothing anywhere for these features. What an agent
does with the answers it gets, such as sending them to its model provider,
is between you and that agent. The website's
[Agents](https://pullwatch.net/agents/) page explains the setup,
[docs/mcp.md](docs/mcp.md) the design, and [SECURITY.md](SECURITY.md) how
to report a problem with the helper or its socket.
