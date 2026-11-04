import Foundation

/// Eén tag van een container-image (of een OCI-Helm-chart), gelezen zoals Renovate, Dependabot en
/// Artifact Hub dat doen: een versie (`1.2.3`, `v1.2.3`, `1.2`, `21.0.0-rc9`), een zwevende tag
/// (`latest`, `main`, een branch) of iets dat over de versie niets zegt en weg blijft: een commit
/// (7 tot 40 hex), `sha-…`, `sha256-…` (de handtekeningen en attestaties van cosign en de
/// referrers-tags van OCI 1.1), alles op `.sig`, `.att` of `.sbom`, en `artifacthub.io`.
public struct ContainerTag: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// Een versie; de volgorde is die van `Version`, een pre-release onder zijn release.
        case version
        /// Een tag die meeschuift met een branch of build (`latest`, `main`, `nightly`, `pr-12`).
        case floating
        /// Zegt niets over de versie: digest, handtekening, commit, metadata.
        case ignored
    }

    public let name: String
    public let kind: Kind
    /// De versie bij `.version`, anders nil.
    public let version: Version?

    public init(_ name: String) {
        self.name = name
        let lowered = name.lowercased()
        if Self.isIgnored(lowered) {
            kind = .ignored
            version = nil
        } else if !Self.floatingNames.contains(lowered), lowered.wholeMatch(of: /v?\d+(\.\d+)*([-+_.]?[0-9a-z][0-9a-z.+_-]*)?/) != nil,
                  let parsed = Version(name) {
            kind = .version
            version = parsed
        } else {
            kind = .floating
            version = nil
        }
    }

    /// De tag die meeschuift met de nieuwste build; hij krijgt een eigen label.
    public static let latest = "latest"

    /// Zwevende tags met een bekende naam; elke andere tag die geen versie is, telt ook als zwevend.
    static let floatingNames: Set<String> = ["latest", "main", "master", "edge", "nightly", "dev"]

    private static func isIgnored(_ tag: String) -> Bool {
        if tag == "artifacthub.io" || tag.hasPrefix("sha256-") || tag.hasPrefix("sha-") { return true }
        if [".sig", ".att", ".sbom"].contains(where: tag.hasSuffix) { return true }
        // Een commit: 7 tot 40 hex. Alleen cijfers (een datum als 20261104) is een commit alleen
        // als hij de volle 40 tekens heeft.
        guard (7...40).contains(tag.count), tag.allSatisfy(\.isHexDigit) else { return false }
        return tag.count == 40 || tag.contains { $0.isLetter }
    }
}

extension ContainerTag {
    /// Of `self` de mooiere naam is voor dezelfde image dan `other`: de hoogste versie, en bij een
    /// gelijke versie de meest precieze ("0.4.0" boven "0.4").
    package func isBetterVersion(than other: ContainerTag) -> Bool {
        guard let mine = version, let theirs = other.version else { return version != nil }
        if mine != theirs { return mine > theirs }
        return mine.release.count > theirs.release.count
    }
}
