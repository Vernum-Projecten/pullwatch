import Foundation
import Testing
@testable import PullwatchCore

/// Installs met workspace, scope, soort en via, per lockfile.
@Suite struct PackageInstallTests {
    // MARK: npm

    static let npmMonorepo = """
    {"lockfileVersion": 3, "packages": {
      "": {"name": "mono", "workspaces": ["packages/*"], "dependencies": {"lodash": "^4.17.21"},
           "devDependencies": {"typescript": "^5"}, "optionalDependencies": {"fsevents": "^2"}},
      "packages/web": {"name": "web", "dependencies": {"express": "^4"}},
      "packages/api": {"name": "api", "dependencies": {"lodash": "4.17.15"}},
      "node_modules/web": {"resolved": "packages/web", "link": true},
      "node_modules/api": {"resolved": "packages/api", "link": true},
      "node_modules/lodash": {"version": "4.17.21"},
      "node_modules/typescript": {"version": "5.6.0", "dev": true},
      "node_modules/fsevents": {"version": "2.3.3", "optional": true},
      "node_modules/express": {"version": "4.21.0", "dependencies": {"body-parser": "1.20.3"}},
      "node_modules/body-parser": {"version": "1.20.3", "dependencies": {"qs": "6.13.0", "lodash": "4.17.15"}},
      "node_modules/body-parser/node_modules/lodash": {"version": "4.17.15"},
      "node_modules/qs": {"version": "6.13.0"},
      "node_modules/eslint-helper": {"version": "1.0.0", "devOptional": true},
      "packages/api/node_modules/lodash": {"version": "4.17.15"}
    }}
    """

