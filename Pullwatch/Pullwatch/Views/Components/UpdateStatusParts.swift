import PullwatchCore
import SwiftUI

/// De update-status van één install of repo, met wat nodig is om hem in woorden te zeggen: de
/// geïnstalleerde versie en het gevraagde bereik. `update` is nil voor een runtime.
struct UpdateStatus: Hashable {
    let update: PackageUpdate?
    let category: UpdateCategory
    let installed: String
    let requested: String?

    init(update: PackageUpdate?, category: UpdateCategory? = nil, installed: String, requested: String?) {
        self.update = update
        self.category = category ?? update?.status.category ?? .upToDate
        self.installed = installed
        self.requested = requested
    }

    init(_ install: InstallUpdate) {
        self.init(update: install.update, installed: install.install.version, requested: install.install.requested)
    }

    /// De status van wat `user` zelf kan bijwerken: de install die de status bepaalt (direct eerst).
    init(user: PackageUser, latest: String?) {
        let category = user.category(latest: latest)
        let combined = user.update
        let leading = user.updates.first { $0.install.scope == .direct && $0.update.status == combined?.status }
            ?? user.updates.first { $0.update.status == combined?.status }
        self.init(update: combined, category: category, installed: leading?.install.version ?? user.version,
                  requested: leading?.install.requested)
    }

    /// Korte tekst voor een tabelcel of pil.
    var label: LocalizedStringResource {
        guard let update else {
            return category == .upToDate ? "Actueel" : "Update beschikbaar"
        }
        if category == .upToDate { return "Actueel" }
        switch update.status {
        case .upToDate: return "Actueel"
        case .withinRange:
            switch update.step {
            case .patch: return "Patch-update binnen bereik"
            case .minor: return "Minor-update binnen bereik"
            case .major: return "Major-update binnen bereik"
            case nil: return "Update binnen bereik"
            }
        case .needsManifestChange:
            return update.step == .major ? "Major-update" : "Update buiten bereik"
        case .blockedByPackage, .blockedByPeer, .blockedByRuntime: return "Geblokkeerd"
        case .unknown: return "Nieuwere versie"
        }
    }

    var symbol: String { category.symbol }
    var color: Color { category.color }

    /// Waarom, en wat eerst moet, in één zin; nil als er niets te zeggen is.
    var reason: LocalizedStringResource? {
        guard let update, category != .upToDate, let latest = update.latest else { return nil }
        switch update.status {
        case .withinRange:
            guard let requested else { return nil }
            return "\(latest) valt binnen \(requested): alleen de lockfile verandert."
        case .needsManifestChange:
            guard let requested else { return nil }
            return "\(latest) valt buiten \(requested): pas eerst het manifest aan."
        case .blockedByPackage(let parent, let range, let minimum?):
            return "Vastgehouden op \(installed) door \(parent), dat \(range) vraagt. Werk eerst \(parent) bij naar \(minimum)."
        case .blockedByPackage(let parent, let range, nil):
            return "Vastgehouden op \(installed) door \(parent), dat \(range) vraagt. Nog geen versie van \(parent) laat \(latest) toe."
        case .blockedByPeer(let name, let needs, let installedPeer):
            return "\(latest) vraagt \(name) \(needs); deze workspace heeft \(installedPeer)."
        case .blockedByRuntime(let runtime, let needs, let installedRuntime):
            let name = Runtime.name(runtime)
            return "\(latest) vraagt \(name) \(needs); de repo gebruikt \(name) \(installedRuntime)."
        case .upToDate, .unknown:
            return nil
        }
    }

    /// De nieuwste versie die nu kan, als die anders is dan de nieuwste en nieuwer dan wat er staat.
    var usableNow: String? {
        guard let usable = update?.usable, usable != update?.latest, usable != installed else { return nil }
        return usable
    }

    /// Status, reden en de versie die nu kan, voor VoiceOver, een tooltip of het klembord.
    var spoken: String {
        [String(localized: label), reason.map { String(localized: $0) }, usableNow.map { String(localized: "Nieuwste die nu kan: \($0)") }]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}

extension UpdateCategory {
    var symbol: String {
        switch self {
        case .canUpdateNow: "arrow.up.circle.fill"
        case .needsManifestChange: "arrow.up.forward.circle"
        case .blocked: "lock.circle"
        case .unknown: "questionmark.circle"
        case .upToDate: "checkmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .canUpdateNow: .green
        case .needsManifestChange: .orange
        case .blocked: .red
        case .unknown, .upToDate: .secondary
        }
    }

    /// Kop van de groep in Afhankelijkheden.
    var title: LocalizedStringResource {
        switch self {
        case .canUpdateNow: "Kan nu bijwerken"
        case .needsManifestChange: "Manifest aanpassen nodig"
        case .blocked: "Geblokkeerd"
        case .unknown: "Nieuwere versie, status onbekend"
        case .upToDate: "Actueel"
        }
    }
}

/// De naam van een runtime zoals een ontwikkelaar hem kent (endoflife.date-product → naam).
enum Runtime {
    static func name(_ product: String) -> String {
        switch product {
        case "nodejs": "Node"
        case "php": "PHP"
        case "python": "Python"
        case "rust": "Rust"
        case "dotnet": ".NET"
        case "ruby": "Ruby"
        case "go": "Go"
        default: product
        }
    }
}

/// Symbool en korte tekst van een status; de reden in de tooltip, en alles samen voor VoiceOver.
struct UpdateStatusLabel: View {
    let status: UpdateStatus
    var font: Font = .body

    var body: some View {
        Label {
            Text(status.label)
        } icon: {
            Image(systemName: status.symbol).foregroundStyle(status.color)
        }
        .font(font)
        .lineLimit(1)
        .help(Text(verbatim: status.spoken))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: status.spoken))
    }
}
