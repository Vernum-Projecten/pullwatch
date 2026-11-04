import Foundation
import Testing
@testable import PullwatchCore

@Suite struct DirectDependencyTests {
    private func direct(_ deps: [Dependency]) -> [String: Bool?] {
        Dictionary(uniqueKeysWithValues: deps.map { ($0.name, $0.isDirect) })
    }

    @Test func goModMarksIndirectRequires() {
        let gomod = """
        module example.com/app

        require github.com/a/one v1.0.0
        require (
            github.com/b/two v2.1.0
            github.com/c/three v0.3.0 // indirect
        )
        """
        let found = direct(DependencyDetector.detect(path: "go.mod", content: gomod))
        #expect(found["github.com/a/one"] == true)
        #expect(found["github.com/b/two"] == true)
        #expect(found["github.com/c/three"] == false)
    }

    @Test func npmLockV3UsesRootPackageForDirectNames() {
        let lock = """
        {"lockfileVersion": 3, "packages": {
          "": {"dependencies": {"react": "^19.0.0"}, "devDependencies": {"vite": "^6.0.0"}},
          "node_modules/react": {"version": "19.2.1"},
          "node_modules/vite": {"version": "6.1.0"},
          "node_modules/loose-envify": {"version": "1.4.0"},
          "node_modules/vite/node_modules/react": {"version": "18.0.0"}
        }}
        """
        let deps = DependencyDetector.detect(path: "package-lock.json", content: lock)
        let directOnes = Set(deps.filter { $0.isDirect == true }.map { "\($0.name)@\($0.version)" })
        #expect(directOnes == ["react@19.2.1", "vite@6.1.0"])
        #expect(deps.first { $0.name == "loose-envify" }?.isDirect == false)
    }

    @Test func npmLockWorkspacePackagesCountAsDirect() {
        let lock = """
        {"lockfileVersion": 3, "packages": {
          "": {"workspaces": ["packages/*"], "devDependencies": {"typescript": "^5"}},
          "packages/web": {"name": "web", "dependencies": {"react": "^19.0.0"}},
          "node_modules/web": {"resolved": "packages/web", "link": true},
          "node_modules/react": {"version": "19.2.1"},
          "node_modules/typescript": {"version": "5.6.0"},
          "node_modules/scheduler": {"version": "0.25.0"}
        }}
        """
        let deps = DependencyDetector.detect(path: "package-lock.json", content: lock)
        #expect(Set(deps.filter { $0.isDirect == true }.map(\.name)) == ["react", "typescript"])
        #expect(deps.first { $0.name == "scheduler" }?.isDirect == false)
    }

    @Test func cargoTomlReadsWorkspaceTargetAndTableDependencies() {
        let toml = """
        [workspace.dependencies]
        anyhow = "1"

        [dependencies.serde]
        version = "1"
        features = ["derive"]

        [target.'cfg(unix)'.dependencies]
        libc = "0.2"

        [profile.release]
        lto = true
        """
        #expect(DependencyDetector.directNames(path: "Cargo.toml", content: toml)?.names == ["anyhow", "serde", "libc"])
    }

    @Test func npmLockV1LeavesDirectnessUnknown() {
        let lock = #"{"lockfileVersion": 1, "dependencies": {"lodash": {"version": "4.17.21"}}}"#
        #expect(DependencyDetector.detect(path: "package-lock.json", content: lock).first?.isDirect == .some(nil))
    }

    @Test func nugetAndRequirementsAreDirect() {
        let csproj = #"<PackageReference Include="Serilog" Version="4.0.0" />"#
        #expect(DependencyDetector.detect(path: "App.csproj", content: csproj).first?.isDirect == true)
        #expect(DependencyDetector.detect(path: "requirements.txt", content: "django==5.1.2").first?.isDirect == true)
    }

    @Test func directNamesFromPackageJson() {
        let json = #"{"dependencies": {"react": "^19"}, "devDependencies": {"@types/node": "^22"}, "engines": {"node": ">=22"}}"#
        let result = DependencyDetector.directNames(path: "web/package.json", content: json)
        #expect(result?.ecosystem == "npm")
        #expect(result?.names == ["react", "@types/node"])
    }

    @Test func directNamesFromComposerJsonSkipPhpAndExtensions() {
        let json = #"{"require": {"php": "^8.3", "ext-json": "*", "laravel/framework": "^12.0"}, "require-dev": {"phpunit/phpunit": "^11"}}"#
        let result = DependencyDetector.directNames(path: "composer.json", content: json)
        #expect(result?.ecosystem == "Packagist")
        #expect(result?.names == ["laravel/framework", "phpunit/phpunit"])
    }

    @Test func directNamesFromPyproject() {
        let toml = """
        [project]
        name = "app"
        requires-python = ">=3.12"
        dependencies = [
            "Django>=5.1",
            "requests[socks] ~= 2.32",
        ]

        [tool.poetry.dependencies]
        python = "^3.12"
        Flask_Login = "^0.6"
        """
        let result = DependencyDetector.directNames(path: "pyproject.toml", content: toml)
        #expect(result?.ecosystem == "PyPI")
        #expect(result?.names == ["django", "requests", "flask-login"])
    }

    @Test func directNamesFromCargoToml() {
        let toml = """
        [package]
        name = "app"

        [dependencies]
        serde = { version = "1", features = ["derive"] }
        tokio = "1.40"

        [dev-dependencies]
        insta = "1"

        [profile.release]
        lto = true
        """
        let result = DependencyDetector.directNames(path: "Cargo.toml", content: toml)
        #expect(result?.ecosystem == "crates.io")
        #expect(result?.names == ["serde", "tokio", "insta"])
    }

    @Test func directKeepsMarkedAndManifestNamesAndMergesSources() {
        let deps = [
            Dependency(ecosystem: "Go", name: "github.com/a/one", version: "1.0.0", source: "go.mod", isDirect: true),
            Dependency(ecosystem: "Go", name: "github.com/c/three", version: "0.3.0", source: "go.mod", isDirect: false),
            Dependency(ecosystem: "Packagist", name: "laravel/framework", version: "12.4.0", source: "composer.lock"),
            Dependency(ecosystem: "Packagist", name: "symfony/console", version: "7.1.0", source: "composer.lock"),
            Dependency(ecosystem: "Packagist", name: "laravel/framework", version: "12.3.0", source: "api/composer.lock"),
            Dependency(ecosystem: "SwiftURL", name: "github.com/apple/swift-nio", version: "2.70.0", source: "Package.resolved"),
        ]
        let result = DependencyDetector.direct(deps, manifests: ["Packagist": ["laravel/framework"]])
        #expect(result.map(\.name) == ["github.com/a/one", "laravel/framework", "github.com/apple/swift-nio"])
        let laravel = result.first { $0.name == "laravel/framework" }
        #expect(laravel?.version == "12.3.0")
        #expect(laravel?.sources == ["composer.lock", "api/composer.lock"])
    }
}
