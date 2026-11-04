import AppKit
import Foundation
import SwiftUI
import Testing

@testable import Pullwatch

/// De menubalk van de draaiende app (`NSApp.mainMenu`), zoals `AppCommands` hem opbouwt: de
/// volgorde van Apple's richtlijnen en de onderdelen die er altijd in moeten staan, zodat een
/// refactor ze niet ongemerkt laat vallen. Taalonafhankelijk: een menu wordt herkend aan een
/// sneltoets die alleen daarin staat, een eigen onderdeel aan zijn titel in de taal van de app.
///
/// Met `TEST_RUNNER_PULLWATCH_MENU_LISTING=<map>` schrijft `writesTheListing` elk menu met zijn
/// onderdelen naar `<map>/menus-<taal>.txt` (voor de beschrijving van een pull request).
@MainActor @Suite struct MenuBarTests {
    let mainMenu: NSMenu

    init() throws {
        mainMenu = try #require(NSApp.mainMenu)
    }

    /// De menu's van links naar rechts, elk herkend aan een sneltoets die alleen daarin staat.
    private static let order: [(name: String, key: String, modifiers: NSEvent.ModifierFlags)] = [
        ("app", "q", [.command]),
        ("File", "n", [.command]),
        ("Edit", "v", [.command]),
        ("View", "s", [.control, .command]),
        ("Go", "1", [.command]),
        ("Item", "u", [.shift, .command]),
        ("Repository", "r", [.option, .command]),
        ("Window", "m", [.command]),
        ("Help", "", []),
    ]

    private var menus: [NSMenu] { mainMenu.items.compactMap(\.submenu) }

    @Test func `The menus follow Apple's order`() throws {
        let menus = menus
        try #require(menus.count == Self.order.count, "menu's: \(menus.map(\.title))")
        for (index, expected) in Self.order.enumerated() where !expected.key.isEmpty {
            #expect(menus[index].item(key: expected.key, modifiers: expected.modifiers) != nil,
                    "\(expected.name) staat niet op plek \(index + 1): \(menus.map(\.title))")
        }
        #expect(menus.last === NSApp.helpMenu || menus.last?.item(title: String(localized: "Pullwatch-help")) != nil)
    }

    @Test func `The app menu checks for updates`() throws {
        let app = try #require(menus.first)
        #expect(app.item(title: String(localized: "Controleer op updates…")) != nil)
        #expect(app.item(title: String(localized: "Over Pullwatch")) != nil)
    }

    @Test func `The View menu has the sidebar, the toolbar and Reload`() throws {
        let view = try #require(menus[safe: 3])
        // Schermvullend voegt AppKit pas toe als er een venster is dat het kan.
        #expect(view.item(key: "s", modifiers: [.control, .command]) != nil, "Toon of verberg zijbalk")
        #expect(view.item(key: "t", modifiers: [.option, .command]) != nil, "Toon of verberg knoppenbalk")
        #expect(view.item(key: "r", modifiers: [.command])?.title == String(localized: "Laad opnieuw"))
    }

    @Test func `The Item menu copies the reference right after the link`() throws {
        let item = try #require(menus[safe: 5])
        let link = try #require(item.item(key: "l", modifiers: [.shift, .command]))
        let reference = try #require(item.item(key: "l", modifiers: [.option, .shift, .command]))
        #expect(link.title == String(localized: "Kopieer link"))
        #expect(reference.title == String(localized: "Kopieer verwijzing"))
        #expect(item.index(of: reference) == item.index(of: link) + 1)
        #expect(!reference.isAlternate, "Kopieer verwijzing staat er altijd, niet alleen met ⌥")
    }

    @Test func `The Go menu lists every section in sidebar order, Packages on Command-6`() throws {
        let go = try #require(menus[safe: 4])
        let sections = MainSection.allCases.compactMap { section in
            go.item(key: section.shortcut.character.description, modifiers: [.command])
        }
        #expect(sections.map(\.title) == MainSection.allCases.map { String(localized: $0.title) })
        #expect(go.item(key: "6", modifiers: [.command])?.title == String(localized: MainSection.packages.title))
    }

    @Test func `The Window menu brings back the main window`() throws {
        let window = try #require(menus[safe: 7])
        #expect(window.item(key: "0", modifiers: [.command])?.title == "Pullwatch")
    }

    @Test func `The Help menu leads to the documentation and the acknowledgements`() throws {
        let help = try #require(menus.last)
        let titles = help.items.map(\.title)
        for key: String.LocalizationValue in ["Pullwatch-help", "Toetscombinaties", "Nieuw in Pullwatch", "Privacy en bronnen", "Meld een probleem…", "Erkenningen"] {
            #expect(titles.contains(String(localized: key)), "\(key) ontbreekt in Help: \(titles)")
        }
    }

    @Test func `Privacy and Sources sits between What's New and Report an Issue`() throws {
        let titles = try #require(menus.last).items.map(\.title)
        let new = try #require(titles.firstIndex(of: String(localized: "Nieuw in Pullwatch")))
        let privacy = try #require(titles.firstIndex(of: String(localized: "Privacy en bronnen")))
        let issue = try #require(titles.firstIndex(of: String(localized: "Meld een probleem…")))
        #expect(new < privacy && privacy < issue, "\(titles)")
    }

    @Test func `No shortcut is used twice`() {
        var seen: [String: String] = [:]
        for item in allItems(mainMenu) where !item.keyEquivalent.isEmpty && !item.isHidden {
            let shortcut = MenuListing.shortcut(item)
            #expect(seen[shortcut] == nil, "\(shortcut): \(seen[shortcut] ?? "") en \(item.title)")
            seen[shortcut] = item.title
        }
    }

    @Test func writesTheListing() throws {
        guard let folder = ProcessInfo.processInfo.environment["PULLWATCH_MENU_LISTING"] else { return }
        let language = Bundle.main.preferredLocalizations.first ?? "unknown"
        let url = URL(filePath: folder).appending(path: "menus-\(language).txt")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try MenuListing.text(of: mainMenu).write(to: url, atomically: true, encoding: .utf8)
    }

    private func allItems(_ menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { [$0] + ($0.submenu.map(allItems) ?? []) }
    }
}

