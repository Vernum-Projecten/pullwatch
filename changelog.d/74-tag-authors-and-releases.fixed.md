- **Tags have an author on GitHub, and releases are shown.** Tags and
  Releases lists each tag with who made it (the person behind a release,
  else the tagger, else the commit author) and its photo, a Release or
  Pre-release label with the release title, and a filter for releases or
  tags without one. A release published after its tag was seen gets one
  notification and updates the same row. A tag without a release opens the
  tag's files instead of a release page that does not exist. GitHub tags
  come from one GraphQL request per ten repositories, and a repository
  where nothing changed costs one small request per fifty. Azure DevOps
  tags without a creator get their tagger or commit author.
