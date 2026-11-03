import AppKit
import PullwatchCore
import SwiftUI

/// Het paneel onder het menubalk-icoon: losse onderdelen die elk alleen krijgen wat ze tonen,
/// zodat een poll niet het hele paneel opnieuw laat tekenen. Acties gaan via het model.
struct MenuView: View {
    @Environment(AppModel.self) private var app
    @Environment(AccountsModel.self) private var accounts
    @Environment(HistoryModel.self) private var historyModel
    @Environment(PollingModel.self) private var polling
    @Environment(NotificationsModel.self) private var notifications
    @Environment(UpdatesModel.self) private var updates
    @Environment(AppRouter.self) private var router
    /// Welke rij of knop de aanwijzer raakt; één waarde voor het hele paneel.
    @State private var hover = MenuHover()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MenuHeader(
                isPolling: polling.pollProgress != nil,
                refresh: { Task { await polling.refreshNow() } },
                openSettings: { MenuPanel.close(); router.show(.settings) },
                openAbout: { MenuPanel.close(); router.show(.about) }
            )
            .padding(.horizontal, MenuMetrics.rowInset)

            if let update = updates.availableUpdate {
                UpdateBanner(update: update) { MenuPanel.close(); updates.installUpdate() }
                    .padding(.horizontal, MenuMetrics.rowInset)
            }
            if !notifications.notificationsAllowed && !accounts.needsOnboarding {
                NotificationsOffNotice()
                    .padding(.horizontal, MenuMetrics.rowInset)
            }
            if let mute = notifications.recentMute {
                MuteBanner(mute: mute, undo: app.undoMute, dismiss: notifications.dismissMute)
                    .padding(.horizontal, MenuMetrics.rowInset)
            }

            Divider()

            if accounts.config.pollableAccounts.isEmpty {
                SetupPrompt { MenuPanel.close(); router.show(.onboarding) }
            } else {
                RecentSection(title: "Pull requests", empty: "Nog geen nieuwe PR's", items: historyModel.menuPullRequests, open: historyModel.open, setRead: { historyModel.setRead([$0.id], $1) }) { item in
                    MenuPanel.close()
                    app.showRepo(accountId: item.entry.accountId, repo: item.entry.repo)
                    router.show(.main)
                }
                if historyModel.hasTags {
                    RecentSection(title: "Tags en releases", empty: nil, items: historyModel.menuTags, open: historyModel.open, setRead: { historyModel.setRead([$0.id], $1) }) { item in
                        MenuPanel.close()
                        app.showRepo(accountId: item.entry.accountId, repo: item.entry.repo)
                        router.show(.main)
                    }
                }
            }

            if !accounts.config.accounts.isEmpty {
                Divider()
                AccountStatusList(accounts: accounts.config.accounts, statuses: polling.statuses)
                    .padding(.horizontal, MenuMetrics.rowInset)
            }

            Divider()

            MenuFooter(
                unreadCount: historyModel.unreadCount,
                markAllRead: historyModel.markAllRead,
                openMain: { MenuPanel.close(); router.show(.main) }
            )
            .padding(.horizontal, MenuMetrics.rowInset)
        }
        // Zijkant: 12 pt tot de tekst, waarvan 8 binnen elke regel (daar tekent een rij haar
        // markering), zodat markeringen bijna tot de rand lopen zoals in de menubalkpanelen.
        .padding(.horizontal, 12 - MenuMetrics.rowInset)
        .padding(.vertical, 12)
        .frame(width: 480)
        .resetsMenuHover(hover)
    }
}

/// Sluit het menupaneel, zodat een venster dat daarna opent er niet onder valt.
enum MenuPanel {
    static func close() {
        NSApp.keyWindow?.orderOut(nil)
    }
}

/// Kop van het paneel: naam en versie, en rechtsboven drie symboolknoppen (over, verversen,
/// instellingen) met een ronde markering bij aanwijzen. Geen glas: het paneel zelf is al van
/// Liquid Glass, en Apple raadt glas op glas en glas in de inhoudslaag af.
private struct MenuHeader: View {
    /// Er loopt een poll: een kleine spinner naast Verversen, en Verversen staat uit.
    let isPolling: Bool
    let refresh: () -> Void
    let openSettings: () -> Void
    let openAbout: () -> Void

