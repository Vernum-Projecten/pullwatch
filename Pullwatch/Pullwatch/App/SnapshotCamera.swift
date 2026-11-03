#if DEBUG
import AppKit

/// Alleen in debug-builds: met `-PullwatchSnapshotDirectory <map>` tekent de app een venster
/// zelf naar een PNG, zodat schermen te bekijken zijn zonder schermopname-toestemming. De UI-tests
/// gebruiken het; Liquid Glass en materialen tekent het niet zoals het scherm.
enum SnapshotCamera {
    static var directory: URL? {
        UserDefaults.standard.string(forKey: "PullwatchSnapshotDirectory").map { URL(filePath: $0, directoryHint: .isDirectory) }
    }

    /// Bewaart het venster met deze id-prefix (of het voorste venster) als `<naam>.png`, na een
    /// korte pauze zodat de layout klaar is. Met `sheet` het blad dat op dat venster openstaat.
    static func shoot(_ name: String, windowId: String? = nil, sheet: Bool = false) {
        guard let directory else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            var window = windowId.flatMap { id in NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(id) == true } }
                ?? NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible && $0.contentView != nil }
            if sheet {
                window = windowId == nil
                    ? NSApp.windows.first { $0.attachedSheet != nil }?.attachedSheet
                    : window?.attachedSheet
            }
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
            // Het inspectievenster rechts staat in Liquid Glass en tekent niet mee; wat erin staat
            // (het document van de scrollview zonder tabel) apart wel, over de hele hoogte.
            if let inspector = scrollViews(in: view).first(where: {
                $0.convert($0.bounds, to: nil).minX > view.bounds.width * 0.55 && outlineOrTableViews(in: $0).isEmpty
            }), let document = inspector.documentView, let rep = document.bitmapImageRepForCachingDisplay(in: document.bounds) {
                document.cacheDisplay(in: document.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: directory.appending(path: "\(name)-inspector.png"))
            }
        }
    }

    /// Een foto van het venster, en daarna `pages` keer een vensterhoogte verder naar beneden
    /// (`<naam>-2.png` en verder), voor een lang formulier.
    static func shootScrolling(_ name: String, windowId: String, pages: Int) {
        guard directory != nil else { return }
        shoot(name, windowId: windowId)
        Task {
            for page in 1..<max(pages, 1) {
                try? await Task.sleep(for: .seconds(1))
                scroll(windowId: windowId, pages: Double(page))
                shoot("\(name)-\(page + 1)", windowId: windowId)
            }
        }
    }

    /// Met `-PullwatchSnapshotExpand YES`: inklapbare groepen (packages, rijen in Afhankelijkheden) staan
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

    private static func outlineOrTableViews(in view: NSView) -> [NSTableView] {
        (view as? NSTableView).map { [$0] } ?? view.subviews.flatMap(outlineOrTableViews)
    }

    private static func outlineViews(in view: NSView) -> [NSOutlineView] {
        (view as? NSOutlineView).map { [$0] } ?? view.subviews.flatMap(outlineViews)
    }
}
#endif
