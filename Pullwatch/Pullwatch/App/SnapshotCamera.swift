#if DEBUG
import AppKit

/// Alleen in debug-builds: met `-PullwatchSnapshotDirectory <map>` tekent de app een venster
/// zelf naar een PNG, zodat schermen te bekijken zijn zonder schermopname-toestemming. De UI-tests
/// gebruiken het; Liquid Glass en materialen tekent het niet zoals het scherm.
@MainActor
enum SnapshotCamera {
    static var directory: URL? {
        UserDefaults.standard.string(forKey: "PullwatchSnapshotDirectory").map { URL(filePath: $0, directoryHint: .isDirectory) }
    }

    /// Bewaart het venster met deze id-prefix (of het voorste venster) als `<naam>.png`, na een
    /// korte pauze zodat de layout klaar is.
    static func shoot(_ name: String, windowId: String? = nil) {
        guard let directory else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            let window = windowId.flatMap { id in NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(id) == true } }
                ?? NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible && $0.contentView != nil }
            guard
                let view = window?.contentView,
                let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
            else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? rep.representation(using: .png, properties: [:])?.write(to: directory.appending(path: "\(name).png"))
        }
    }
}
#endif
