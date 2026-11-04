import PullwatchCore
import SwiftUI

#if DEBUG
/// Elke soort melding onder elkaar, ook met de stille uren en de samenvatting boven de grens.
struct NotificationPreviewGallery: View {
    private let samples = NotificationSamples(builder: NotificationContentBuilder())

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(NotificationKind.allCases) { kind in
                if let content = samples.content(for: kind) {
                    NotificationPreview(content: content)
                }
            }
            NotificationPreview(content: samples.summary)
        }
        .padding(16)
        .frame(width: 420)
    }
}
#endif
