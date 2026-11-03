- GitHub Enterprise accounts, on GitHub Enterprise Server or your enterprise's subdomain on
  GHE.com (https only): choose GitHub Enterprise on the GitHub card in the welcome window or
  in the add menu under Settings, Accounts, and enter your server. Pullwatch follows pull
  requests, tags and releases there, links to that server and shows its host on the account
  card. Sign in with a personal access token made on the server or with the GitHub CLI
  (`gh auth login --hostname`). What a server lacks, such as a repository's own advisories
  on GitHub Enterprise Server, shows as not available instead of an error.
