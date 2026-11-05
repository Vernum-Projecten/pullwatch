import Foundation
import PullwatchCore
import Testing

@testable import Pullwatch

/// De erkenningen in de gebouwde app (`Contents/Resources/Acknowledgements/`) tegen wat er echt in
/// zit. `Package.resolved` en de lijst van niet-gelinkte packages leest de test uit de
/// broncode (via `#filePath`): xcodebuild test draait altijd vanuit een checkout, en zo vergelijkt
/// hij de bundle met de pins van precies deze commit, zonder kopie die zelf kan verouderen. Een
/// nieuwe of opgehoogde dependency zonder bijgewerkt manifest faalt hier, net als in
/// `scripts/checks/acknowledgements.sh`.
@MainActor @Suite struct AcknowledgementsTests {
    /// De root van de repository: `Pullwatch/PullwatchTests/<dit bestand>` drie mappen omhoog.
    static let repository = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    let folder: URL
    let manifest: AcknowledgementsManifest

    init() throws {
        folder = try #require(
            Bundle.main.url(forResource: AcknowledgementsModel.folderName, withExtension: nil),
            "geen map Acknowledgements in Contents/Resources van de app"
        )
        let data = try Data(contentsOf: folder.appending(path: AcknowledgementsModel.manifestName))
        manifest = try JSONDecoder().decode(AcknowledgementsManifest.self, from: data)
    }

    /// De pins van de app (`identity` naar versie), uit de broncode.
    private func resolvedPins() throws -> [String: String] {
        struct Resolved: Decodable {
            struct Pin: Decodable {
                struct State: Decodable { let version: String? }
                let identity: String
                let state: State
            }
            let pins: [Pin]
        }
        let url = Self.repository.appending(path: "Pullwatch/Pullwatch.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
        let resolved = try JSONDecoder().decode(Resolved.self, from: Data(contentsOf: url))
        return Dictionary(uniqueKeysWithValues: resolved.pins.map { ($0.identity, $0.state.version ?? "") })
    }

    /// De packages die niet in de app of de helper gelinkt worden, met hun reden.
    private func notLinked() throws -> Set<String> {
        let url = Self.repository.appending(path: "scripts/checks/acknowledgements-not-linked.txt")
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        return Set(lines.filter { !$0.hasPrefix("#") }.compactMap { line in
            line.split(separator: ":", maxSplits: 1).first.map { $0.trimmingCharacters(in: .whitespaces) }
        })
    }

    @Test func `Every resolved package is acknowledged or listed as not linked`() throws {
        let acknowledged = Set(manifest.components.compactMap(\.package))
        let notLinked = try notLinked()
        for identity in try resolvedPins().keys {
            #expect(acknowledged.contains(identity) || notLinked.contains(identity),
                    "\(identity) staat in Package.resolved maar niet in acknowledgements.json of acknowledgements-not-linked.txt")
            #expect(!(acknowledged.contains(identity) && notLinked.contains(identity)), "\(identity) staat in beide lijsten")
        }
    }

    @Test func `Every acknowledged package has the resolved version`() throws {
        let pins = try resolvedPins()
        for component in manifest.components {
            guard let package = component.package else { continue }
            let resolved = try #require(pins[package], "\(package) staat niet (meer) in Package.resolved")
            #expect(component.version == resolved, "\(component.name): manifest \(component.version), Package.resolved \(resolved)")
        }
    }

    @Test func `Every licence file is in the bundle and not empty`() throws {
        let files = ["LICENSE", "NOTICE"] + manifest.components.flatMap(\.files)
        for file in files {
            let text = try String(contentsOf: folder.appending(path: file), encoding: .utf8)
            #expect(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(file) is leeg")
        }
    }

    @Test func `LICENSE and NOTICE in the bundle equal the repository's`() throws {
        for file in ["LICENSE", "NOTICE"] {
            let bundled = try Data(contentsOf: folder.appending(path: file))
            let source = try Data(contentsOf: Self.repository.appending(path: file))
            #expect(bundled == source, "\(file) in de app wijkt af van \(file) in de repository")
        }
    }

    @Test func `NOTICE names every component`() throws {
        let notice = try String(contentsOf: folder.appending(path: "NOTICE"), encoding: .utf8)
        for component in manifest.components {
            #expect(notice.contains(component.name), "NOTICE noemt \(component.name) niet")
            #expect(notice.contains(component.version), "NOTICE noemt versie \(component.version) van \(component.name) niet")
        }
    }

    /// Elk logo van een dienst (`ProviderKind.glyph` als asset) staat in NOTICE: zijn bestand in de
    /// assetcatalogus en de zin dat Pullwatch niet bij de eigenaar hoort.
    @Test(arguments: ProviderKind.allCases)
    func `Every provider logo is credited in NOTICE`(kind: ProviderKind) throws {
        guard case .asset(let asset) = kind.glyph else { return }
        let notice = try String(contentsOf: folder.appending(path: "NOTICE"), encoding: .utf8)
        let flat = notice.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        #expect(flat.contains("Assets.xcassets/\(asset).imageset"), "NOTICE noemt \(asset) niet")
        // Tot het volgende logo: de zin moet bij dit logo staan.
        let after = try #require(flat.components(separatedBy: "Assets.xcassets/\(asset).imageset").last)
        let paragraph = after.components(separatedBy: "Assets.xcassets/").first ?? after
        #expect(paragraph.contains("Pullwatch is not affiliated with"), "NOTICE zegt bij \(asset) niet dat Pullwatch er niet bij hoort")
    }

    /// De logo's met een licentie staan erin met hun licentietekst: Codeberg (CC0), Forgejo
    /// (CC BY-SA 4.0, met de naam van de maker in NOTICE), de iconen van Simple Icons (CC0) en het
    /// Rust-logo daaruit (CC BY-SA 4.0).
    @Test(arguments: [
        ("codeberg-logo", "CC0-1.0", "CC0 1.0 Universal"),
        ("simple-icons", "CC0-1.0", "CC0 1.0 Universal"),
        ("rust-logo", "CC-BY-SA-4.0", "Attribution-ShareAlike 4.0 International"),
        ("forgejo-logo", "CC-BY-SA-4.0", "Attribution-ShareAlike 4.0 International"),
    ])
    func `The logos are acknowledged with their licence`(id: String, license: String, title: String) throws {
        let component = try #require(manifest.components.first { $0.id == id })
        #expect(component.license == license)
        #expect(component.package == nil)
        let text = try String(contentsOf: folder.appending(path: component.file), encoding: .utf8)
        #expect(text.contains(title))
        let notice = try String(contentsOf: folder.appending(path: "NOTICE"), encoding: .utf8)
        #expect(notice.contains(license))
    }

    @Test func `NOTICE credits the maker of the Forgejo logo`() throws {
        let notice = try String(contentsOf: folder.appending(path: "NOTICE"), encoding: .utf8)
        #expect(notice.contains("Caesar Schinas"))
        // Gitea zonder licentie (keuze van de eigenaar): de bron en de regel dat Pullwatch er los van staat.
        #expect(notice.contains("https://raw.githubusercontent.com/go-gitea/gitea/main/assets/logo.svg"))
        #expect(notice.contains("with, endorsed, sponsored, or approved by CommitGo, Inc."))
    }

    /// Sparkle is het enige dynamisch gelinkte onderdeel: de versie van het framework in de bundle
    /// zelf moet die van het manifest zijn.
    @Test func `The embedded Sparkle framework has the acknowledged version`() throws {
        let frameworks = try #require(Bundle.main.privateFrameworksURL)
        let sparkle = try #require(Bundle(url: frameworks.appending(path: "Sparkle.framework")))
        let entry = try #require(manifest.components.first { $0.package == "sparkle" })
        #expect(sparkle.infoDictionary?["CFBundleShortVersionString"] as? String == entry.version)
    }

    @Test func `The model reads every component and its texts`() {
        let model = AcknowledgementsModel()
        model.load()
        #expect(!model.isMissing)
        #expect(model.components == manifest.components)
        #expect(model.selected?.id == AcknowledgementsModel.pullwatchID)
        for component in model.app + model.components {
            let texts = model.texts[component.id] ?? []
            #expect(texts.map(\.file) == component.files)
            #expect(texts.allSatisfy { !$0.text.isEmpty }, "lege tekst bij \(component.name)")
        }
    }
}
