# Hoofdvenster en package-versies Implementation Plan

> Noot (4 november 2026): Dit plan noemt bestanden zoals ze toen heetten. Sinds de opruiming van #112 staan de bronnen per module en gebied (`PullwatchKit/Sources/<Module>/<Gebied>/`, `Pullwatch/Pullwatch/App/` en `Views/`) en zijn de grote bestanden per onderdeel gesplitst; `CLAUDE.md` geeft de huidige indeling. XcodeGen (`project.yml`) is vervangen door het vastgelegde `Pullwatch/Pullwatch.xcodeproj`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eén hoofdvenster met zijbalk (PR's, Tags, Repo-controle, Versies) en een nieuw onderdeel Versies dat per package/runtime-cyclus toont welke repo's achterlopen, met een gebundelde melding bij nieuwe versies.

**Architecture:** De bestaande `VersionChecker`-run levert per repo ook de directe packages (`PackageUse`) en per uniek package de nieuwste versie uit het register (`PackageRegistry`). `VersionReport` bewaart die en rekent `packageSummaries()` uit; de UI toont alleen. Runtimes vergelijken binnen hun cyclus via `ComponentVersion.cycleLatest`.

**Tech Stack:** Swift 6, SwiftUI (`NavigationSplitView`, macOS 14), XCTest/Swift Testing zoals in `Tests/PullwatchCoreTests`, `MockHTTPClient`.

**Spec:** `docs/superpowers/specs/2026-11-01-hoofdvenster-en-package-versies-design.md`

## Global Constraints

- macOS 14; geen nieuwe dependencies.
- Alle nieuwe UI-strings en Core-strings in `Localizable.xcstrings` (NL bron, EN/DE/FR vertaald).
- Oude `versions.json` en `config.json` blijven laden (`decodeIfPresent` met default).
- Commentaar in het Nederlands, zelfde dichtheid als omliggende code.
- `make test` groen na elke Core-taak; `make build` groen na elke App-taak.

## Review Focus

1. Go-modulepad met hoofdletters (`github.com/BurntSushi/toml`) → proxy-URL met `!b` escaping; anders "Niet te checken".
2. Go-proxy `@latest` met pseudo-versie (`v0.0.0-2024…`) → geen nieuwste versie (nil), niet "achter".
3. Gebruikte versie zonder patch (`1.27`) tegen `1.27.4` → niet achter.
4. Eerste check zonder vorige `latestPackages` → geen melding.
5. Scoped npm-naam `@angular/core` → URL `@angular%2fcore`.

---

### Task 1: Hoofdvenster met zijbalk

**Files:**
- Create: `App/MainView.swift`
- Modify: `App/PullwatchApp.swift`, `App/MenuView.swift`, `App/HistoryView.swift`, `App/AppModel.swift`, `App/Localizable.xcstrings`

**Interfaces:**
- Produces: `enum MainSection: String, CaseIterable { case pullRequests, tags, repoCheck, versions }`; `AppModel.mainSection: MainSection` (observable, startwaarde uit `UserDefaults` "mainSection"); `Window` id `"main"`; `HistoryView(model:kind:)` met vaste `ItemKind`.

- [ ] Vervang de `Window`s `history` en `versions` door `Window("Pullwatch", id: "main") { MainView(model:) }`.
- [ ] `MainView`: `NavigationSplitView` met zijbalk-`List(selection:)` over `MainSection`, badges (`.badge`) PR's/Tags = ongelezen per soort, Versies = 0 (Task 8 vult in). Detail: `HistoryView(kind: .pullRequest)`, `HistoryView(kind: .tag)`, `VersionsView` (titel "Repo-controle"), placeholder voor Versies.
- [ ] `HistoryView`: segmented filter weg; `showVersions(of:)` zet `model.versionsSearch` + `model.mainSection = .repoCheck`.
- [ ] Menu: "Geschiedenis…" en "Versies…" → één "Openen…" (`openWindow(id: "main")`).
- [ ] `make build` → BUILD SUCCEEDED. Handmatig: venster opent, vier onderdelen werken, sprong vanuit geschiedenis naar Repo-controle werkt.
- [ ] Commit `feat: one main window with a sidebar`.

### Task 2: Directe dependencies

**Files:** Modify `Sources/PullwatchCore/DependencyDetector.swift`, `Sources/PullwatchCore/VersionCheck.swift` (scan); Test `Tests/PullwatchCoreTests/VersionCheckTests.swift` of nieuw `DependencyDetectorTests.swift`.

**Interfaces:**
- Produces: `Dependency.isDirect: Bool?` (nil = onbekend, init-default nil); `DependencyDetector.directNames(path: String, content: String) -> (ecosystem: String, names: Set<String>)?` voor `package.json` (dependencies+devDependencies → npm), `composer.json` (require+require-dev zonder `php`, `ext-*` → Packagist), `pyproject.toml` (`[project] dependencies`, `[tool.poetry.dependencies]` zonder `python` → PyPI, namen lowercased/genormaliseerd), `Cargo.toml` (`[dependencies]`, `[dev-dependencies]` → crates.io); `VersionChecker.Scan.directDependencies: [Dependency]`.

