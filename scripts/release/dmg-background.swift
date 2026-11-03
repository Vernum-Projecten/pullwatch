// swift scripts/release/dmg-background.swift <out-dir>
//
// Tekent de achtergrond van het venster van de disk image: een lichte wash
// van indigo naar teal (de kleuren van het icoon), een titel, één regel
// uitleg en een gestippelde pijl van waar Finder de app toont naar waar het
// Applications toont. Schrijft background.png (660 bij 400) en
// background@2x.png; package.sh voegt ze samen tot één Retina-TIFF. De
// posities hier moeten gelijk zijn aan de icoonposities in package.sh.

import AppKit

let size = CGSize(width: 660, height: 400)
/// Middelpunten van de iconen in Finder-coördinaten (vanaf linksboven), zoals package.sh ze zet.
let app = CGPoint(x: 170, y: 200)
let applications = CGPoint(x: 490, y: 200)

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: dmg-background.swift <out-dir>\n".utf8))
    exit(2)
}
let out = URL(filePath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha)
}

// De kleuren van het icoon (scripts/make-icon.swift).
let indigo = color(0x5B3FF0)
let deepIndigo = color(0x2A1F8F)
let teal = color(0x0E8FA8)

/// De tekst gecentreerd op `x`, met de bovenkant op `y`, beide vanaf linksboven.
func text(_ string: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, x: CGFloat, y: CGFloat) {
    let attributed = NSAttributedString(
        string: string,
        attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .kern: size > 20 ? -0.3 : 0])
    let width = attributed.size().width
    attributed.draw(at: CGPoint(x: x - width / 2, y: y))
}

func draw(scale: CGFloat, to url: URL) throws {
    guard
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)
    else { throw CocoaError(.fileWriteUnknown) }
    rep.size = size
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    // Tekenen vanaf linksboven, zoals Finder iconen plaatst.
    let cg = context.cgContext
    cg.translateBy(x: 0, y: size.height)
    cg.scaleBy(x: 1, y: -1)
    let flipped = NSGraphicsContext(cgContext: cg, flipped: true)
    NSGraphicsContext.current = flipped

    // Een lichte wash van indigo links naar teal rechts, zodat het venster
    // licht blijft en de bestandsnamen onder de iconen leesbaar zijn.
    NSGradient(colors: [color(0xF4F2FF), color(0xF7F8FC), color(0xEAF6F8)])!
        .draw(in: CGRect(origin: .zero, size: size), angle: 0)
    // Twee zachte schijven geven het vlak wat diepte zonder op te vallen.
    color(0x5B3FF0, 0.05).setFill()
    NSBezierPath(ovalIn: CGRect(x: -170, y: 230, width: 400, height: 400)).fill()
    color(0x0E8FA8, 0.06).setFill()
    NSBezierPath(ovalIn: CGRect(x: 440, y: -180, width: 420, height: 420)).fill()

    text("Install Pullwatch", size: 24, weight: .semibold, color: deepIndigo, x: size.width / 2, y: 38)
    text("Drag Pullwatch onto Applications.", size: 13, weight: .regular, color: color(0x4E4A6E), x: size.width / 2, y: 74)

    // De pijl: een zachte boog van de app naar Applications, gestippeld, met
    // een verloop van indigo naar teal over de lijn en de punt.
    let start = CGPoint(x: app.x + 84, y: app.y)
    let end = CGPoint(x: applications.x - 90, y: applications.y)
    let tail = CGPoint(x: end.x - 14, y: end.y - 3)
    let curve = CGMutablePath()
    curve.move(to: start)
    curve.addCurve(
        to: tail, control1: CGPoint(x: start.x + 50, y: start.y - 26), control2: CGPoint(x: tail.x - 50, y: tail.y - 24))
    let dots = curve.copy(dashingWithPhase: 0, lengths: [1, 11])
        .copy(strokingWithWidth: 4, lineCap: .round, lineJoin: .round, miterLimit: 10)
    let head = CGMutablePath()
    head.move(to: CGPoint(x: end.x - 13, y: end.y - 11))
    head.addLine(to: CGPoint(x: end.x + 2, y: end.y))
    head.addLine(to: CGPoint(x: end.x - 13, y: end.y + 11))
    let headStroke = head.copy(strokingWithWidth: 4, lineCap: .round, lineJoin: .round, miterLimit: 10)

    cg.saveGState()
    cg.addPath(dots)
    cg.addPath(headStroke)
    cg.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [indigo.cgColor, teal.cgColor] as CFArray,
        locations: [0, 1])!
    cg.drawLinearGradient(
        gradient, start: CGPoint(x: start.x, y: 0), end: CGPoint(x: end.x + 2, y: 0),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    cg.restoreGState()

    NSGraphicsContext.current = nil
    guard let png = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
    try png.write(to: url)
}

try draw(scale: 1, to: out.appending(path: "background.png"))
try draw(scale: 2, to: out.appending(path: "background@2x.png"))
print("dmg-background: \(out.path())background.png and background@2x.png")
