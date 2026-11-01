import PullwatchCore
import SwiftUI

/// Versies per package over alle gevolgde repo's.
struct PackagesView: View {
    let model: AppModel

    var body: some View {
        ContentUnavailableView("Nog niet gecheckt", systemImage: "shippingbox")
    }
}
