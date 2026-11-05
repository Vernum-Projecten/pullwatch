# Releasing Pullwatch

Pullwatch is released as a signed, notarised macOS app (universal, Apple
Silicon and Intel, macOS 26.6 and later) attached to a GitHub release
`vX.Y.Z`. People install the `.dmg` once; after that the app updates itself
from the same releases through Sparkle 2. Its update check reads the
latest published release's `appcast.xml` once a day. The lane is the one FerroLICENCE uses,
adapted: `.github/workflows/release.yml` runs on a tag and calls the same
`scripts/release/release.sh` the maintainer can run on his Mac.

## Versioning

- `MARKETING_VERSION` in `Pullwatch/App.xcconfig` is the version (SemVer);
  the tag is `v` plus that version.
- `CURRENT_PROJECT_VERSION` in the same file is the build number. It goes
  up by one with every release (a test version included) and never down:
  Sparkle compares build numbers (`sparkle:version` against the app's
  `CFBundleVersion`) and never installs a lower one.
- `CHANGELOG.md` (Keep a Changelog) has a section `## [X.Y.Z] - YYYY-MM-DD`
  for every release; that section is the release's notes. Between releases
  each change waits as a fragment in `changelog.d/` (`changelog.d/README.md`),
  and the cut writes the fragments into that section.

`scripts/release/check-version.sh vX.Y.Z` checks all three, refuses a tag
while `changelog.d/` still holds a fragment, and is the
release workflow's first step. It warns when `Pullwatch/Release.xcconfig`
has no GitHub App (`docs/github-app.md`), because such a release offers only
a token, not Sign in with GitHub.

## What a release holds

| File | For |
|---|---|
| `Pullwatch-X.Y.Z.dmg` | people installing or updating by hand: the install window with the app and a link to Applications |
| `Pullwatch-X.Y.Z.zip` | Sparkle: the app, made by `ditto -c -k --sequesterRsrc --keepParent` so symlinks survive |
| `appcast.xml` | Sparkle's update feed: build number, version, minimum macOS (26.6, from the app's `LSMinimumSystemVersion`), the `.zip`'s size and EdDSA signature, the release notes from `CHANGELOG.md`, and for a test version the `beta` channel |

The app is signed with the Developer ID of Code24 BV (hardened runtime),
notarised and stapled before it is packaged, so the app in the `.zip`
carries its own ticket. The `.dmg` is then signed, notarised and stapled as
well. An update therefore carries three signatures: Sparkle's EdDSA
signature over the `.zip`, the Developer ID signature and Apple's
notarisation, stapled to the app. Sparkle refuses an update without them.

The app's executable ships without symbols. The Release configuration of
the `Pullwatch` target strips it (`DEPLOYMENT_POSTPROCESSING`,
`STRIP_INSTALLED_PRODUCT`, `STRIP_STYLE = all`) and links it without
exported symbols (`LD_EXPORT_SYMBOLS = NO`, which passes
`-no_exported_symbols`), as `pullwatch-mcp` is stripped too; Debug builds
and the test host keep everything. The symbols live on in
`build/Build/Products/Release/Pullwatch.app.dSYM`, which Xcode writes before
it strips and which never goes into the `.dmg` or `.zip`. `release.yml`
uploads it as the workflow artifact `dsym`; download it from the run and
keep it with the release (its UUIDs match the binary, `dwarfdump --uuid`)
to symbolicate a crash report. CI's package job fails when the Release binary still has a
local symbol table or a dSYM ends up in either file.

## How the updater is set up

