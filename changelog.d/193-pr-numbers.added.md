- Pull requests show their number as the service writes it: `#1570` on
  GitHub, Bitbucket, Gitea, Forgejo and Codeberg, `!42` for GitLab merge requests and Azure DevOps pull
  requests. The Repo column of the list reads `FerroFED #1570` and sorts a
  repository's pull requests by number, the menu panel and the repository
  page show the number, and a notification names
  `FerroHEALTH/FerroFED #1570`. Search finds a pull request by `1570`,
  `#1570`, `!42`, `FerroFED#1570` or `FerroHEALTH/FerroFED#1570`. Item, Copy
  Reference (Option-Shift-Command-L) copies `FerroHEALTH/FerroFED#1570`, and
  agents get the same `reference` from `list_pull_requests` and
  `get_pull_request`. The pull requests on a repository page show their
  state with the same icon as the list instead of a text label.
