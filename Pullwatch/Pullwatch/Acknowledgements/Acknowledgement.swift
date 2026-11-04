import Foundation

/// Een onderdeel in de erkenningen: Pullwatch zelf of open-sourcesoftware die in de app zit, met
/// de licentietekst(en) in `Contents/Resources/Acknowledgements/`. De velden zijn die van
/// `acknowledgements.json`; `scripts/checks/acknowledgements.sh` en `AcknowledgementsTests` houden
/// dat bestand gelijk aan `Package.resolved`.
nonisolated struct Acknowledgement: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let version: String
    /// SPDX-expressie van de licentie, zoals `MIT` of `Apache-2.0 WITH Swift-exception`.
    let license: String
    let homepage: URL
    /// Bestandsnaam van de licentietekst in de map.
    let file: String
    /// Bestandsnaam van een NOTICE-bestand dat bij de licentie hoort (Apache-2.0), als dat er is.
    let notice: String?
    /// De `identity` in `Package.resolved` van een Swift-package; nil voor iets anders (iconen).
    let package: String?

    /// De bestanden van dit onderdeel, in de volgorde waarin het venster ze toont.
    var files: [String] { [file] + (notice.map { [$0] } ?? []) }
}

/// De inhoud van `acknowledgements.json`.
nonisolated struct AcknowledgementsManifest: Codable, Sendable {
    let components: [Acknowledgement]
}

/// Eén licentie- of NOTICE-tekst zoals hij in de bundle staat.
nonisolated struct LicenseText: Hashable, Identifiable, Sendable {
    /// De bestandsnaam, ook de kop boven de tekst.
    let file: String
    let text: String

    var id: String { file }
}
