# Releasing Pullwatch

Pullwatch is released as a signed, notarised macOS app (universal, Apple
Silicon and Intel, macOS 26.6 and later) attached to a GitHub release
`vX.Y.Z`. People install the `.dmg`; the app's update check reads the
latest published release once a day. The lane is the one FerroLICENCE uses,
adapted: `.github/workflows/release.yml` runs on a tag and calls the same
`scripts/release/release.sh` the maintainer can run on his Mac.

## Versioning

- `MARKETING_VERSION` in `Pullwatch/App.xcconfig` is the version (SemVer);
  the tag is `v` plus that version.
- `CURRENT_PROJECT_VERSION` in the same file is the build number. It goes
  up by one with every release and never down: the coming updater (Sparkle,
  #9) compares build numbers and never installs a lower one.
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
| `Pullwatch-X.Y.Z.zip` | the coming updater (#9): the app, made by `ditto` so symlinks survive |

The app is signed with the Developer ID of Code24 BV (hardened runtime),
notarised and stapled before it is packaged, so the app in the `.zip`
carries its own ticket. The `.dmg` is then signed, notarised and stapled as
well. The appcast for Sparkle is added by #9; `release.yml` marks the spot.

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

The notarytool profile `pullwatch` in the maintainer's Keychain stays for
releases made on his Mac; CI uses the API key instead.

Sparkle's private key (`SPARKLE_PRIVATE_KEY`) joins this table with #9.

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
   `scripts/release/release.sh`: universal Release build, signing,
   notarisation and stapling of the app, the `.dmg` and `.zip`, then
   signing, notarisation and stapling of the `.dmg`; no build cache),
   `publish` (a draft release "Pullwatch X.Y.Z" with both files and the
   changelog section as notes).
6. Open the draft on GitHub, download the `.dmg`, check that it opens
   without a warning and that the app starts, then publish the draft. Only
   then do the app's update checks see it.

A failed run is fixed and re-run from the Actions page, or, when the code
must change, by a new patch version. If a draft was already created, delete
it before re-running `publish`.

## Releasing from the Mac

`scripts/release/release.sh` still works on its own: with the Developer ID
in the login Keychain and the notarytool profile `pullwatch` it makes the
same signed, notarised `dist/Pullwatch-X.Y.Z.dmg` and `.zip`, to upload by
hand (`gh release create vX.Y.Z dist/Pullwatch-X.Y.Z.*`). The terminal must
be allowed to control Finder (System Settings, Privacy & Security,
Automation) for the install window. `scripts/release/release.sh --unsigned`
makes an ad-hoc signed build for testing; CI runs that on every pull
request.
