- The version check now reads what each package version asks for from its registry (npm,
  Packagist, crates.io, NuGet, RubyGems, PyPI and the Go proxy) and works out what holds an
  update back: a parent package whose range pins it, a peer dependency, or a runtime (Node, PHP,
  Python, Rust, .NET, Ruby, Go) that is older than the new version needs. It also finds the
  newest version you can use right now, and the lowest parent version that lets a fix through.
  Vulnerability fixes use the same rules. Details per version are kept between checks, so a
  check asks the registries for little more than before.
