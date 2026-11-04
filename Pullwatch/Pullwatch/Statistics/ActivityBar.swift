import PullwatchCore
import SwiftUI

extension SyncStatus {
    /// Korte beschrijving van wat er loopt, als één zin; nil als er niets loopt.
    var activityDescription: String? {
        guard case .syncing(let done, let total, let what) = self else { return nil }
        switch what {
        case .accounts:
            return total > 0
                ? String(localized: "Accounts ophalen… \(done) van \(total)", comment: "Voortgang: klaar, totaal aantal accounts")
                : String(localized: "Accounts ophalen…")
        case .firstSync(let account?):
            return String(localized: "PR's en tags ophalen van \(account)…", comment: "Accountnaam, bv. @octocat op GitHub")
        case .firstSync(nil):
            return String(localized: "PR's en tags ophalen…")
        case .refetch:
            return String(localized: "Geschiedenis opnieuw ophalen… \(done) van \(total)", comment: "Voortgang: klaar, totaal aantal accounts")
        case .versions:
            return total > 0
                ? String(localized: "Repo's checken… \(done) van \(total)", comment: "Voortgang: gecheckte repo's, totaal aantal repo's")
                : String(localized: "Repo's zoeken…")
        case .repoCheck(let repo):
            return String(localized: "\(repo) checken…", comment: "Naam van de repo")
        }
    }

    /// Voortgang van 0 tot 1; nil als het totaal nog niet bekend is (onbepaald).
    var fraction: Double? {
        guard case .syncing(let done, let total, let what) = self, total > 0 else { return nil }
        // Eén account in een eerste sync: de aantallen gaan over de poll, niet over de backfill.
        if case .firstSync = what, total == 1 { return nil }
        return min(Double(done) / Double(total), 1)
    }
}

/// De balk onderin het hoofdvenster voor lang werk (eerste sync, opnieuw ophalen, versiecheck),
/// op dezelfde plek in elk onderdeel: een lineaire voortgang, één zin en Stoppen als dat veilig
/// kan. Een gewone poll krijgt geen balk, alleen de spinner in het menu.
struct ActivityBar: View {
    let status: SyncStatus
    let cancel: () -> Void

    var body: some View {
        if let work = status.work, work.showsActivityBar, let description = status.activityDescription {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Group {
                            if let fraction = status.fraction {
                                ProgressView(value: fraction)
                            } else {
                                ProgressView()
                            }
                        }
                        .progressViewStyle(.linear)
                        .frame(width: 160)
                        Text(verbatim: description)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: description))
                    .accessibilityValue(status.fraction.map { Text($0, format: .percent.precision(.fractionLength(0))) } ?? Text(verbatim: ""))
                    .accessibilityAddTraits(.updatesFrequently)
                    Spacer(minLength: 0)
                    if work.isCancellable {
                        Button("Stoppen", action: cancel)
                            .controlSize(.small)
                            .help("Stopt het ophalen; wat al binnen is blijft")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(.bar)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("main.activityBar")
        }
    }
}

/// Zet de balk onderin een venster, met een korte overgang (alleen vervagen met Verminder
/// beweging) en een VoiceOver-aankondiging bij begin en einde.
struct ActivityBarModifier: ViewModifier {
    let status: SyncStatus
    let cancel: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isShown: Bool { status.work?.showsActivityBar ?? false }

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isShown {
                    ActivityBar(status: status, cancel: cancel)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isShown)
            .onChange(of: isShown) { _, shown in
                let text = shown
                    ? (status.activityDescription ?? String(localized: "Ophalen…"))
                    : String(localized: "Klaar met ophalen")
                AccessibilityNotification.Announcement(text).post()
            }
    }
}

extension View {
    func activityBar(_ status: SyncStatus, cancel: @escaping () -> Void) -> some View {
        modifier(ActivityBarModifier(status: status, cancel: cancel))
    }
}
