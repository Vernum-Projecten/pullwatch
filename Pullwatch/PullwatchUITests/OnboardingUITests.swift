import XCTest

/// De eerste start: een lege datamap (`-PullwatchDataDirectory`), dus geen accounts en geen
/// echte config of geschiedenis. Het welkomstvenster moet vanzelf openen en elke stap werken.
/// Met `PULLWATCH_SHOTS=<map>` (via `TEST_RUNNER_PULLWATCH_SHOTS` voor xcodebuild) tekent de
/// debug-app elke stap zelf naar die map (`SnapshotCamera`), ook zonder schermopname-toestemming.
@MainActor
final class OnboardingUITests: XCTestCase {
    private var dataDirectory: URL!

    override func setUp() {
        continueAfterFailure = false
        dataDirectory = FileManager.default.temporaryDirectory.appending(path: "pullwatch-uitest-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dataDirectory)
    }

    private func launchFirstRun(language: String = "nl") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-PullwatchDataDirectory", dataDirectory.path(percentEncoded: false),
            "-onboardingCompleted", "NO",
            "-ApplePersistenceIgnoreState", "YES",
            "-AppleLanguages", "(\(language))",
        ]
        if let shots = ProcessInfo.processInfo.environment["PULLWATCH_SHOTS"] {
            app.launchArguments += ["-PullwatchSnapshotDirectory", URL(filePath: shots).appending(path: language).path(percentEncoded: false)]
        }
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }


    func testTheWelcomeOpensByItselfAndEveryStepWorks() {
        walkThrough(language: "nl")
    }

    func testTheWelcomeInEnglish() {
        walkThrough(language: "en")
    }

    private func walkThrough(language: String) {
        let app = launchFirstRun(language: language)

        XCTAssertTrue(element(app, "onboarding.welcome").waitForExistence(timeout: 15), "het welkomstvenster opent bij de eerste start")

        element(app, "onboarding.start").click()
        XCTAssertTrue(element(app, "onboarding.account").waitForExistence(timeout: 5), "stap 2: het eerste account")

        element(app, "onboarding.addGitHub").click()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5), "de accountgegevens verschijnen")

        element(app, "onboarding.skip").click()
        XCTAssertTrue(element(app, "onboarding.finish").waitForExistence(timeout: 5), "stap 3: meldingen en inloggen")
        XCTAssertTrue(element(app, "onboarding.allowNotifications").exists)

        element(app, "onboarding.done").click()
        XCTAssertTrue(element(app, "onboarding.welcome").waitForNonExistence(timeout: 5) || !element(app, "onboarding.finish").exists, "Klaar sluit het venster")
        XCTAssertFalse(element(app, "onboarding.finish").exists, "het welkomstvenster is dicht")
    }
}
