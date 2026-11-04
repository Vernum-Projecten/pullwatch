import Foundation
import Observation
import PullwatchCore

nonisolated private let logger = Log(category: "acknowledgements")

/// De erkenningen: Pullwatch zelf (LICENSE en NOTICE) en de open-sourcesoftware in de app, met hun
/// licentieteksten, gelezen uit `Contents/Resources/Acknowledgements/` (`acknowledgements.json`
/// en één bestand per tekst). Het venster Erkenningen toont ze; de teksten blijven Engels.
@Observable
final class AcknowledgementsModel {
    /// De map in de bundle; Xcode kopieert `Acknowledgements/Resources/Acknowledgements` als geheel.
    nonisolated static let folderName = "Acknowledgements"
    nonisolated static let manifestName = "acknowledgements.json"
    nonisolated static let pullwatchID = "pullwatch"

    /// Pullwatch zelf: LICENSE en NOTICE.
    private(set) var app: [Acknowledgement] = []
    /// De open-sourcesoftware, in de volgorde van het manifest.
    private(set) var components: [Acknowledgement] = []
    /// De teksten per onderdeel (`Acknowledgement.id`).
    private(set) var texts: [String: [LicenseText]] = [:]
    /// Het gekozen onderdeel in de zijbalk.
    var selection: Acknowledgement.ID? = AcknowledgementsModel.pullwatchID
    /// Het manifest ontbreekt of is onleesbaar; dan is de app verkeerd gebouwd.
    private(set) var isMissing = false

    @ObservationIgnored private let folder: URL?

    init(bundle: Bundle = .main) {
        folder = bundle.url(forResource: Self.folderName, withExtension: nil)
        #if DEBUG
        // Voor de camera: `-PullwatchAcknowledgement <id>` kiest een ander onderdeel.
        if let id = UserDefaults.standard.string(forKey: "PullwatchAcknowledgement") { selection = id }
        #endif
    }

    /// Het gekozen onderdeel.
    var selected: Acknowledgement? {
        (app + components).first { $0.id == selection }
    }

    // MARK: - Laden

    /// Leest het manifest en de teksten; een tweede keer doet niets. Het zijn een paar kleine
    /// bestanden in de bundle, dus gewoon op de main actor.
    func load() {
        guard app.isEmpty, !isMissing else { return }
        guard let folder,
              let data = try? Data(contentsOf: folder.appending(path: Self.manifestName)),
              let manifest = try? JSONDecoder().decode(AcknowledgementsManifest.self, from: data)
        else {
            logger.error("no readable \(Self.manifestName) in the app bundle")
            isMissing = true
            return
        }
        let pullwatch = Acknowledgement(
            id: Self.pullwatchID, name: "Pullwatch", version: AppModel.currentVersion, license: "Apache-2.0",
            homepage: AboutView.repository, file: "LICENSE", notice: "NOTICE", package: nil
        )
        app = [pullwatch]
        components = manifest.components
        texts = Dictionary(uniqueKeysWithValues: (app + components).map { component in
            (component.id, component.files.map { LicenseText(file: $0, text: Self.read($0, in: folder)) })
        })
    }

    private static func read(_ file: String, in folder: URL) -> String {
        do {
            return try String(contentsOf: folder.appending(path: file), encoding: .utf8)
        } catch {
            logger.error("cannot read \(file) from the acknowledgements: \(error.localizedDescription)")
            return ""
        }
    }
}
