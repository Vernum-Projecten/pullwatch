# Getting help with Pullwatch

Pullwatch is maintained by one person in their own time. Help is best
effort, and the documentation answers most questions fastest.

## Read first

- [Documentation](https://pullwatch.net): every screen and setting.
- [FAQ](https://pullwatch.net/faq/): the common questions.
- [Troubleshooting](https://pullwatch.net/troubleshooting/): notifications,
  accounts, missing repositories, permissions, Keychain prompts and logs.
- [Privacy and sources](https://pullwatch.net/privacy/): what is sent where.

## Ask or report

- **A bug:** open a [bug report](https://github.com/alessandro823/pullwatch/issues/new?template=bug_report.yml).
- **An idea:** open a [feature request](https://github.com/alessandro823/pullwatch/issues/new?template=feature_request.yml).
- **A question the website does not answer:** open an
  [issue](https://github.com/alessandro823/pullwatch/issues/new/choose) and
  say what you looked for. The repository has no Discussions.
- **A vulnerability:** privately, as [SECURITY.md](SECURITY.md) describes;
  never in an issue.

Search the [open and closed issues](https://github.com/alessandro823/pullwatch/issues?q=is%3Aissue)
first; your question may already have an answer.

## What a bug report needs

- the Pullwatch version (About Pullwatch) and the macOS version, and whether
  the Mac has Apple silicon or Intel;
- the service (github.com, GitHub Enterprise Server, GHE.com, Azure DevOps,
  gitlab.com or a self-managed GitLab) and how the account signs in (**Sign
  In with GitHub**, a token, or `gh`, `az` or `glab`);
- the steps that show the problem, what you expected and what happened;
- the log around the moment it happened. Set Settings, General, **Log
  Level**, then run

  ```bash
  log stream --predicate 'subsystem == "nl.torrisi.pullwatch"'
  ```

  or search Console for `nl.torrisi.pullwatch`.

Remove tokens, and the names of private repositories you would rather not
share, before you post a log or a screenshot.
