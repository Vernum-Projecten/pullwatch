import Foundation
import Testing
@testable import PullwatchCore
import PullwatchTestSupport

/// Metadata per versie uit elk register, met ingekorte echte antwoorden.
@Suite struct RegistryMetadataTests {
    let now = Date(timeIntervalSince1970: 1_792_000_000)

    private func decode(_ ecosystem: String, _ name: String, _ json: String) throws -> (latest: String?, versions: [String: VersionMetadata]) {
        try RegistryMetadata.decode(ecosystem: ecosystem, name: name, data: Data(json.utf8))
    }

    @Test func documentURLs() {
        #expect(RegistryMetadata.documentURL(ecosystem: "npm", name: "@angular/core")?.absoluteString == "https://registry.npmjs.org/@angular%2Fcore")
        #expect(RegistryMetadata.documentURL(ecosystem: "NuGet", name: "Serilog")?.absoluteString
            == "https://api.nuget.org/v3/registration5-gz-semver2/serilog/index.json")
        #expect(RegistryMetadata.documentURL(ecosystem: "RubyGems", name: "rack")?.absoluteString == "https://rubygems.org/api/v1/versions/rack.json")
        #expect(RegistryMetadata.documentURL(ecosystem: "Packagist", name: "monolog/monolog")?.absoluteString
            == "https://repo.packagist.org/p2/monolog/monolog.json")
        #expect(RegistryMetadata.documentURL(ecosystem: "SwiftURL", name: "github.com/apple/swift-nio") == nil)
        #expect(RegistryMetadata.detailURL(ecosystem: "crates.io", name: "anyhow", version: "1.0.80")?.absoluteString
            == "https://crates.io/api/v1/crates/anyhow/1.0.80/dependencies")
        #expect(RegistryMetadata.detailURL(ecosystem: "RubyGems", name: "rack", version: "3.0.0")?.absoluteString
            == "https://rubygems.org/api/v2/rubygems/rack/versions/3.0.0.json")
        #expect(RegistryMetadata.detailURL(ecosystem: "PyPI", name: "requests", version: "2.31.0")?.absoluteString
            == "https://pypi.org/pypi/requests/2.31.0/json")
        #expect(RegistryMetadata.detailURL(ecosystem: "Go", name: "github.com/BurntSushi/toml", version: "1.4.0")?.absoluteString
            == "https://proxy.golang.org/github.com/!burnt!sushi/toml/@v/v1.4.0.mod")
        #expect(RegistryMetadata.detailURL(ecosystem: "npm", name: "react", version: "19.0.0") == nil)
    }

    @Test func npmPackument() throws {
        let express = try decode("npm", "express", RegistryFixtures.npmExpress)
        #expect(express.latest == "5.3.0")
        #expect(express.versions["5.3.0"]?.runtimes == ["nodejs": ">= 18"])
        #expect(express.versions["5.3.0"]?.dependencies?["qs"] == "^6.16.0")
        #expect(express.versions["0.14.1"]?.isWithdrawn == true)
        let reactDOM = try decode("npm", "react-dom", RegistryFixtures.npmReactDOM)
        #expect(reactDOM.versions["19.0.0"]?.peerDependencies == ["react": "^19.0.0"])
    }

    @Test func npmToleratesOldShapes() throws {
        // Heel oude packages hebben `engines` als lijst en `deprecated` als boolean.
        let json = #"{"dist-tags":{"latest":"1.0.0"},"versions":{"1.0.0":{"engines":["node >= 0.4"],"deprecated":true}}}"#
        let decoded = try decode("npm", "old", json)
        #expect(decoded.versions["1.0.0"]?.runtimes == [:])
        #expect(decoded.versions["1.0.0"]?.isWithdrawn == true)
    }

    @Test func packagistExpandsMinifiedVersions() throws {
        let monolog = try decode("Packagist", "monolog/monolog", RegistryFixtures.packagistMonolog)
        #expect(monolog.latest == "3.12.1")
        // 3.12.0 en 3.11.0 erven `require` van 3.12.1; 2.10.0 van 2.11.1.
        #expect(monolog.versions["3.11.0"]?.runtimes == ["php": ">=8.1"])
        #expect(monolog.versions["3.11.0"]?.dependencies == ["psr/log": "^2.0 || ^3.0"])
        #expect(monolog.versions["2.10.0"]?.runtimes == ["php": ">=7.2"])
        #expect(monolog.versions["2.0.0-beta1"]?.runtimes == ["php": "^7.1"])
    }

    @Test func cratesVersionsAndDependencies() throws {
        let anyhow = try decode("crates.io", "anyhow", RegistryFixtures.cratesAnyhow)
        #expect(anyhow.latest == "1.0.104")
        #expect(anyhow.versions["1.0.104"]?.runtimes == ["rust": ">= 1.68"])
        #expect(anyhow.versions["1.0.104"]?.dependencies == nil)
        #expect(anyhow.versions["1.0.103"]?.isWithdrawn == true)
        #expect(anyhow.versions["1.0.30"]?.runtimes == [:])
        let detail = try RegistryMetadata.decodeDetail(ecosystem: "crates.io", data: Data(RegistryFixtures.cratesAnyhowDependencies.utf8))
        #expect(detail.dependencies == ["backtrace": "^0.3.51"])
    }

    @Test func nugetDependencyGroups() throws {
        let newtonsoft = try decode("NuGet", "Newtonsoft.Json", RegistryFixtures.nugetNewtonsoft)
        #expect(newtonsoft.latest == "13.0.4")
        // Ook voor .NET Standard gebouwd: past op elke .NET.
        #expect(newtonsoft.versions["13.0.4"]?.runtimes == [:])
        let modern = try decode("NuGet", "Acme.Modern", RegistryFixtures.nugetModernOnly)
        #expect(modern.versions["2.0.0"]?.runtimes == ["dotnet": ">= 9.0"])
        #expect(modern.versions["1.0.0"]?.runtimes == ["dotnet": ">= 6.0"])
        #expect(RegistryMetadata.dotnetMinimum([".NETFramework4.6.2", "net6.0", "net8.0"]) == "6.0")
        #expect(RegistryMetadata.dotnetMinimum([".NETCoreApp3.1", "net5.0"]) == "3.1")
        #expect(RegistryMetadata.dotnetMinimum(["net8.0", ".NETStandard2.0"]) == nil)
        #expect(RegistryMetadata.dotnetMinimum([".NETFramework4.8"]) == nil)
        #expect(RegistryMetadata.dotnetMinimum([""]) == nil)
    }

    @Test func nugetFetchesOnlyPagesFromTheOldestInstall() async throws {
        let http = MockHTTPClient()
        http.on("serilog/index.json", body: RegistryFixtures.nugetSerilog)
        http.on("serilog/page/4.3.0-dev-02360/4.4.1-dev-02453.json", body: RegistryFixtures.nugetSerilogPage)
        let metadata = try #require(await RegistryMetadata.fetch(ecosystem: "NuGet", name: "Serilog", floor: "4.3.0", keep: ["4.3.0"], http: http, now: now))
        #expect(metadata.latest == "4.3.0")
        #expect(metadata.versions["4.3.0"]?.dependencies?["System.Diagnostics.DiagnosticSource"] == "[8.0.1, )")
        // De oudere pagina (tot 4.3.0-dev-02358) bevat niets vanaf 4.3.0 en blijft liggen.
        #expect(http.requests.map { $0.url!.lastPathComponent } == ["index.json", "4.4.1-dev-02453.json"])
    }

    @Test func rubyGemsVersions() throws {
        let rack = try decode("RubyGems", "rack", RegistryFixtures.rubyGemsRack)
        #expect(rack.latest == "3.2.8")
        // Het gewone platform telt, `>= 0` zegt niets.
        #expect(rack.versions["3.2.8"]?.runtimes == ["ruby": ">= 2.4.0"])
        #expect(rack.versions["2.2.9"]?.runtimes == ["ruby": ">= 2.3.0"])
        let detail = try RegistryMetadata.decodeDetail(ecosystem: "RubyGems", data: Data(RegistryFixtures.rubyGemsRack300.utf8))
        #expect(detail.dependencies == [:])
        #expect(detail.runtimes == ["ruby": ">= 2.4.0"])
    }

    @Test func pypiReleasesAndRequiresDist() throws {
        let requests = try decode("PyPI", "requests", RegistryFixtures.pypiRequests)
        #expect(requests.latest == "2.34.2")
        #expect(requests.versions["2.32.3"]?.runtimes == ["python": ">=3.8"])
        #expect(requests.versions["2.32.0"]?.isWithdrawn == true)
        #expect(requests.versions["2.31.0"]?.dependencies == nil)
        let detail = try RegistryMetadata.decodeDetail(ecosystem: "PyPI", data: Data(RegistryFixtures.pypiRequests2310.utf8))
        #expect(detail.dependencies == [
            "charset-normalizer": "<4,>=2", "idna": "<4,>=2.5", "urllib3": "<3,>=1.21.1", "certifi": ">=2017.4.17",
        ])
        #expect(RegistryMetadata.requiresDist(["urllib3<3,>=1.26", "requests[socks]>=2.0", "tomli; python_version < \"3.11\""])
            == ["urllib3": "<3,>=1.26", "requests": ">=2.0", "tomli": ""])
    }

    @Test func goLatestAndModFile() async throws {
        let http = MockHTTPClient()
        http.on("spf13/cobra/@latest", body: RegistryFixtures.goCobraLatest)
        http.on("spf13/cobra/@v/v1.10.2.mod", body: RegistryFixtures.goCobraMod)
        let metadata = try #require(await RegistryMetadata.fetch(
            ecosystem: "Go", name: "github.com/spf13/cobra", floor: "1.8.0", http: http, now: now
        ))
        #expect(metadata.latest == "1.10.2")
        #expect(metadata.isComplete == false)
        #expect(metadata.versions["1.10.2"]?.runtimes == ["go": ">= 1.15"])
        #expect(metadata.versions["1.10.2"]?.dependencies?["github.com/spf13/pflag"] == "1.0.5")
        #expect(http.requests.count == 2)

        // Wat een vorige check per versie al had, gaat niet opnieuw de deur uit.
        let again = MockHTTPClient()
        again.on("spf13/cobra/@latest", body: RegistryFixtures.goCobraLatest)
        let cached = await RegistryMetadata.fetch(ecosystem: "Go", name: "github.com/spf13/cobra", floor: "1.8.0", cached: metadata, http: again, now: now)
        #expect(cached == metadata)
        #expect(again.requests.count == 1)
    }

    @Test func npmAsksForTheAbbreviatedDocument() async throws {
        let http = MockHTTPClient()
        http.on("registry.npmjs.org/express", body: RegistryFixtures.npmExpress)
        let metadata = try #require(await RegistryMetadata.fetch(ecosystem: "npm", name: "express", floor: "4.21.2", keep: ["4.21.2"], http: http, now: now))
        #expect(http.requests.first?.value(forHTTPHeaderField: "Accept")?.hasPrefix("application/vnd.npm.install-v1+json") == true)
        // Alleen vanaf de oudste install: 0.14.1 valt weg.
        #expect(Set(metadata.versions.keys) == ["4.21.2", "5.0.0", "5.3.0"])
    }

    @Test func failuresGiveNoMetadata() async {
        let http = MockHTTPClient()
        http.on("registry.npmjs.org/private", status: 404, body: "")
        #expect(await RegistryMetadata.fetch(ecosystem: "npm", name: "private", floor: nil, http: http, now: now) == nil)
        #expect(await RegistryMetadata.fetch(ecosystem: "SwiftURL", name: "github.com/a/b", floor: nil, http: http, now: now) == nil)
    }

    @Test func runtimeRequirements() {
        #expect(RuntimeRequirement.isSatisfied(runtime: "nodejs", requirement: ">= 18", installed: "16") == false)
        #expect(RuntimeRequirement.isSatisfied(runtime: "nodejs", requirement: "^18.18.0 || >=20", installed: "18") == true)
        #expect(RuntimeRequirement.isSatisfied(runtime: "php", requirement: ">=8.1", installed: "7.4") == false)
        #expect(RuntimeRequirement.isSatisfied(runtime: "php", requirement: "^7.2 || ^8.0", installed: "8.3") == true)
        #expect(RuntimeRequirement.isSatisfied(runtime: "python", requirement: ">=3.10", installed: "3.9") == false)
        #expect(RuntimeRequirement.isSatisfied(runtime: "python", requirement: ">=3.8", installed: "3.12") == true)
        #expect(RuntimeRequirement.isSatisfied(runtime: "rust", requirement: ">= 1.68", installed: "1.60.0") == false)
        #expect(RuntimeRequirement.isSatisfied(runtime: "go", requirement: ">= 1.22", installed: "1.22") == true)
        #expect(RuntimeRequirement.isSatisfied(runtime: "dotnet", requirement: ">= 9.0", installed: "8.0") == false)
        #expect(RuntimeRequirement.isSatisfied(runtime: "ruby", requirement: ">= 3.1", installed: "3.0") == false)
        #expect(RuntimeRequirement.isSatisfied(runtime: "nodejs", requirement: "nonsense", installed: "20") == nil)
    }
}
