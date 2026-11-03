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
                // Het frame van het venster, zodat knoppenbalk en titel er ook op staan.
                let view = window?.contentView?.superview ?? window?.contentView,
                let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
            else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? rep.representation(using: .png, properties: [:])?.write(to: directory.appending(path: "\(name).png"))
            // Een zwevende zijbalk (Liquid Glass) tekent niet mee; de lijst erin apart wel.
            if let sidebar = outlineViews(in: view).first(where: { $0.convert($0.bounds, to: nil).minX < 100 }),
               let sidebarRep = sidebar.bitmapImageRepForCachingDisplay(in: sidebar.visibleRect) {
                sidebar.cacheDisplay(in: sidebar.visibleRect, to: sidebarRep)
                try? sidebarRep.representation(using: .png, properties: [:])?.write(to: directory.appending(path: "\(name)-sidebar.png"))
            }
        }
    }

    /// Met `-PullwatchSnapshotExpand YES`: inklapbare groepen (packages, rijen in Versies) staan
    /// open, zodat de foto's laten zien wat erin zit.
    static var expandsAll: Bool { UserDefaults.standard.bool(forKey: "PullwatchSnapshotExpand") }

    /// Schuift de grootste scrollview van het venster `pages` vensterhoogtes naar beneden, voor
    /// foto's van wat onder de vouw staat.
    static func scroll(windowId: String, pages: Double) {
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix(windowId) == true }),
              let content = window.contentView,
              let scrollView = scrollViews(in: content).max(by: { $0.documentView?.frame.height ?? 0 < $1.documentView?.frame.height ?? 0 })
        else { return }
        let height = scrollView.contentView.bounds.height
        let maxY = max(0, (scrollView.documentView?.frame.height ?? 0) - height)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: min(maxY, height * 0.9 * pages)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private static func scrollViews(in view: NSView) -> [NSScrollView] {
        ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap(scrollViews)
    }

    private static func outlineViews(in view: NSView) -> [NSOutlineView] {
        (view as? NSOutlineView).map { [$0] } ?? view.subviews.flatMap(outlineViews)
    }
}
#endif