The setup follows Sparkle's documentation
(<https://sparkle-project.org/documentation/>) and FerroLICENCE's updater,
without FerroLICENCE's token: Pullwatch's releases are public.

- **The package.** Sparkle 2.10.1, pinned to that exact version in
  `Pullwatch.xcodeproj` (`Package.resolved` holds its commit; Swift Package
  Manager checks the binary's checksum from Sparkle's `Package.swift`).
- **Info.plist** (`Pullwatch/Pullwatch/Info.plist`): `SUPublicEDKey` from
  `SPARKLE_PUBLIC_ED_KEY` in `Pullwatch/Release.xcconfig`;
  `SUVerifyUpdateBeforeExtraction` on, so the EdDSA signature is checked
  before the archive is unpacked; `SUEnableAutomaticChecks` off, because
  Pullwatch runs its own daily check and hands Sparkle the feed;
  `SUAllowsAutomaticUpdates` on, behind **Install updates automatically**.
- **The feed.** `https://github.com/<owner>/pullwatch/releases/latest/download/appcast.xml`,
  with `<owner>` from `PW_RELEASES_OWNER` in `Pullwatch/App.xcconfig`
  (`alessandro823`), so a fork with its own releases differs only in that
  setting. GitHub's `releases/latest` never points at a pre-release, so
  with **Include test versions** on the app asks the API (public, no token)
  for the newest release with an `appcast.xml`, and Sparkle's
  `allowedChannels` admits the `beta` channel.
- **No key, no Sparkle.** With `SPARKLE_PUBLIC_ED_KEY` empty (debug builds,
  a build from source, the fork) the app cannot verify an update, so Sparkle
  never starts and the old check stays: a banner and a notification with a
  download button for the `.dmg`.
- **App Sandbox off, Hardened Runtime on.** Sparkle's XPC services are only
  for sandboxed apps, so `release.sh` removes `XPCServices` from
  `Sparkle.framework`, as Sparkle's sandboxing guide allows, and then signs
  `Autoupdate`, `Updater.app` and the framework one by one with hardened
  runtime and a timestamp, without `--deep`, before it signs the app. No
  entitlements are needed.
- **Checks in the lane.** `generate_appcast` writes the feed with the
  private key on stdin (`--ed-key-file -`); `scripts/release/verify-update.swift`
  then checks the `.zip` against the feed's signature and length with the
  public key inside the built app, and that the feed's build number and
  minimum macOS are the app's, so a release whose app carries the wrong key,
  or none, is never attached.

## Secrets, once

The release workflow reads these Actions secrets (repository Settings,
Secrets and variables, Actions, New repository secret). They belong to the
maintainer and never enter the repository. Without them the workflow stops
in its first job and names the missing ones; CI never needs them.

| Secret | What |
|---|---|
| `DEVELOPER_ID_P12` | the Developer ID Application certificate of Code24 BV with its private key, exported from Keychain Access as `.p12`, base64-encoded |
| `DEVELOPER_ID_P12_PASSWORD` | the password chosen at that export |
| `NOTARY_KEY` | an App Store Connect API key for notarisation: the contents of its `.p8` file |
| `NOTARY_KEY_ID` | that key's id |
| `NOTARY_ISSUER_ID` | the issuer id of the team's keys |
| `SPARKLE_PRIVATE_KEY` | Sparkle's EdDSA private key, as `generate_keys -x` exports it |

Making them, on the Mac that has the certificate:

1. **The certificate.** Keychain Access, login keychain, My Certificates:
   select "Developer ID Application: Code24 BV (…)" (it shows the private
   key under it), File, Export Items, format Personal Information Exchange
   (`.p12`), with a new password. Then:

   ```bash
   base64 -i developer-id.p12 | gh secret set DEVELOPER_ID_P12 --repo alessandro823/pullwatch
   gh secret set DEVELOPER_ID_P12_PASSWORD --repo alessandro823/pullwatch   # asks for the password
   rm developer-id.p12
   ```

2. **The notarisation key.** App Store Connect, Users and Access,
   Integrations, App Store Connect API, Team Keys: generate a key with the
   role Developer and download the `.p8` (Apple offers the download once).
   The key id is in the list, the issuer id above it. Then:

   ```bash
   gh secret set NOTARY_KEY --repo alessandro823/pullwatch < AuthKey_XXXXXXXXXX.p8
   gh secret set NOTARY_KEY_ID --repo alessandro823/pullwatch --body XXXXXXXXXX
   gh secret set NOTARY_ISSUER_ID --repo alessandro823/pullwatch --body <issuer id>
   ```

   Keep the `.p8` somewhere safe or delete it; a new key can be made at any
   time and the old one revoked.

3. **Sparkle's key.** Once, on the maintainer's Mac. Build the app in
   Xcode once (or run `xcodebuild -resolvePackageDependencies -project
   Pullwatch/Pullwatch.xcodeproj -scheme Pullwatch -derivedDataPath build`),
   so the Sparkle package is resolved with its tools, then:

   ```bash
   bin=build/SourcePackages/artifacts/sparkle/Sparkle/bin
   "$bin/generate_keys"                   # stores the private key in your login Keychain, prints the public key
   "$bin/generate_keys" -x sparkle.key    # exports the private key for the secret
   gh secret set SPARKLE_PRIVATE_KEY --repo alessandro823/pullwatch < sparkle.key
   rm sparkle.key
   ```

   Put the printed public key in `SPARKLE_PUBLIC_ED_KEY` in
   `Pullwatch/Release.xcconfig` (public, not a secret) and commit it.
   `check-version.sh` refuses a release while it is empty.

   The private key stays in that login Keychain as the only copy that can
   be read back (an Actions secret cannot); back it up with the Keychain.
   With `SUVerifyUpdateBeforeExtraction` on, a lost key cannot be replaced
   through an update: the next release ships a new public key and everyone
   installs that one `.dmg` by hand.

The notarytool profile `pullwatch` in the maintainer's Keychain stays for
releases made on his Mac; CI uses the API key instead.

Optional: `scripts/release/protect-tags.sh alessandro823/pullwatch` creates
a ruleset once that stops `v*` tags from being deleted or moved, so a
published release always points at the commit it was built from.

## Cutting a release

On a branch `release/vX.Y.Z`:

1. Check the notes with
   `bash scripts/release/changelog.sh --preview X.Y.Z`, then run
   `bash scripts/release/changelog.sh --assemble X.Y.Z YYYY-MM-DD`. It
   writes `## [X.Y.Z] - YYYY-MM-DD` under a fresh, empty `## [Unreleased]`
   in `CHANGELOG.md` from the fragments in `changelog.d/`, in Keep a
   Changelog order, updates the links at the bottom and `git rm`s the
   fragments. Read the section and commit it.
2. In `Pullwatch/App.xcconfig`, set `MARKETING_VERSION = X.Y.Z` and raise
   `CURRENT_PROJECT_VERSION` by one.
3. Run the gates (`CLAUDE.md`, Gates) and
   `bash scripts/release/check-version.sh vX.Y.Z`.
4. Merge the pull request. Tag the merge commit on `main` and push the tag:

   ```bash
   git switch main && git pull
   git tag -s vX.Y.Z -m "vX.Y.Z"
   git push origin vX.Y.Z
   ```

5. `.github/workflows/release.yml` runs (watch it with `gh run watch`):
   `plan` (tag, version, changelog, the secrets), `build` on the
   `xcode-27` image (the certificate in a keychain of its own,
   `scripts/release/release.sh`: universal Release build, Sparkle's parts
   signed, signing, notarisation and stapling of the app, the `.dmg` and
   `.zip`, then signing, notarisation and stapling of the `.dmg`; the
   signed `appcast.xml` and its check against the app's key; no build
   cache), `publish` (a draft release "Pullwatch X.Y.Z" with the three
   files and the changelog section as notes).
6. Open the draft on GitHub, download the `.dmg`, check that it opens
   without a warning and that the app starts, then publish the draft. Only
   then do the app's update checks see it: `releases/latest/download/appcast.xml`
   now points at this release.

A test version is a tag `vX.Y.Z-beta.N` on the release branch before the
cut, with `MARKETING_VERSION` already at `X.Y.Z` and
`CURRENT_PROJECT_VERSION` raised by one for each test version (the final
release raises it once more, so it replaces the test version). The same
lane builds it, takes its notes from the fragments still in `changelog.d/`
(`changelog.sh --preview`), puts its appcast item on Sparkle's `beta`
channel and makes a draft pre-release. Only apps with **Include test
versions** on are offered it.

A failed run is fixed and re-run from the Actions page, or, when the code
must change, by a new patch version. If a draft was already created, delete
it before re-running `publish`.

## Releasing from the Mac

`scripts/release/release.sh` still works on its own: with the Developer ID
in the login Keychain and the notarytool profile `pullwatch` it makes the
same signed, notarised `dist/Pullwatch-X.Y.Z.dmg` and `.zip`. The appcast
then comes from `generate_appcast` with the key in the login Keychain:

```bash
mkdir feed && cp dist/Pullwatch-X.Y.Z.zip feed/
bash scripts/release/notes.sh vX.Y.Z > feed/Pullwatch-X.Y.Z.md
build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast --embed-release-notes \
  --download-url-prefix https://github.com/alessandro823/pullwatch/releases/download/vX.Y.Z/ feed
swift scripts/release/verify-update.swift build/Build/Products/Release/Pullwatch.app feed/appcast.xml dist/Pullwatch-X.Y.Z.zip
gh release create vX.Y.Z dist/Pullwatch-X.Y.Z.* feed/appcast.xml
``` The terminal must
be allowed to control Finder (System Settings, Privacy & Security,
Automation) for the install window. `scripts/release/release.sh --unsigned`
makes an ad-hoc signed build for testing; CI runs that on every pull
request.
