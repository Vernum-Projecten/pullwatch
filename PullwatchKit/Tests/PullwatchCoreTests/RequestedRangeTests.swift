import Foundation
import Testing
@testable import PullwatchCore

/// Het gevraagde bereik per install: uit het manifest voor directe installs, uit de ouder voor
/// transitieve waar de lockfile dat bewaart.
@Suite struct RequestedRangeTests {
    /// "naam@versie" → gevraagd bereik ("-" als onbekend); bij meer workspaces "naam@versie workspace".
    private func requested(_ dependencies: [Dependency], workspaces: Bool = false) -> [String: String] {
        dependencies.reduce(into: [:]) { result, d in
            let key = workspaces ? "\(d.name)@\(d.version) \(d.workspace.isEmpty ? "." : d.workspace)" : "\(d.name)@\(d.version)"
            result[key] = d.requested ?? "-"
        }
    }

    @Test func npmLockKeepsTheImporterAndParentRanges() {
        let lock = """
        {"lockfileVersion": 3, "packages": {
          "": {"dependencies": {"express": "^4.18.0", "string-width-cjs": "npm:string-width@^4.2.0"}, "devDependencies": {"typescript": "~5.6.0"}},
          "node_modules/express": {"version": "4.18.2", "dependencies": {"qs": "6.11.0", "body-parser": "1.20.1"}},
          "node_modules/body-parser": {"version": "1.20.1", "dependencies": {"qs": "~6.11.0"}},
          "node_modules/qs": {"version": "6.11.0"},
          "node_modules/string-width-cjs": {"name": "string-width", "version": "4.2.3"},
          "node_modules/typescript": {"version": "5.6.3", "dev": true}
        }}
        """
        #expect(requested(DependencyDetector.detect(path: "package-lock.json", content: lock)) == [
            "express@4.18.2": "^4.18.0",
            "body-parser@1.20.1": "1.20.1",
            // Breedte eerst: express vraagt qs het eerst.
            "qs@6.11.0": "6.11.0",
            "string-width@4.2.3": "npm:string-width@^4.2.0",
            "typescript@5.6.3": "~5.6.0",
        ])
    }

    @Test func npmV1TakesDirectRangesFromPackageJson() {
        let lock = #"{"lockfileVersion": 1, "dependencies": {"lodash": {"version": "4.17.21"}}}"#
        let manifest = #"{"dependencies": {"lodash": "^4.17.0"}}"#
        #expect(requested(installs(["package-lock.json": lock, "package.json": manifest])) == ["lodash@4.17.21": "^4.17.0"])
    }

    @Test func yarnClassicKeepsDescriptorRanges() {
        let deps = installs([
            "yarn.lock": LockfileTests.yarnClassic, "package.json": LockfileTests.yarnRoot,
            "packages/web/package.json": LockfileTests.yarnWeb, "packages/api/package.json": LockfileTests.yarnApi,
        ])
        let ranges = requested(deps, workspaces: true)
        #expect(ranges["express@4.21.0 packages/web"] == "^4.21.0")
        #expect(ranges["body-parser@1.20.3 packages/web"] == "1.20.3")
        #expect(ranges["qs@6.13.0 packages/web"] == "6.13.0")
        #expect(ranges["side-channel@1.0.6 packages/web"] == "^1.0.6")
        #expect(ranges["lodash@3.10.1 packages/web"] == "^3.10.1")
        #expect(ranges["string-width@4.2.3 packages/web"] == "npm:string-width@^4.2.0")
        #expect(ranges["lodash@4.17.21 ."] == "^4.17.21")
        #expect(ranges["lodash@4.17.15 packages/api"] == "4.17.15")
    }

    @Test func yarnBerryKeepsNpmDescriptors() {
        let lock = """
        __metadata:
          version: 8
          cacheKey: 10c0

        "app@workspace:.":
          version: 0.0.0-use.local
          resolution: "app@workspace:."
          dependencies:
            loose-envify: "npm:^1.1.0"
          languageName: unknown
          linkType: soft

        "js-tokens@npm:^3.0.0 || ^4.0.0":
          version: 4.0.0
          resolution: "js-tokens@npm:4.0.0"
          languageName: node
          linkType: hard

        "loose-envify@npm:^1.1.0":
          version: 1.4.0
          resolution: "loose-envify@npm:1.4.0"
          dependencies:
            js-tokens: "npm:^3.0.0 || ^4.0.0"
          languageName: node
          linkType: hard
        """
        let ranges = requested(installs(["yarn.lock": lock]))
        #expect(ranges == ["loose-envify@1.4.0": "npm:^1.1.0", "js-tokens@4.0.0": "npm:^3.0.0 || ^4.0.0"])
        #expect(ranges["js-tokens@4.0.0"].flatMap(NpmRange.parse)?.contains("4.0.0") == true)
    }

    @Test func pnpmKeepsImporterSpecifiersOnly() {
        let ranges = requested(DependencyDetector.detect(path: "pnpm-lock.yaml", content: LockfileTests.pnpmV9), workspaces: true)
        #expect(ranges["lodash@4.17.21 ."] == "^4.17.21")
        #expect(ranges["typescript@5.6.3 ."] == "^5.6.0")
        #expect(ranges["express@4.21.0 packages/api"] == "^4.21.0")
        #expect(ranges["react-dom@18.3.1 packages/ui"] == "^18.3.1")
        // De graaf van pnpm bewaart alleen opgeloste versies.
        #expect(ranges["body-parser@1.20.3 packages/api"] == "-")
    }

    @Test func composerTakesRequireFromJsonAndLock() {
        let lock = """
        {"packages": [
          {"name": "laravel/framework", "version": "v11.9.2", "require": {"php": "^8.2", "symfony/console": "^7.0"}},
          {"name": "symfony/console", "version": "v7.1.1", "require": {"php": ">=8.2"}}
        ], "packages-dev": [
          {"name": "phpunit/phpunit", "version": "11.2.0", "require": []}
        ]}
        """
        let manifest = #"{"require": {"php": "^8.2", "laravel/framework": "^11.0"}, "require-dev": {"phpunit/phpunit": "^11.0"}}"#
        #expect(requested(installs(["composer.lock": lock, "composer.json": manifest])) == [
            "laravel/framework@11.9.2": "^11.0",
            "symfony/console@7.1.1": "^7.0",
            "phpunit/phpunit@11.2.0": "^11.0",
        ])
    }

    @Test func poetryTakesRangesFromPyprojectAndLock() {
        let lock = """
        [[package]]
        name = "requests"
        version = "2.32.3"
        groups = ["main"]

        [package.dependencies]
        certifi = ">=2017.4.17"
        urllib3 = {version = ">=1.21.1,<3", markers = "python_version >= \\"3.8\\""}

        [[package]]
        name = "certifi"
        version = "2024.8.30"
        groups = ["main"]

        [[package]]
        name = "urllib3"
        version = "2.2.3"
        groups = ["main"]

        [[package]]
        name = "pytest"
        version = "8.3.3"
        groups = ["dev"]
        """
        let pyproject = """
        [tool.poetry.dependencies]
        python = "^3.12"
        requests = "^2.32"

        [tool.poetry.group.dev.dependencies]
        pytest = { version = "^8.0", optional = false }
        """
        #expect(requested(installs(["poetry.lock": lock, "pyproject.toml": pyproject])) == [
            "requests@2.32.3": "^2.32",
            "certifi@2024.8.30": ">=2017.4.17",
            "urllib3@2.2.3": ">=1.21.1,<3",
            "pytest@8.3.3": "^8.0",
        ])
    }

    @Test func pep621AndUvTakeSpecifiersFromPyproject() {
        let uv = """
        version = 1

        [[package]]
        name = "app"
        version = "0.1.0"
        source = { editable = "." }
        dependencies = [
            { name = "httpx" },
        ]

        [[package]]
        name = "httpx"
        version = "0.27.2"
        source = { registry = "https://pypi.org/simple" }
        """
        let pyproject = """
        [project]
        name = "app"
        dependencies = [
            "httpx[http2] >= 0.27, < 1 ; python_version >= '3.9'",
        ]
        """
        #expect(requested(installs(["uv.lock": uv, "pyproject.toml": pyproject])) == ["httpx@0.27.2": ">= 0.27, < 1"])
        #expect(DependencyDetector.pep508("requests")?.name == "requests")
        #expect(DependencyDetector.pep508("requests")?.specifier == nil)
        #expect(DependencyDetector.pep508("pkg @ https://example.com/pkg.whl")?.specifier == nil)
        #expect(DependencyDetector.pep508("name (>=1.0)")?.specifier == ">=1.0")
    }

    @Test func cargoTakesRequirementsFromCargoToml() {
        let lock = """
        [[package]]
        name = "app"
        version = "0.1.0"
        dependencies = ["serde", "tokio", "anyhow"]

        [[package]]
        name = "serde"
        version = "1.0.210"
        source = "registry+https://github.com/rust-lang/crates.io-index"

        [[package]]
        name = "tokio"
        version = "1.40.0"
        source = "registry+https://github.com/rust-lang/crates.io-index"

        [[package]]
        name = "anyhow"
        version = "1.0.89"
        source = "registry+https://github.com/rust-lang/crates.io-index"
        """
        let toml = """
        [workspace.dependencies]
        anyhow = "1.0.80"

        [dependencies]
        serde = { version = "1.0", features = ["derive"] }
        anyhow = { workspace = true }

        [dependencies.tokio]
        version = "1.38"
        features = ["full"]
        """
        #expect(requested(installs(["Cargo.lock": lock, "Cargo.toml": toml])) == [
            "serde@1.0.210": "1.0",
            "tokio@1.40.0": "1.38",
            "anyhow@1.0.89": "1.0.80",
        ])
    }

    @Test func nugetLockKeepsRequestedAndParentRanges() {
        let ranges = requested(DependencyDetector.detect(path: "src/Api/packages.lock.json", content: LockfileTests.nugetApi))
        #expect(ranges["Newtonsoft.Json@13.0.3"] == "[13.0.3, )")
        #expect(ranges["Serilog.AspNetCore@8.0.0"] == "[8.0.0, )")
        #expect(ranges["Microsoft.Extensions.Logging@8.0.0"] == "[8.0.0, )")
        #expect(ranges["System.Text.Json@6.0.0"] == "6.0.0")
    }

    @Test func projectFilesAndRequirementsKeepTheirVersion() {
        let csproj = #"<Project><ItemGroup><PackageReference Include="Serilog" Version="3.1.1" /></ItemGroup></Project>"#
        #expect(requested(DependencyDetector.detect(path: "Api.csproj", content: csproj)) == ["Serilog@3.1.1": "3.1.1"])
        #expect(requested(DependencyDetector.detect(path: "requirements.txt", content: "django==5.1.2\n")) == ["django@5.1.2": "==5.1.2"])
    }

    @Test func gemfileLockKeepsDependenciesAndSpecRanges() {
        let ranges = requested(installs(["Gemfile": LockfileTests.gemfile, "Gemfile.lock": LockfileTests.gemfileLock]))
        #expect(ranges["actionpack@7.1.4"] == "~> 7.1.4")
        #expect(ranges["pg@1.5.8"] == "~> 1.5")
        #expect(ranges["rack-test@2.1.0"] == ">= 0.6.3")
        #expect(ranges["racc@1.8.1"] == "~> 1.4")
        #expect(ranges["nokogiri@1.16.7"] == "-")
        #expect(ranges["rspec-core@3.13.1"] == "~> 3.13")
    }

    @Test func gemfileRequirementsAreReadPerGem() {
        let names = DependencyDetector.gemfileNames("""
        gem "rails", "~> 7.1", ">= 7.1.2", require: false
        gem("pg", "~> 1.5")
        gem "puma"
        """)
        #expect(names.map(\.0) == ["rails", "pg", "puma"])
        #expect(names.map(\.2) == ["~> 7.1, >= 7.1.2", "~> 1.5", nil])
    }

    @Test func goModKeepsTheRequiredVersion() {
        let mod = """
        module example.com/app

        require (
            github.com/a/b/v2 v2.1.0
            golang.org/x/text v0.14.0 // indirect
        )
        """
        #expect(requested(DependencyDetector.detect(path: "go.mod", content: mod)) == [
            "github.com/a/b/v2@2.1.0": "v2.1.0", "golang.org/x/text@0.14.0": "v0.14.0",
        ])
    }

    @Test func swiftPinsTakeTheirRequirementFromPackageSwift() {
        let resolved = """
        {"pins": [
          {"identity": "swift-nio", "kind": "remoteSourceControl", "location": "https://github.com/apple/swift-nio.git", "state": {"revision": "a", "version": "2.65.0"}},
          {"identity": "swift-log", "kind": "remoteSourceControl", "location": "https://github.com/apple/swift-log.git", "state": {"revision": "b", "version": "1.6.1"}},
          {"identity": "swift-atomics", "kind": "remoteSourceControl", "location": "https://github.com/apple/swift-atomics.git", "state": {"revision": "c", "version": "1.2.0"}}
        ], "version": 2}
        """
        let manifest = """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "App",
            dependencies: [
                .package(url: "https://github.com/apple/swift-nio.git", from: "2.60.0"),
                .package(url: "https://github.com/apple/swift-log.git", .upToNextMinor(from: "1.6.0")),
                .package(path: "../Local"),
            ]
        )
        """
        let deps = installs(["Package.resolved": resolved, "Package.swift": manifest])
        #expect(requested(deps) == [
            "github.com/apple/swift-nio@2.65.0": #"from: "2.60.0""#,
            "github.com/apple/swift-log@1.6.1": #".upToNextMinor(from: "1.6.0")"#,
            "github.com/apple/swift-atomics@1.2.0": "-",
        ])
        // Package.swift zegt niet wat direct is: de scope blijft onbekend.
        #expect(deps.allSatisfy { $0.scope == .unknown })
        #expect(DependencyDetector.swiftRequirements(#".package(url: "https://github.com/a/b", "1.0.0"..<"2.0.0")"#) == ["github.com/a/b": #""1.0.0"..<"2.0.0""#])
        #expect(DependencyDetector.swiftRequirements(#".package(url: "https://github.com/a/b", branch: "main")"#).isEmpty)
    }

    @Test func oldVersionsJsonDecodesWithoutRequested() throws {
        let install = try JSONDecoder().decode(PackageInstall.self, from: Data(#"{"version": "1.0.0", "workspace": "", "scope": "direct", "source": "package-lock.json"}"#.utf8))
        #expect(install.requested == nil)
        let dependency = try JSONDecoder().decode(Dependency.self, from: Data(#"{"ecosystem": "npm", "name": "a", "version": "1.0.0", "source": "package-lock.json"}"#.utf8))
        #expect(dependency.requested == nil)
        let roundTrip = try JSONDecoder().decode(PackageInstall.self, from: JSONEncoder().encode(
            PackageInstall(version: "1.0.0", workspace: "", scope: .direct, source: "package-lock.json", requested: "^1.0.0")))
        #expect(roundTrip.requested == "^1.0.0")
    }
}
