import SwiftUI

/// De laatste tag in de tabel van Repo's, met een slot ervoor als het token de repo niet kan
/// lezen: die tag kan dan oud zijn. Leest zelf geen model uit de environment (zie `ChecksBadge`).
struct LatestTagCell: View {
    let tag: String?
    let isUnreachable: Bool

    var body: some View {
        HStack(spacing: 4) {
            if isUnreachable {
                Image(systemName: "lock.slash")
                    .foregroundStyle(.yellow)
                    .help(Text("Niet te lezen met het token van dit account: nieuwe tags komen niet binnen."))
                    .accessibilityLabel(Text("Niet te lezen met het token van dit account: nieuwe tags komen niet binnen."))
            }
            if let tag {
                Text(verbatim: tag).monospacedDigit().lineLimit(1)
            }
        }
    }
}
