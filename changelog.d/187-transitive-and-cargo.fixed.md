- Rust packages get an update status again: Pullwatch reads the requested
  range from every `Cargo.toml` of a workspace, including the
  `[workspace.dependencies]` that members take over with `workspace = true`,
  renamed packages, dev, build and target-specific dependencies. A status
  that stays unknown now says why (no latest version, no requested range,
  a range it cannot read), in the app and for agents.
- A vulnerable package that only comes in through another package can be
  found and explained: Dependencies lists it under "Only transitive, with a
  vulnerability" with the chain that pulls it in, and `explain_update` and
  `get_repository_report` explain it too, including whether the fix only
  changes the lockfile or needs a newer parent first. A version check made
  by an older Pullwatch runs again by itself.
