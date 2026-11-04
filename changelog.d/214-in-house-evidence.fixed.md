- A dependency only counts as in-house when its lockfile shows it comes
  from your own registry (or it is an npm name with your scope), not just
  because one of your repositories publishes a package with the same name.
  A public package that shares a name with one of yours stays public, so
  its known vulnerabilities are reported again, and OSV.dev still checks an
  in-house package whose name the public registry also knows. In-house
  status ends when the publishing account is removed or paused.
