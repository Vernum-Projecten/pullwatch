- The version check keeps every install of a package: its version, its
  workspace, direct or transitive, runtime, dev or optional, and the
  shortest chain from a direct package. A package used in two versions is
  no longer folded into the oldest one, and each vulnerability is listed
  for every install it hits. Older saved checks still load.