/// Een menu als tekst: elk menu met zijn onderdelen, de sneltoets erachter en submenu's ingesprongen.
enum MenuListing {
    static func text(of mainMenu: NSMenu) -> String {
        mainMenu.items.compactMap(\.submenu).map { menu in
            ([menu.title.isEmpty ? "(app)" : menu.title] + lines(menu, depth: 1)).joined(separator: "\n")
        }
        .joined(separator: "\n\n") + "\n"
    }

    private static func lines(_ menu: NSMenu, depth: Int) -> [String] {
        let indent = String(repeating: "  ", count: depth)
        return menu.items.filter { !$0.isHidden }.flatMap { item -> [String] in
            if item.isSeparatorItem { return [indent + "----"] }
            let key = item.keyEquivalent.isEmpty ? "" : "  " + shortcut(item)
            return [indent + item.title + key] + (item.submenu.map { lines($0, depth: depth + 1) } ?? [])
        }
    }

    /// ⌃⌥⇧⌘ en de toets, zoals de Mac ze in een menu toont.
    static func shortcut(_ item: NSMenuItem) -> String {
        let flags = item.keyEquivalentModifierMask
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        let key = item.keyEquivalent
        if flags.contains(.shift) || key != key.lowercased() { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        let names: [String: String] = [
            String(UnicodeScalar(NSDownArrowFunctionKey)!): "↓", String(UnicodeScalar(NSUpArrowFunctionKey)!): "↑",
            "\u{1b}": "⎋", "\u{8}": "⌫", "\u{7f}": "⌫", "\r": "↩", " ": "Space",
        ]
        return text + (names[key] ?? key.uppercased())
    }
}

private extension NSMenu {
    func item(key: String, modifiers: NSEvent.ModifierFlags) -> NSMenuItem? {
        items.first { item in
            // ⇧ staat in het masker of in de hoofdletter van de toets.
            var flags = item.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask)
            if item.keyEquivalent != item.keyEquivalent.lowercased() { flags.insert(.shift) }
            return item.keyEquivalent.lowercased() == key && flags == modifiers
        }
    }

    func item(title: String) -> NSMenuItem? {
        items.first { $0.title == title }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