- [ ] Tests: go.mod met `// indirect` → `isDirect == false`, zonder → `true`; npm lock v3 met `packages[""].dependencies = {react}` → react direct, `node_modules/a/node_modules/b` niet direct; NuGet/requirements → `true`; `directNames` voor de vier manifesten.
- [ ] Implementeer. In `scan`: na de lus `directDependencies` = deps met `isDirect == true`, plus deps met `isDirect == nil` waarvan de naam in de repo-brede `directNames` voor dat ecosysteem staat; SwiftURL-pins altijd. Ontdubbel op (ecosystem, name) met oudste versie, bronnen samengevoegd.
- [ ] `make test` groen. Commit `feat: tell direct dependencies apart`.

### Task 3: Nieuwste patch per runtime-cyclus

**Files:** Modify `Sources/PullwatchCore/EndOfLife.swift`, `Sources/PullwatchCore/VersionCheck.swift`; Test `Tests/PullwatchCoreTests/VersionCheckTests.swift`.

**Interfaces:**
- Produces: `EndOfLife.cycle(of version: String, releases: [EndOfLifeRelease]) -> EndOfLifeRelease?` (langste naam-prefix match, zoals in `evaluate`); `ComponentVersion.cycle: String?`, `ComponentVersion.cycleLatest: String?` (decodeIfPresent, init-default nil).

- [ ] Test: releases `1.27 latest 1.27.4`, `1.26 latest 1.26.10`; `cycle(of: "1.26.9")?.latest == "1.26.10"`; component uit checker heeft `cycle == "1.26"`, `cycleLatest == "1.26.10"`.
- [ ] Implementeer; `evaluate` gebruikt `cycle(of:)` intern.
- [ ] `make test`; commit `feat: keep the latest patch of each runtime cycle`.

### Task 4: PackageRegistry

**Files:** Create `Sources/PullwatchCore/PackageRegistry.swift`; Test `Tests/PullwatchCoreTests/PackageRegistryTests.swift`.

**Interfaces:**
- Produces: `PackageRegistry.url(ecosystem: String, name: String) -> URL?` (nil voor SwiftURL/onbekend); `PackageRegistry.decodeLatest(ecosystem: String, data: Data) throws -> String?`; `PackageRegistry.latest(ecosystem:name:http:now:) async -> String?` (nil bij elke fout, 404 of geen stabiele versie).

| Ecosysteem | URL | Uit JSON |
|---|---|---|
| Go | `proxy.golang.org/<escaped>/@latest` | `Version`, "v" eraf; pseudo-versie (bevat `-0.` of 3 delen na `-`) → nil |
| npm | `registry.npmjs.org/<name met / als %2f>/latest` | `version` |
| Packagist | `repo.packagist.org/p2/<vendor>/<name>.json` | `packages[name]`: hoogste `version` zonder `dev`/`-`/`RC`/`beta`/`alpha`, "v" eraf |
| NuGet | `api.nuget.org/v3-flatcontainer/<lowercase>/index.json` | laatste in `versions` zonder `-` |
| PyPI | `pypi.org/pypi/<name>/json` | `info.version` |
| crates.io | `crates.io/api/v1/crates/<name>` (header `User-Agent: Pullwatch`) | `crate.max_stable_version` |

- [ ] Tests: URL-gevallen uit Review Focus 1 en 5 (`github.com/BurntSushi/toml` → `github.com/!burnt!sushi/toml`); decode per ecosysteem met kleine fixture; Go-pseudo-versie → nil; `latest` met 404 via `MockHTTPClient` → nil.
- [ ] Implementeer. `make test`; commit `feat: look up the latest package version in its registry`.

### Task 5: Package-overzicht in het rapport

**Files:** Create `Sources/PullwatchCore/PackageOverview.swift`; Modify `VersionCheck.swift` (`RepoVersions.packages`, `VersionReport.latestPackages`); Test `Tests/PullwatchCoreTests/PackageOverviewTests.swift`.

**Interfaces:**
- Produces:
  - `struct PackageUse: Codable, Hashable, Sendable { ecosystem, name, version: String; sources: [String] }`; `RepoVersions.packages: [PackageUse]` (default `[]`).
  - `struct PackageLatest: Codable, Hashable, Sendable { version: String?; seenAt: Date }`; `VersionReport.latestPackages: [String: PackageLatest]` (sleutel `PackageUse.key` = `"ecosystem:name"`, default `[:]`).
  - `struct PackageUser: Hashable, Sendable, Identifiable { repoId, repo, version: String; sources: [String] }`.
  - `struct PackageSummary: Hashable, Sendable, Identifiable { id, label, kind: String; latest: String?; since: Date?; behind: [PackageUser]; current: [PackageUser] }` met `state: State { updateAvailable, current, unchecked }`.
  - `VersionReport.packageSummaries() -> [PackageSummary]`: runtimes uit `components` met `cycleLatest != nil`, product niet in `StackDetector.lockedPackages`-sleutels, id `"runtime:<product>:<cycle>"`, label `"<label> <cycle>"`, kind `"runtime"`, latest = `cycleLatest`, since = nil; libraries uit `packages` met `latestPackages[key]`. Sortering: updateAvailable (meeste achter eerst), current, unchecked; daarbinnen label.
  - `PackageVersions.isBehind(_ used: String, latest: String) -> Bool`: vergelijk alleen zoveel delen als `used` heeft (`1.27` vs `1.27.4` → false).
  - `VersionReport.carryingSeenDates(from previous: VersionReport?) -> VersionReport`: `seenAt` van vorige behouden als `version` gelijk.
  - `VersionReport.newPackageVersions(since previous: VersionReport?) -> [PackageSummary]`: libraries met vorige non-nil versie ≠ nieuwe, plus runtime-cycli waarvan `cycleLatest` veranderde t.o.v. vorige; alleen met `behind` niet leeg. Vorige nil → `[]`.
