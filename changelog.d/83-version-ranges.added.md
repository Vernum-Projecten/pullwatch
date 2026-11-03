- The version check keeps the range each manifest asks for next to the installed version (npm, yarn
  and pnpm, Composer, PyPI and Poetry, Cargo, NuGet, RubyGems, Go modules and Swift packages), and
  works out per install whether the newest version fits that range, so only the lockfile changes,
  or needs a manifest change, and whether the step is a patch, minor or major update.
