import Foundation
import PullwatchCore

extension Bundle {
    /// De teksten van PullwatchGitHub in de taal die de app gekozen heeft, zoals
    /// `Bundle.localizedCore` voor PullwatchCore.
    static let localizedGitHub: Bundle = gitHub(for: Bundle.main.preferredLocalizations.first)

    static func gitHub(for language: String?) -> Bundle {
        localized(#bundle, for: language)
    }
}