    var body: some View {
        HStack {
            Text(verbatim: "Pullwatch").font(.headline)
            Text(verbatim: AppModel.currentVersion)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
            // Vaste plek links van de knoppen, alleen zichtbaar tijdens een poll: er verschuift
            // niets, en de drie knoppen staan als groep bij elkaar.
            ProgressView()
                .controlSize(.small)
                .opacity(isPolling ? 1 : 0)
                .accessibilityHidden(!isPolling)
                .accessibilityLabel(Text("Bezig met verversen"))
                .help("Bezig met verversen")
            HStack(spacing: 4) {
                Button("Over Pullwatch", systemImage: "info.circle", action: openAbout)
                    .buttonStyle(MenuIconButtonStyle(id: "about"))
                    .help("Over Pullwatch")
                Button("Nu verversen", systemImage: "arrow.clockwise", action: refresh)
                    .buttonStyle(MenuIconButtonStyle(id: "refresh"))
                    .keyboardShortcut("r")
                    .disabled(isPolling)
                    .help("Nu verversen")
                Button("Instellingen", systemImage: "gearshape", action: openSettings)
                    .buttonStyle(MenuIconButtonStyle(id: "settings"))
                    .keyboardShortcut(",")
                    .help("Instellingen")
                    .accessibilityIdentifier("menu.settings")
            }
        }
    }
}

private struct UpdateBanner: View {
    let update: AvailableUpdate
    /// Sparkle's venster openen (alleen als de update in de app installeert).
    let install: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack {
            Label("Pullwatch \(update.version) is beschikbaar", systemImage: "arrow.down.circle.fill")
                .foregroundStyle(.tint)
            Spacer()
            Button("Release notes") { openURL(update.pageURL) }
                .buttonStyle(.link)
            if update.installsInApp {
                Button("Installeren", action: install)
            } else {
                Button("Downloaden") { openURL(update.downloadURL ?? update.pageURL) }
            }
        }
        .font(.callout)
    }
}

/// Na "Repo dempen" op een melding: welke repo nu stil is, met Ongedaan maken.
private struct MuteBanner: View {
    let mute: RepositoryMute
    let undo: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack {
            Label {
                Text("Meldingen van \(mute.repo) staan uit", comment: "Na Repo dempen op een melding; repo")
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(systemName: "bell.slash")
            }
            Spacer()
            Button("Ongedaan maken", action: undo)
            Button("Sluiten", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Sluiten")
        }
        .font(.callout)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("menu.muteBanner")
    }
}

private struct NotificationsOffNotice: View {
    var body: some View {
        Label("Meldingen staan uit in Systeeminstellingen", systemImage: "bell.slash")
            .font(.caption)
            .foregroundStyle(.orange)
    }
}

/// Nog geen account: wat Pullwatch nodig heeft, met de knop naar het welkomstvenster.
private struct SetupPrompt: View {
    let setUp: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Nog geen account ingesteld", systemImage: "person.crop.circle.badge.plus")
        } description: {
            Text("Voeg een GitHub- of Azure DevOps-account toe om pull requests en tags te volgen.")
        } actions: {
            Button("Pullwatch instellen…", action: setUp)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("menu.setUp")
        }
    }
}

/// De laatste PR's of tags: een kop en per item één rij.
private struct RecentSection: View {
    let title: LocalizedStringKey
    /// Tekst als er nog niets is; nil: dan toont het onderdeel niets.
    let empty: LocalizedStringKey?
    let items: [HistoryItem]
    let open: (HistoryItem) -> Void
    let setRead: (HistoryItem, Bool) -> Void
    let openRepo: (HistoryItem) -> Void

