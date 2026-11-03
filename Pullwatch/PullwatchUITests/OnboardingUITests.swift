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
            // De echte vraag om meldingen is een systeemvenster buiten de app.
            "-PullwatchSkipNotificationRequest", "YES",
        ]
        if let shots = ProcessInfo.processInfo.environment["PULLWATCH_SHOTS"] {
            app.launchArguments += ["-PullwatchSnapshotDirectory", URL(filePath: shots).appending(path: language).path(percentEncoded: false)]
        }
        app.launch()
        // Zoals openen vanuit de Finder: de app vooraan. Gestart door de test-runner blijft een
        // menubalk-app anders achter andere vensters staan.
        app.activate()
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    /// Klikt pas als het element er is en klikbaar is; anders gaat een klik vlak na het openen
    /// van het venster soms verloren.
    private func tap(_ app: XCUIApplication, _ id: String) {
        let target = element(app, id)
        XCTAssertTrue(target.waitForExistence(timeout: 10), "\(id) verschijnt")
        let hittable = NSPredicate(format: "isHittable == true")
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: hittable, evaluatedWith: target)], timeout: 10), .completed, "\(id) is klikbaar")
        target.click()
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

        tap(app, "onboarding.start")
        XCTAssertTrue(element(app, "onboarding.account").waitForExistence(timeout: 10), "stap 2: het eerste account")

        tap(app, "onboarding.addGitHub")
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 10), "de accountgegevens verschijnen")

        tap(app, "onboarding.skip")
        XCTAssertTrue(element(app, "onboarding.finish").waitForExistence(timeout: 10), "stap 3: meldingen en inloggen")
        XCTAssertTrue(element(app, "onboarding.notifications").exists, "de rij voor meldingen staat er")

        tap(app, "onboarding.done")
        XCTAssertTrue(element(app, "onboarding.welcome").waitForNonExistence(timeout: 5) || !element(app, "onboarding.finish").exists, "Klaar sluit het venster")
        XCTAssertFalse(element(app, "onboarding.finish").exists, "het welkomstvenster is dicht")
    }
}