- [ ] Tests: isBehind (Review Focus 3), summaries met twee repo's (één achter, één actueel), framework `react` alleen als npm-rij, unchecked bij `version == nil`, carry-over, newPackageVersions (Review Focus 4, gewijzigd, ongewijzigd, niemand achter), oud JSON zonder nieuwe velden decodeert.
- [ ] Implementeer; `make test`; commit `feat: package overview across repos`.

### Task 6: Checker vult packages en nieuwste versies

**Files:** Modify `Sources/PullwatchCore/VersionCheck.swift`; Test `VersionCheckTests.swift`.

**Interfaces:**
- Consumes: Task 2 `Scan.directDependencies`, Task 4 `PackageRegistry.latest`, Task 5 types.
- Produces: `run(accounts:)` vult `RepoVersions.packages` en `VersionReport.latestPackages` (seenAt = `now()`); `run(account:repo:) -> (repo: RepoVersions, latest: [String: PackageLatest])`; `VersionReport.replacing(_ repo: RepoVersions, latest: [String: PackageLatest]) -> VersionReport` (merge, bestaande seenAt behouden bij gelijke versie).

- [ ] Test met `MockProvider` + `MockHTTPClient`: repo met go.mod (direct + indirect) → `packages` alleen direct, `latestPackages["Go:github.com/x/y"]?.version == "1.2.0"`; registry-404 → `version == nil`.
- [ ] Implementeer: unieke keys, `withTaskGroup` met max 8 tegelijk.
- [ ] `make test`; commit `feat: fetch latest versions during the version check`.

### Task 7: Melding en instelling

**Files:** Modify `Sources/PullwatchCore/AppConfig.swift`, `App/AppModel.swift`, `App/Notifier.swift`, `App/SettingsView.swift`, strings; Test `Tests/PullwatchCoreTests/ModelsTests.swift` (config decode).

**Interfaces:**
- Produces: `AppConfig.notifyPackageUpdates: Bool` (default true); `AppModel.setNotifyPackageUpdates(_:)`; `Notifier.deliverPackageUpdates(_ items: [PackageSummary])`; userInfo `"section": "versions"` → `onOpenSection`.

- [ ] Test: oude config zonder veld → true.
- [ ] `checkVersions`: `report = report.carryingSeenDates(from: previous)`; bij automatic en setting aan: `newPackageVersions(since: previous)` → `deliverPackageUpdates`. `refreshVersions` gebruikt nieuwe `run`/`replacing`.
- [ ] Melding: titel `"\(n) nieuwe versies"` (1: `"\(label) \(latest) beschikbaar"`), body eerste 3 `"\(label) \(latest)"` + `"+ \(n-3) meer"`. Klik: open venster `main`, `mainSection = .versions`.
- [ ] Toggle in Instellingen → Algemeen "Melding bij nieuwe versies".
- [ ] `make test && make build`; commit `feat: notify about new package versions`.

### Task 8: Onderdeel Versies

**Files:** Create `App/PackagesView.swift`; Modify `App/MainView.swift`, `App/AppModel.swift`.

**Interfaces:**
- Consumes: `packageSummaries()`.
- Produces: `AppModel.unseenPackageUpdates: Int` (updateAvailable met `since > lastSeenPackages`, `UserDefaults` "lastSeenPackages" bijgewerkt bij openen van het onderdeel).

- [ ] UI volgens mockup: zoekveld (label/repo), knop "Nu checken" (`checkVersions`), groepen Nieuwe versie beschikbaar / Actueel (ingeklapt) / Niet te checken (ingeklapt), uitklapbare rijen met repo, versie, bronnen, "✓ N al op x". Klik op repo → Repo-controle gefilterd. Stip voor `since > lastSeen`. Lege staat zoals `VersionsView`.
- [ ] Badge Versies in zijbalk = `unseenPackageUpdates`.
- [ ] `make build`; handmatig met echte accounts nalopen. Commit `feat: Versions section per package`.

### Task 9: Afronden

- [ ] README "Versions"-sectie: hoofdvenster, onderdeel Versies, registers (packagenamen gaan naar die registers, ook private repo's), melding.
- [ ] Vertalingen EN/DE/FR compleet (geen `new`/lege states in xcstrings).
- [ ] Versie in `project.yml` naar volgende minor; `make test && make build`.
- [ ] Commit `docs: main window and package versions`.
