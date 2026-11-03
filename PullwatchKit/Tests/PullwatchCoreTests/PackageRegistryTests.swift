import Foundation
import Testing
@testable import PullwatchCore
import PullwatchTestSupport

@Suite struct PackageRegistryTests {
    private func latest(_ ecosystem: String, _ json: String) throws -> String? {
        try PackageRegistry.decodeLatest(ecosystem: ecosystem, name: "x", data: Data(json.utf8))
    }

    @Test func urls() {
        #expect(PackageRegistry.url(ecosystem: "Go", name: "github.com/BurntSushi/toml")?.absoluteString
            == "https://proxy.golang.org/github.com/!burnt!sushi/toml/@latest")
        #expect(PackageRegistry.url(ecosystem: "npm", name: "@angular/core")?.absoluteString
            == "https://registry.npmjs.org/@angular%2Fcore/latest")
        #expect(PackageRegistry.url(ecosystem: "npm", name: "react")?.absoluteString == "https://registry.npmjs.org/react/latest")
        #expect(PackageRegistry.url(ecosystem: "Packagist", name: "laravel/framework")?.absoluteString
            == "https://repo.packagist.org/p2/laravel/framework.json")
        #expect(PackageRegistry.url(ecosystem: "NuGet", name: "Serilog")?.absoluteString
            == "https://api.nuget.org/v3-flatcontainer/serilog/index.json")
        #expect(PackageRegistry.url(ecosystem: "PyPI", name: "Django")?.absoluteString == "https://pypi.org/pypi/Django/json")
        #expect(PackageRegistry.url(ecosystem: "crates.io", name: "serde")?.absoluteString == "https://crates.io/api/v1/crates/serde")
        #expect(PackageRegistry.url(ecosystem: "SwiftURL", name: "github.com/apple/swift-nio") == nil)
    }

    @Test func goDropsVAndIgnoresPseudoVersions() throws {
        #expect(try latest("Go", #"{"Version":"v1.4.0","Time":"2025-01-01T00:00:00Z"}"#) == "1.4.0")
        #expect(try latest("Go", #"{"Version":"v0.0.0-20240101120000-abcdef123456"}"#) == nil)
        #expect(try latest("Go", #"{"Version":"v1.5.0-0.20240101120000-abcdef123456"}"#) == nil)
    }

    @Test func npmReadsVersion() throws {
        #expect(try latest("npm", #"{"name":"react","version":"19.2.1"}"#) == "19.2.1")
    }

    @Test func packagistPicksHighestStable() throws {
        let json = #"{"packages":{"x":[{"version":"v12.5.0-RC1"},{"version":"v12.4.1"},{"version":"dev-main"},{"version":"v11.9.0"}]}}"#
        #expect(try latest("Packagist", json) == "12.4.1")
    }

    @Test func nugetPicksHighestStable() throws {
        #expect(try latest("NuGet", #"{"versions":["3.1.0","4.0.0","4.1.0-dev-0001","4.0.10"]}"#) == "4.0.10")
    }

    @Test func pypiReadsInfoVersion() throws {
        #expect(try latest("PyPI", #"{"info":{"version":"5.1.3"}}"#) == "5.1.3")
    }

    @Test func cratesReadsMaxStable() throws {
        #expect(try latest("crates.io", #"{"crate":{"max_stable_version":"1.0.215","max_version":"1.1.0-beta"}}"#) == "1.0.215")
    }

    @Test func fetchReturnsNilOnNotFound() async {
        let http = MockHTTPClient()
        http.on("proxy.golang.org", status: 404, body: "not found")
        #expect(await PackageRegistry.latest(ecosystem: "Go", name: "github.com/private/x", http: http) == nil)
    }

    @Test func fetchSendsUserAgentToCrates() async {
        let http = MockHTTPClient()
        http.on("crates.io", body: #"{"crate":{"max_stable_version":"1.40.0"}}"#)
        #expect(await PackageRegistry.latest(ecosystem: "crates.io", name: "tokio", http: http) == "1.40.0")
        #expect(http.requests.first?.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("Pullwatch") == true)
    }
}
