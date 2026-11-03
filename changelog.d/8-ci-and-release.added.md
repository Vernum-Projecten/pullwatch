- **CI and a release workflow.** Every pull request runs the package tests,
  the app's unit and UI tests and an unsigned release build with the disk
  image. A tag `vX.Y.Z` builds, signs, notarises and packages the release
  and attaches it to a draft GitHub release.
