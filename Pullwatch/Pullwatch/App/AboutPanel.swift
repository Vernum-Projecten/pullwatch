import AppKit

/// Het standaard About-paneel van macOS met versie en icoon, plus een korte uitleg en link.
@MainActor enum AboutPanel {
    static let repository = URL(string: "https://github.com/alessandro823/pullwatch")!

    static func show() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let text: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ]
        let credits = NSMutableAttributedString(
            string: String(localized: "Nieuwe pull requests en tags uit GitHub en Azure DevOps in je menubalk, met geschiedenis en een versie- en CVE-check van je repo's.") + "\n\n",
            attributes: text
        )
        var link = text
        link[.link] = repository
        credits.append(NSAttributedString(string: "github.com/alessandro823/pullwatch", attributes: link))
        credits.append(NSAttributedString(string: "\n" + String(localized: "Licentie: Apache 2.0"), attributes: text))
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}