    @Test func npmWorkspacesGiveEveryInstallItsWorkspaceScopeKindAndVia() {
        let deps = DependencyDetector.detect(path: "package-lock.json", content: Self.npmMonorepo)
        #expect(describe(deps) == [
            "body-parser@1.20.3 packages/web transitive runtime express",
            "eslint-helper@1.0.0 . transitive dev",
            "express@4.21.0 packages/web direct runtime",
            "fsevents@2.3.3 . direct optional",
            "lodash@4.17.15 packages/api direct runtime",
            "lodash@4.17.15 packages/web transitive runtime express>body-parser",
            "lodash@4.17.21 . direct runtime",
            "qs@6.13.0 packages/web transitive runtime express>body-parser",
            "typescript@5.6.0 . direct dev",
        ])
    }

    @Test func npmLockInASubfolderPrefixesTheWorkspace() {
        let lock = #"{"lockfileVersion":3,"packages":{"":{"dependencies":{"a":"1"}},"node_modules/a":{"version":"1.0.0","dependencies":{"b":"2"}},"node_modules/b":{"version":"2.0.0"}}}"#
        #expect(describe(DependencyDetector.detect(path: "frontend/package-lock.json", content: lock)) == [
            "a@1.0.0 frontend direct runtime",
            "b@2.0.0 frontend transitive runtime a",
        ])
    }

    @Test func npmV1UsesPackageJsonInTheSameFolderForScopeAndVia() {
        let lock = """
        {"lockfileVersion": 1, "dependencies": {
          "lodash": {"version": "4.17.21"},
          "request": {"version": "2.88.2", "requires": {"lodash": "^4.17.15"},
                      "dependencies": {"lodash": {"version": "4.17.15"}}},
          "mocha": {"version": "10.0.0", "dev": true, "requires": {"debug": "4"}},
          "debug": {"version": "4.3.4", "dev": true}
        }}
        """
        let manifest = #"{"dependencies": {"lodash": "^4.17.21", "request": "^2"}, "devDependencies": {"mocha": "^10"}}"#
        #expect(describe(installs(["package-lock.json": lock, "package.json": manifest])) == [
            "debug@4.3.4 . transitive dev mocha",
            "lodash@4.17.15 . transitive runtime request",
            "lodash@4.17.21 . direct runtime",
            "mocha@10.0.0 . direct dev",
            "request@2.88.2 . direct runtime",
        ])
    }

    @Test func packageUseKeepsEveryInstallAndTheOldestDirectVersion() throws {
        let deps = DependencyDetector.detect(path: "package-lock.json", content: Self.npmMonorepo)
        let uses = DependencyDetector.direct(deps, manifests: [:])
        let lodash = try #require(uses.first { $0.name == "lodash" })
        #expect(lodash.installs.count == 3)
        #expect(lodash.versions == ["4.17.15", "4.17.21"])
        #expect(lodash.version == "4.17.15")
        #expect(Set(lodash.installs.map(\.workspace)) == ["", "packages/api", "packages/web"])
        #expect(lodash.installs.first { $0.workspace == "packages/web" }?.via == ["express", "body-parser"])
        // Alleen transitief: geen eigen regel in het overzicht.
        #expect(!uses.contains { $0.name == "qs" || $0.name == "body-parser" || $0.name == "eslint-helper" })
    }

    // MARK: Cargo

    @Test func cargoLockWalksFromWorkspaceCrates() {
        let lock = """
        version = 4

        [[package]]
        name = "app"
        version = "0.1.0"
        dependencies = [
         "cli",
         "rand 0.9.0",
         "tokio",
        ]

        [[package]]
        name = "cli"
        version = "0.1.0"
        dependencies = [
         "serde",
        ]

        [[package]]
        name = "rand"
        version = "0.8.5"
        source = "registry+https://github.com/rust-lang/crates.io-index"

        [[package]]
        name = "rand"
        version = "0.9.0"
        source = "registry+https://github.com/rust-lang/crates.io-index"

        [[package]]
        name = "serde"
        version = "1.0.219"
        source = "registry+https://github.com/rust-lang/crates.io-index"

        [[package]]
        name = "tokio"
        version = "1.40.0"
        source = "registry+https://github.com/rust-lang/crates.io-index"
        dependencies = [
         "rand 0.8.5 (registry+https://github.com/rust-lang/crates.io-index)",
        ]
        """
        #expect(describe(DependencyDetector.detect(path: "service/Cargo.lock", content: lock)) == [
            "rand@0.8.5 service transitive runtime tokio",
            "rand@0.9.0 service direct runtime",
            "serde@1.0.219 service direct runtime",
            "tokio@1.40.0 service direct runtime",
        ])
    }

    // MARK: Composer

    @Test func composerLockSplitsRuntimeAndDevAndFollowsRequire() {
        let lock = """
        {"packages": [
          {"name": "laravel/framework", "version": "v12.4.0", "require": {"php": "^8.3", "symfony/console": "^7"}},
          {"name": "symfony/console", "version": "v7.2.1", "require": {"psr/log": "^3"}},
          {"name": "psr/log", "version": "3.0.0", "require": []}
        ], "packages-dev": [
          {"name": "phpunit/phpunit", "version": "11.5.0", "require": {"sebastian/diff": "^6"}},
          {"name": "sebastian/diff", "version": "6.0.2"}
        ]}
        """
        let manifest = #"{"require": {"php": "^8.3", "laravel/framework": "^12"}, "require-dev": {"phpunit/phpunit": "^11"}}"#
        let api = #"{"packages": [{"name": "psr/log", "version": "2.0.0"}]}"#
        let found = installs([
            "composer.lock": lock, "composer.json": manifest,
            "api/composer.lock": api, "api/composer.json": #"{"require": {"psr/log": "^2"}}"#,
        ])
        #expect(describe(found) == [
            "laravel/framework@12.4.0 . direct runtime",
            "phpunit/phpunit@11.5.0 . direct dev",
            "psr/log@2.0.0 api direct runtime",
            "psr/log@3.0.0 . transitive runtime laravel/framework>symfony/console",
            "sebastian/diff@6.0.2 . transitive dev phpunit/phpunit",
            "symfony/console@7.2.1 . transitive runtime laravel/framework",
        ])
    }

    // MARK: Python

    static let poetryLock = """
    [[package]]
    name = "flask"
    version = "3.0.3"
    groups = ["main"]

    [package.dependencies]
    Jinja2 = ">=3.1.2"
    werkzeug = ">=3.0.0"

    [[package]]
    name = "jinja2"
    version = "3.1.4"
    groups = ["main"]

    [package.dependencies]
    MarkupSafe = ">=2.0"

    [[package]]
    name = "werkzeug"
    version = "3.0.4"
    groups = ["main"]

    [package.dependencies]
    MarkupSafe = ">=2.1.1"

    [[package]]
    name = "markupsafe"
    version = "2.1.5"
    groups = ["main"]

    [[package]]
    name = "pytest"
    version = "8.3.3"
    groups = ["dev"]

    [package.dependencies]
    pluggy = ">=1.5,<2"

    [[package]]
    name = "pluggy"
    version = "1.5.0"
    groups = ["dev"]

    [metadata]
    lock-version = "2.1"
    """

    static let pyproject = """
    [tool.poetry.dependencies]
    python = "^3.12"
    Flask = "^3.0"

    [tool.poetry.group.dev.dependencies]
    pytest = "^8"
    """

    @Test func poetryLockUsesGroupsAndPyprojectForDirect() {
        #expect(describe(installs(["poetry.lock": Self.poetryLock, "pyproject.toml": Self.pyproject])) == [
            "flask@3.0.3 . direct runtime",
            "jinja2@3.1.4 . transitive runtime flask",
            "markupsafe@2.1.5 . transitive runtime flask>jinja2",
            "pluggy@1.5.0 . transitive dev pytest",
            "pytest@8.3.3 . direct dev",
            "werkzeug@3.0.4 . transitive runtime flask",
        ])
    }

    @Test func poetryLockWithoutGroupsTakesTheKindFromThePyproject() {
        let lock = Self.poetryLock.replacing(/groups = \[[^\]]*\]\n/, with: "")
        let found = installs(["poetry.lock": lock, "pyproject.toml": Self.pyproject])
        #expect(found.first { $0.name == "pluggy" }?.kind == .dev)
        #expect(found.first { $0.name == "markupsafe" }?.kind == .runtime)
    }

    @Test func uvLockWorkspaceMembersAreWorkspacesWithTheirOwnDirectPackages() {
        let lock = """
        version = 1
        requires-python = ">=3.12"

        [[package]]
        name = "mono"
        version = "0.1.0"
        source = { editable = "." }
        dependencies = [
            { name = "httpx" },
        ]

        [package.optional-dependencies]
        cli = [
            { name = "click" },
        ]

        [package.dev-dependencies]
        dev = [
            { name = "pytest" },
        ]

        [package.metadata]
        requires-dist = [{ name = "httpx", specifier = ">=0.27" }, { name = "requests" }]

        [[package]]
        name = "api"
        version = "0.1.0"
        source = { editable = "packages/api" }
        dependencies = [
            { name = "anyio", version = "3.7.1", source = { registry = "https://pypi.org/simple" } },
        ]

        [[package]]
        name = "httpx"
        version = "0.27.2"
        source = { registry = "https://pypi.org/simple" }
        dependencies = [
            { name = "anyio", version = "4.6.0", source = { registry = "https://pypi.org/simple" } },
        ]

        [[package]]
        name = "anyio"
        version = "3.7.1"
        source = { registry = "https://pypi.org/simple" }

        [[package]]
        name = "anyio"
        version = "4.6.0"
        source = { registry = "https://pypi.org/simple" }

        [[package]]
        name = "click"
        version = "8.1.7"
        source = { registry = "https://pypi.org/simple" }

        [[package]]
        name = "pytest"
        version = "8.3.3"
        source = { registry = "https://pypi.org/simple" }
        """
        #expect(describe(DependencyDetector.detect(path: "uv.lock", content: lock)) == [
            "anyio@3.7.1 packages/api direct runtime",
            "anyio@4.6.0 . transitive runtime httpx",
            "click@8.1.7 . direct optional",
            "httpx@0.27.2 . direct runtime",
            "pytest@8.3.3 . direct dev",
        ])
    }

    // MARK: Workspace voor de overige bestanden

    @Test func workspaceIsTheFolderOfTheFile() {
        let gomod = "module x\n\nrequire (\n  github.com/a/b v1.2.3\n  golang.org/x/net v0.17.0 // indirect\n)\n"
        let resolved = #"{"pins":[{"location":"https://github.com/apple/swift-nio","state":{"version":"2.70.0"}}],"version":3}"#
        let found = installs([
            "tools/go.mod": gomod,
            "App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved": resolved,
            "Kit/Package.resolved": resolved,
            "src/Api/Api.csproj": #"<PackageReference Include="Serilog" Version="4.0.0" />"#,
            "Directory.Packages.props": #"<PackageVersion Include="Polly" Version="8.4.0" />"#,
            "services/ml/requirements.txt": "numpy==2.1.0\n",
        ])
        #expect(describe(found) == [
            "Polly@8.4.0 . direct runtime",
            "Serilog@4.0.0 src/Api direct runtime",
            "github.com/a/b@1.2.3 tools direct runtime",
            "github.com/apple/swift-nio@2.70.0 . unknown runtime",
            "github.com/apple/swift-nio@2.70.0 Kit unknown runtime",
            "golang.org/x/net@0.17.0 tools transitive runtime",
            "numpy@2.1.0 services/ml direct runtime",
        ])
    }

    @Test func samePackageTwiceInOneFolderIsOneInstall() {
        let found = installs([
            "requirements.txt": "django==5.1.2\n",
            "requirements-dev.txt": "django==5.1.2\npytest==8.3.3\n",
        ])
        #expect(found.filter { $0.name == "django" }.map(\.source) == ["requirements-dev.txt"])
    }
}

