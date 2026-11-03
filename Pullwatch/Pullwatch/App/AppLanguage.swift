import AppKit
import PullwatchCore

nonisolated private let logger = Log(category: "language")

/// Taal van de app: volgt macOS, of een vaste keuze via `AppleLanguages` in de eigen defaults.
/// Een wijziging werkt pas na een herstart.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, nl, en, de, fr

    var id: String { rawValue }

    /// Talen in hun eigen taal, zodat je je taal ook herkent als de app in een andere staat.
    var name: String {
        switch self {
        case .system: String(localized: "Automatisch (taal van macOS)")
        case .nl: "Nederlands"
        case .en: "English"
        case .de: "Deutsch"
        case .fr: "Français"
        }
    }

    private static let key = "AppleLanguages"

    /// Keuze waarmee deze run gestart is (wordt vastgelegd bij het opstarten).
    static let atLaunch = current(in: .standard)

    /// Leest alleen het eigen persistent domain (`domain`, standaard de bundle id): `defaults.array`
    /// zou ook de systeemtalen teruggeven. Tests geven de naam van hun eigen suite mee.
    static func current(in defaults: UserDefaults, domain: String = Bundle.main.bundleIdentifier ?? "") -> AppLanguage {
        guard let code = (defaults.persistentDomain(forName: domain)?[key] as? [String])?.first else { return .system }
        return AppLanguage(rawValue: code) ?? .system
    }

    static func select(_ language: AppLanguage, in defaults: UserDefaults) {
        if language == .system {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set([language.rawValue], forKey: key)
        }
    }

    /// Start een nieuwe Pullwatch en sluit deze zodra die draait.
    @MainActor static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        Task {
            do {
                _ = try await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
                NSApp.terminate(nil)
            } catch {
                // Mislukt het starten, dan blijft deze instantie draaien: afsluiten laat niets over.
                logger.error("Opnieuw starten mislukt: \(error.localizedDescription)")
            }
        }
    }
}
