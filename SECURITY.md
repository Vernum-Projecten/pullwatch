# Security policy

## Supported versions

Only the latest release of Pullwatch gets security fixes. Pullwatch updates
itself; **Check for Updates…** in the Pullwatch menu fetches the latest one.
A fix lands in a new release, never in an older version.

## Report a vulnerability

Report it privately through GitHub's
[private vulnerability reporting](https://github.com/alessandro823/pullwatch/security/advisories/new)
(the repository's **Security** tab, **Report a vulnerability**). Do not open a
public issue, pull request or comment about it.

Include what you can:

- the Pullwatch version (About Pullwatch) and the macOS version;
- what an attacker can do, and what they need first;
- the steps to reproduce it, or a proof of concept;
- any idea for a fix.

## What happens next

Pullwatch has one maintainer, who aims for:

- an acknowledgement within a week;
- a first assessment, and whether it is accepted, within two weeks;
- a fix in a release as soon as it is ready, with a GitHub security advisory
  published at the same time, crediting you unless you prefer otherwise.

Please keep the report private until the advisory is published.

## Scope

In scope:

- **The app**: how it stores and uses tokens (the macOS Keychain, or the
  `gh`, `az` and `glab` tools), what it sends where, and the data in its
  folder (`~/Library/Application Support/Pullwatch`).
- **The `pullwatch-mcp` helper and its socket**: the helper in
  `Pullwatch.app/Contents/Helpers/`, the socket `mcp.sock` in the data
  folder, the check of every connecting process (same user, signed as the
  helper), the approval per agent, and anything an agent can get through
  the tools beyond the read-only data they describe.
- **Updates**: the update feed (`appcast.xml`), its Sparkle EdDSA signature
  and the check against the key inside the app, and the Developer ID
  signing and notarisation of the app, the helper and the disk image.
- **The release lane**: the workflows and scripts in this repository that
  build, sign and publish a release.

Out of scope:

- the services Pullwatch talks to (GitHub, GitLab, Azure DevOps, OSV.dev,
  the package registries and the others listed under Settings, Sources):
  report to them;
- an attack that needs an administrator account or full control of the Mac
  already;
- what an agent you approved does with the read-only data Pullwatch gives
  it;
- a known vulnerability in a dependency that does not affect Pullwatch.
  When it does affect Pullwatch, report it here.