/// Oude versions.json en version-history.json blijven leesbaar.
@Suite struct InstallDecodingTests {
    static let oldVersions = """
    {"checkedAt": 0, "latestPackages": {"npm:lodash": {"version": "4.17.21", "seenAt": 0}},
     "repos": [{"accountId": "00000000-0000-0000-0000-000000000001", "repo": "acme/web", "components": [],
       "vulnerabilities": [{"id": "GHSA-1", "cve": "CVE-2020-8203", "summary": "lek", "severity": "HIGH", "ecosystem": "npm",
                            "package": "lodash", "version": "4.17.15", "fixedIn": "4.17.19", "source": "api/package-lock.json"}],
       "packages": [{"ecosystem": "npm", "name": "lodash", "version": "4.17.15", "sources": ["package-lock.json", "api/package-lock.json"]}]}]}
    """

    @Test func oldVersionsJsonDecodesWithDefaults() throws {
        let report = try JSONDecoder().decode(VersionReport.self, from: Data(Self.oldVersions.utf8))
        let repo = try #require(report.repos.first)
        let vulnerability = try #require(repo.vulnerabilities.first)
        #expect(vulnerability.workspace == "api")
        #expect(vulnerability.scope == .unknown)
        #expect(vulnerability.kind == .runtime)
        #expect(vulnerability.via.isEmpty)
        let lodash = try #require(repo.packages.first)
        #expect(lodash.version == "4.17.15")
        #expect(lodash.sources == ["package-lock.json", "api/package-lock.json"])
        #expect(lodash.installs.map(\.workspace) == ["", "api"])
        #expect(lodash.installs.allSatisfy { $0.scope == .direct })
        #expect(report.packageSummaries().first?.behind.first?.version == "4.17.15")
    }

