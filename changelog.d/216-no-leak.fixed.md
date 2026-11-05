- A package whose lockfile gets it from your own registry no longer reaches
  a public registry or OSV.dev when Pullwatch could not read that registry:
  on a first check where reading failed, with the source Package registries
  of your accounts off, without permission to read the registry, on Gitea,
  Forgejo, Codeberg and Bitbucket, or when the repository that publishes it
  is not followed. It shows as in-house and not checked instead. The
  Dependencies and Agents pages now list exactly which names stay private
  and which can still reach public services.
