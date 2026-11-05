- A notification when an open pull request leaves the merge queue or merge
  train, or loses auto-merge or auto-complete, without merging: on GitHub
  (with the reason GitHub gives), GitLab, Azure DevOps and Bitbucket Cloud.
  It has its own switch in Settings, Notifications, on by default, follows
  the bell of each repository, and never fires for a pull request that
  merged, closed or became a draft. Agents see it as `left_queue` in
  `get_pull_request`. GitHub pull requests with auto-merge on now show as
  Queued too.