    @Test func newReportRoundTrips() throws {
        let report = try JSONDecoder().decode(VersionReport.self, from: Data(Self.oldVersions.utf8))
        let again = try JSONDecoder().decode(VersionReport.self, from: JSONEncoder().encode(report))
        #expect(again == report)
        let encoded = String(decoding: try JSONEncoder().encode(report), as: UTF8.self)
        #expect(encoded.contains(#""installs""#) && !encoded.contains(#""sources""#))
    }

    @Test func oldDependencyWithIsDirectMapsToScope() throws {
        func decode(_ json: String) throws -> Dependency { try JSONDecoder().decode(Dependency.self, from: Data(json.utf8)) }
        let direct = try decode(#"{"ecosystem":"Go","name":"x","version":"1.0.0","source":"tools/go.mod","isDirect":true}"#)
        #expect(direct.scope == .direct)
        #expect(direct.workspace == "tools")
        #expect(try decode(#"{"ecosystem":"Go","name":"x","version":"1.0.0","source":"go.mod","isDirect":false}"#).scope == .transitive)
        #expect(try decode(#"{"ecosystem":"Go","name":"x","version":"1.0.0","source":"go.mod"}"#).scope == .unknown)
        let new = Dependency(ecosystem: "npm", name: "qs", version: "6.13.0", source: "package-lock.json", workspace: "packages/web",
                             scope: .transitive, kind: .dev, via: ["express", "body-parser"])
        #expect(try JSONDecoder().decode(Dependency.self, from: JSONEncoder().encode(new)) == new)
    }

    @Test func oldVersionHistoryDecodes() throws {
        let json = #"{"snapshots":[{"checkedAt":0,"repos":[{"id":"x/acme/web","components":{"Go":"1.27.3"},"statuses":{"Go":"current"},"vulnerabilities":{"HIGH":2},"packageUpdates":1}]}]}"#
        let history = try JSONDecoder().decode(VersionHistory.self, from: Data(json.utf8))
        #expect(history.snapshots.first?.repos.first?.vulnerabilities == ["HIGH": 2])
    }
}

/// Het overzicht per package: één regel, meerdere repo's, elk met zijn installs.
@Suite struct PackageOverviewInstallTests {
    let t0 = Date(timeIntervalSince1970: 1_792_000_000)

