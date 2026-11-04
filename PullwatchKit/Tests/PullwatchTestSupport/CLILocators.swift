import Foundation
import PullwatchCore

package extension CLILocator {
    /// Vindt elke CLI in /opt/homebrew/bin, zoals op een Mac met Homebrew.
    static let homebrew = CLILocator(isExecutable: { $0.hasPrefix("/opt/homebrew/bin/") })
    /// Vindt geen enkele CLI.
    static let nothing = CLILocator(isExecutable: { _ in false })
}
