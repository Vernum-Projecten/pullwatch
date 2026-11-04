- A new section, Packages (Command-6), lists what the repositories you
  follow publish to the registry of their own service: npm, NuGet, Maven and
  other packages and container images from GitHub Packages, GitLab and Azure
  Artifacts. One row per package with its latest version and which of your
  repositories use it; the inspector shows the recent versions and who is on
  which one. A repository's Overview names what it publishes, and a new
  notification, off by default, tells you about a new version of your own
  packages. Agents can ask for the same with the new `list_packages` tool.
- A dependency that one of your repositories publishes, and that the
  lockfile shows comes from your own registry (or an npm name with your
  scope), now gets its latest version from that registry and says In-house,
  instead of being unknown. Its name is never sent to a public registry, and
  OSV.dev only sees it when the public registry knows the name too. A public
  package with the same name as one of yours stays public, with its known
  vulnerabilities. Settings, Sources has a switch for the package registries
  of your accounts.
- The repository page's Packages tab is now called Dependencies, the same
  as the section in the sidebar.