    @Test func oneRowPerPackageWithUsersCarryingTheirInstalls() throws {
        let web = PackageUse(ecosystem: "npm", name: "lodash", installs: [
            PackageInstall(version: "4.17.21", workspace: "", scope: .direct, source: "package-lock.json"),
            PackageInstall(version: "4.17.15", workspace: "packages/web", scope: .transitive, via: ["express", "body-parser"], source: "package-lock.json"),
        ])
        let api = PackageUse(ecosystem: "npm", name: "lodash", installs: [
            PackageInstall(version: "4.17.20", workspace: "", scope: .direct, kind: .dev, source: "package-lock.json"),
        ])
        let account = UUID()
        let report = VersionReport(checkedAt: t0, repos: [
            RepoVersions(accountId: account, repo: "acme/web", components: [], packages: [web]),
            RepoVersions(accountId: account, repo: "acme/api", components: [], packages: [api]),
        ], latestPackages: ["npm:lodash": PackageLatest(version: "4.17.21", seenAt: t0)])

        let summaries = report.packageSummaries()
        #expect(summaries.map(\.id) == ["npm:lodash"])
        let lodash = try #require(summaries.first)
        // Achter loopt alleen wie zelf een oude versie vraagt; de transitieve 4.17.15 telt niet.
        #expect(lodash.behind.map(\.repo) == ["acme/api"])
        #expect(lodash.current.map(\.repo) == ["acme/web"])
        let webUser = try #require(lodash.current.first)
        #expect(webUser.version == "4.17.21")
        #expect(webUser.versions == ["4.17.15", "4.17.21"])
        #expect(webUser.installs.first { $0.scope == .transitive }?.via == ["express", "body-parser"])
        #expect(lodash.behind.first?.installs.first?.kind == .dev)
    }
}