    var body: some View {
        // Zelfde inspringing als de rijen (die hun markering binnen hun eigen ruimte tekenen).
        Text(title)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, MenuMetrics.rowInset)
        if items.isEmpty, let empty {
            Text(empty).foregroundStyle(.secondary)
                .padding(.horizontal, MenuMetrics.rowInset)
        } else {
            ForEach(items) { item in
                RecentRow(item: item) { open(item) }
                    .contextMenu {
                        Button(item.isRead ? "Markeer als ongelezen" : "Markeer als gelezen") { setRead(item, !item.isRead) }
                        Button("Open repo \(item.entry.repo)") { openRepo(item) }
                    }
            }
        }
    }
}

/// Eén PR of tag: ongelezen-stip, soort, titel, en daaronder repo, auteur en wanneer. VoiceOver
/// leest het als één zin, met "ongelezen" erbij.
private struct RecentRow: View {
    let item: HistoryItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 6) {
                Circle()
                    .fill(item.isRead ? AnyShapeStyle(.clear) : AnyShapeStyle(.tint))
                    .frame(width: 6, height: 6)
                    .padding(.top, 6)
                // Zoals GitHub: alleen het icoon en de kleur van de status (open, draft,
                // gemerged, gesloten), of het tag-symbool; de woorden staan in tooltip en VoiceOver.
                item.entry.glyph.image
                    .foregroundStyle(item.entry.glyphColor)
                    .frame(width: 14)
                    .help(Text(item.entry.glyphLabel))
                    .accessibilityLabel(Text(item.entry.glyphLabel))
                VStack(alignment: .leading, spacing: 2) {
                    if let release = item.entry.releaseTitle {
                        // De titel van de release, met de tagnaam erachter.
                        HStack(spacing: 4) {
                            Text(verbatim: release).lineLimit(1)
                            Text(verbatim: item.entry.title).foregroundStyle(.secondary).lineLimit(1)
                        }
                    } else {
                        // De titel, met de checks erachter zoals in de PR-lijst van GitHub.
                        HStack(spacing: 6) {
                            Text(item.entry.title).lineLimit(1)
                            ChecksBadge(checks: item.entry.checks)
                                .font(.caption)
                        }
                    }
                    Text("\(item.entry.repo), \(item.entry.author ?? String(localized: "onbekend")), \(item.detectedAt, format: .relative(presentation: .named))", comment: "Repo, auteur, wanneer gezien")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(MenuRowButtonStyle(id: item.id))
        .accessibilityElement(children: .combine)
        .accessibilityValue(item.isRead ? Text(verbatim: "") : Text("Ongelezen"))
    }
}

/// Per account: foto, naam en hoe het pollen ging.
private struct AccountStatusList: View {
    let accounts: [Account]
    let statuses: [UUID: AccountState]

    var body: some View {
        ForEach(accounts) { account in
            AccountStatusRow(account: account, state: statuses[account.id] ?? .idle)
        }
    }
}

private struct AccountStatusRow: View {
    let account: Account
    let state: AccountState

    var body: some View {
        HStack(spacing: 4) {
            AccountAvatar(account: account, size: 16)
            Text(account.displayName).font(.caption.bold())
            switch state {
            case _ where account.isPaused:
                Text("Uitgezet").font(.caption).foregroundStyle(.secondary)
            case .idle where !account.isComplete || !account.followsAnything:
                Text("Volgt nog niets").font(.caption).foregroundStyle(.secondary)
            case .idle:
                Text("wacht op eerste poll").font(.caption).foregroundStyle(.secondary)
            case .ok(let lastPoll):
                Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                    .accessibilityLabel(Text("Bijgewerkt"))
                Text(lastPoll, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary)
            case .failed(let error, _):
                Text(error.userMessage).font(.caption).foregroundStyle(.red).lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Onderaan: alles gelezen, het hoofdvenster en stoppen, elk met een sneltoets (de instellingen
/// zitten rechtsboven).
private struct MenuFooter: View {
    let unreadCount: Int
    let markAllRead: () -> Void
    let openMain: () -> Void

    var body: some View {
        HStack {
            Button("Alles gelezen", action: markAllRead)
                .keyboardShortcut("k")
                .disabled(unreadCount == 0)
            Spacer()
            Button("Openen…", action: openMain)
                .keyboardShortcut("o")
            Button("Stop Pullwatch") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
