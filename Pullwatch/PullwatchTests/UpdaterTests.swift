import Foundation
import PullwatchCore
import Testing

@testable import Pullwatch

/// Sparkle's instellingen in de gebouwde app (Info.plist uit de xcconfig) en wanneer updates in
/// de app aan staan.
@MainActor @Suite struct UpdaterTests {
    let info = Bundle.main.infoDictionary ?? [:]

    @Test func sparkleFollowsPullwatchsOwnSchedule() {
        // Pullwatch kijkt eens per dag zelf; Sparkle's eigen schema blijft uit.
        #expect(info["SUEnableAutomaticChecks"] as? Bool == false)
        #expect(info["SUAllowsAutomaticUpdates"] as? Bool == true)
    }

    @Test func checksTheSignatureBeforeUnpacking() {
        #expect(info["SUVerifyUpdateBeforeExtraction"] as? Bool == true)
    }

    @Test func readsTheReleasesOwnerFromTheBuild() {
        let owner = info["PWReleasesOwner"] as? String ?? ""
        #expect(!owner.isEmpty)
        #expect(!owner.contains("$("))
        #expect(Updater().owner == owner)
    }

    @Test func debugBuildsHaveNoKeyAndInstallNothing() {
        // Debug.xcconfig laat SPARKLE_PUBLIC_ED_KEY leeg: de oude melding blijft.
        #expect((info["SUPublicEDKey"] as? String ?? "").isEmpty)
        #expect(!Updater().isEnabled)
    }

    @Test func aKeyTurnsUpdatesOn() {
        let updater = Updater(info: ["SUPublicEDKey": "CAMlb/hqw2ufjXJ22G5CxttIHhtwpCn/jE/KUSzkE34=", "PWReleasesOwner": "Vernum-Projecten"])
        #expect(updater.isEnabled)
        #expect(updater.owner == "Vernum-Projecten")
        #expect(!Updater(info: ["SUPublicEDKey": ""]).isEnabled)
        #expect(Updater(info: [:]).owner == UpdateChecker.defaultOwner)
    }

    @Test func theBuildNumberIsWhatSparkleCompares() {
        #expect(Updater.currentBuild == info["CFBundleVersion"] as? String)
        #expect(Int(Updater.currentBuild) != nil)
    }
}
