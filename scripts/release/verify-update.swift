// swift scripts/release/verify-update.swift <Pullwatch.app> <appcast.xml> <update.zip>
//
// Overgenomen van FerroLICENCE. Bewijst dat de update klopt zoals de geïnstalleerde app hem
// controleert: de EdDSA-handtekening uit de appcast, gecontroleerd met de openbare sleutel in de
// eigen Info.plist van de app (SUPublicEDKey), over de bytes van de zip, en de lengte klopt.
// Daarnaast noemt de appcast hetzelfde buildnummer en dezelfde minimale macOS als de app, zodat
// Sparkle de update nooit aanbiedt op een Mac die hem niet kan openen. Een release waarvan de app
// geen of een andere sleutel heeft, faalt hier in plaats van op elke Mac die wil updaten.

import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("verify-update: \(message)\n".utf8))
    exit(1)
}

let args = Array(CommandLine.arguments.dropFirst())
guard args.count == 3 else { fail("usage: verify-update.swift <app> <appcast.xml> <update.zip>") }
let (app, appcast, zip) = (URL(filePath: args[0]), URL(filePath: args[1]), URL(filePath: args[2]))

guard let info = NSDictionary(contentsOf: app.appending(path: "Contents/Info.plist")),
    let key = info["SUPublicEDKey"] as? String, !key.isEmpty
else { fail("\(app.lastPathComponent) carries no SUPublicEDKey") }
guard let keyData = Data(base64Encoded: key), let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData)
else { fail("SUPublicEDKey is not a base64 Ed25519 public key") }

guard let feed = try? String(contentsOf: appcast, encoding: .utf8) else { fail("cannot read \(appcast.path())") }
guard feed.matches(of: #/<item>/#).count == 1 else { fail("the appcast must hold exactly one item") }
guard let enclosure = feed.firstMatch(of: #/<enclosure\b[^>]*>/#)?.output else { fail("the appcast has no enclosure") }
let attributes = Dictionary(
    enclosure.matches(of: #/([\w:]+)="([^"]*)"/#).map { (String($0.output.1), String($0.output.2)) }, uniquingKeysWith: { a, _ in a })
guard let signature = attributes["sparkle:edSignature"].flatMap({ Data(base64Encoded: $0) }) else {
    fail("the enclosure has no edSignature")
}
guard let bytes = try? Data(contentsOf: zip) else { fail("cannot read \(zip.path())") }
guard attributes["length"] == String(bytes.count) else { fail("the enclosure's length is not the zip's size") }
guard publicKey.isValidSignature(signature, for: bytes) else { fail("the signature does not verify with the app's SUPublicEDKey") }
guard let url = attributes["url"], url.hasSuffix("/" + zip.lastPathComponent) else {
    fail("the enclosure does not point at \(zip.lastPathComponent)")
}

func element(_ name: String) -> String? {
    let pattern = try! Regex("<sparkle:\(name)>([^<]+)</sparkle:\(name)>", as: (Substring, Substring).self)
    return feed.firstMatch(of: pattern).map { String($0.output.1) } ?? attributes["sparkle:\(name)"]
}
guard element("version") == info["CFBundleVersion"] as? String else {
    fail("the appcast's sparkle:version is not the app's CFBundleVersion \(info["CFBundleVersion"] ?? "")")
}
guard let minimum = info["LSMinimumSystemVersion"] as? String, element("minimumSystemVersion") == minimum else {
    fail("the appcast's sparkle:minimumSystemVersion is not the app's LSMinimumSystemVersion")
}
print("verify-update: \(zip.lastPathComponent) verifies with the app's SUPublicEDKey (build \(element("version") ?? ""), macOS \(minimum) and later)")
