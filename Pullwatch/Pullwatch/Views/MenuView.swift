import AppKit
import PullwatchCore
import SwiftUI

/// Het paneel onder het menubalk-icoon: losse onderdelen die elk alleen krijgen wat ze tonen,
/// zodat een poll niet het hele paneel opnieuw laat tekenen. Acties gaan via het model.
struct MenuView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MenuHeader(
                isPolling: model.pollProgress != nil,
                refresh: { Task { await model.refreshNow() } },
                openSettings: { MenuPanel.close(); model.show(.settings) },
                openAbout: { MenuPanel.close(); model.show(.about) }
            )

            if let update = model.availableUpdate {
                UpdateBanner(update: update)
            }
            if !model.notificationsAllowed && !model.needsOnboarding {
                NotificationsOffNotice()
            }

            Divider()

            if model.config.pollableAccounts.isEmpty {
                SetupPrompt { MenuPanel.close(); model.show(.onboarding) }
            } else {
                RecentSection(title: "Pull requests", empty: "Nog geen nieuwe PR's", items: model.menuPullRequests, open: model.open, setRead: { model.setRead([$0.id], $1) }) { item in
                    MenuPanel.close()
                    model.showRepo(accountId: item.entry.accountId, repo: item.entry.repo)
                    model.show(.main)
                }
                if model.hasTags {
                    RecentSection(title: "Tags en releases", empty: nil, items: model.menuTags, open: model.open, setRead: { model.setRead([$0.id], $1) }) { item in
                        MenuPanel.close()
                        model.showRepo(accountId: item.entry.accountId, repo: item.entry.repo)
                        model.show(.main)
                    }
                }
            }

            if !model.config.accounts.isEmpty {
                Divider()
                AccountStatusList(accounts: model.config.accounts, statuses: model.statuses)
            }

            Divider()

            MenuFooter(
                unreadCount: model.unreadCount,
                markAllRead: model.markAllRead,
                openMain: { MenuPanel.close(); model.show(.main) }
            )
        }
        .padding(12)
        .frame(width: 480)
    }
}

/// Sluit het menupaneel, zodat een venster dat daarna opent er niet onder valt.
@MainActor
enum MenuPanel {
    static func close() {
        NSApp.keyWindow?.orderOut(nil)
    }
}

/// Kop van het paneel: naam en versie, en rechtsboven drie symboolknoppen (over, verversen,
/// instellingen). Gewone randloze knoppen: het paneel zelf is al van Liquid Glass, en Apple
/// raadt glas op glas en glas in de inhoudslaag af.
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
            HStack(spacing: 12) {
                Button("Over Pullwatch", systemImage: "info.circle", action: openAbout)
                    .help("Over Pullwatch")
                // Vaste plek naast Verversen, alleen zichtbaar tijdens een poll: er verschuift niets.
                ProgressView()
                    .controlSize(.small)
                    .opacity(isPolling ? 1 : 0)
                    .accessibilityHidden(!isPolling)
                    .accessibilityLabel(Text("Bezig met verversen"))
                    .help("Bezig met verversen")
                Button("Nu verversen", systemImage: "arrow.clockwise", action: refresh)
                    .keyboardShortcut("r")
                    .disabled(isPolling)
                    .help("Nu verversen")
                Button("Instellingen", systemImage: "gearshape", action: openSettings)
                    .keyboardShortcut(",")
                    .help("Instellingen")
                    .accessibilityIdentifier("menu.settings")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .imageScale(.large)
            .foregroundStyle(.secondary)
        }
    }
}

private struct UpdateBanner: View {
    let update: AvailableUpdate
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack {
            Label("Pullwatch \(update.version) is beschikbaar", systemImage: "arrow.down.circle.fill")
                .foregroundStyle(.tint)
            Spacer()
            Button("Release notes") { openURL(update.pageURL) }
                .buttonStyle(.link)
            Button("Downloaden") { openURL(update.downloadURL ?? update.pageURL) }
        }
        .font(.callout)
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
        Text(title)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
        if items.isEmpty, let empty {
            Text(empty).foregroundStyle(.secondary)
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
                Image(systemName: item.entry.kind.symbol)
                    .foregroundStyle(item.entry.kind.color)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 2) {
                    if let release = item.entry.releaseTitle {
                        // De titel van de release, met de tagnaam erachter.
                        HStack(spacing: 4) {
                            Text(verbatim: release).lineLimit(1)
                            Text(verbatim: item.entry.title).foregroundStyle(.secondary).lineLimit(1)
                        }
                    } else {
                        Text(item.entry.title).lineLimit(1)
                    }
                    Text("\(item.entry.repo), \(item.entry.author ?? String(localized: "onbekend")), \(item.detectedAt, format: .relative(presentation: .named))", comment: "Repo, auteur, wanneer gezien")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
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
