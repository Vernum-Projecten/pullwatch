import SwiftUI

/// Hoe VoiceOver een PR-nummer leest: "pull request 1570", niet "nummerteken 1570".
enum PullRequestNumberText {
    static func spoken(number: Int) -> Text {
        Text("pull request \(String(number))", comment: "VoiceOver; het nummer van een pull request")
    }

    static func spoken(repo: String, number: Int) -> Text {
        Text("\(repo), pull request \(String(number))", comment: "VoiceOver; korte repo-naam en het nummer van een pull request")
    }
}
