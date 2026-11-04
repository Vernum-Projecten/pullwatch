import Foundation
import Testing
@testable import PullwatchCore

/// De catalogus van bronnen en de keuze welke uit staan (`AppConfig.disabledSources`).
@Suite struct DataSourceTests {
    @Test func everySourceIsListedOnce() {
        #expect(DataSource.all.map(\.id) == DataSourceID.allCases)
    }

    @Test func everySourceHasEndpointsAndASite() {
        for source in DataSource.all {
            #expect(!source.endpoints.isEmpty)
            #expect(source.site.scheme == "https")
            #expect(DataSource.source(source.id).id == source.id)
        }
    }

    @Test func registryForEveryEcosystem() {
        for ecosystem in ["npm", "PyPI", "crates.io", "NuGet", "RubyGems", "Packagist", "Go"] {
            #expect(DataSourceID.registry(ecosystem: ecosystem) != nil)
        }
        #expect(DataSourceID.registry(ecosystem: "Maven") == nil)
        #expect(DataSourceID.releases(product: "swift") == .swiftOrg)
        #expect(DataSourceID.releases(product: "go") == .endOfLife)
    }

    @Test func configWithoutDisabledSourcesHasEverythingOn() throws {
        let json = #"{"accounts":[],"pollInterval":120}"#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        #expect(config.disabledSources.isEmpty)
        #expect(DataSourceID.allCases.allSatisfy(config.isEnabled))
    }

    @Test func unknownSourceIdIsIgnored() throws {
        let json = #"{"accounts":[],"pollInterval":120,"disabledSources":["osv","nvd"]}"#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        #expect(config.disabledSources == [.osv])
        #expect(!config.isEnabled(.osv))
        #expect(config.isEnabled(.npm))
    }

    @Test func disabledSourcesRoundTrip() throws {
        let config = AppConfig(disabledSources: [.npm, .gitHubSecurity])
        let decoded = try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(config))
        #expect(decoded == config)
        #expect(decoded.disabledSources == [.npm, .gitHubSecurity])
    }
}
