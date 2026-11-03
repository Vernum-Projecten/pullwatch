import Foundation
import PullwatchCore
import Testing

@testable import Pullwatch

/// Wat de schermen over een update zeggen: elke blokkade heeft een reden met de uitweg, en de
/// versie die nu kan staat er alleen bij als die iets toevoegt.
@MainActor @Suite struct UpdateStatusTests {
    private func status(_ status: PackageUpdate.Status, step: UpdateStep? = .major, usable: String? = nil,
                        requested: String? = "^4.5.0") -> UpdateStatus {
        UpdateStatus(update: PackageUpdate(status: status, step: step, latest: "6.0.0", usable: usable), installed: "4.5.0", requested: requested)
    }

    @Test func everyBlockerSaysWhatToDoFirst() {
        let blocked: [PackageUpdate.Status] = [
            .blockedByPackage(parent: "express", parentRange: "~6.11.0", minimumParentVersion: "4.21.0"),
            .blockedByPackage(parent: "express", parentRange: "~6.11.0", minimumParentVersion: nil),
            .blockedByPeer(name: "react", needs: "^19.0.0", installed: "18.3.1"),
            .blockedByRuntime(runtime: "nodejs", needs: ">=20", installed: "18"),
        ]
        for item in blocked {
            let shown = status(item)
            #expect(shown.category == .blocked)
            #expect(shown.reason != nil)
            #expect(shown.spoken.count > String(localized: shown.label).count, "VoiceOver leest ook de reden")
        }
        let reasons = blocked.compactMap { status($0).reason.map { String(localized: $0) } }
        #expect(Set(reasons).count == reasons.count)
    }

    @Test func rangeReasonNeedsTheRequestedRange() {
        #expect(status(.withinRange, step: .patch).reason != nil)
        #expect(status(.withinRange, step: .patch, requested: nil).reason == nil)
        #expect(status(.needsManifestChange).reason != nil)
        #expect(status(.upToDate).reason == nil)
    }

    @Test func labelsFollowStepAndStatus() {
        let labels = [
            status(.withinRange, step: .patch), status(.withinRange, step: .minor), status(.needsManifestChange, step: .major),
            status(.needsManifestChange, step: .minor), status(.blockedByPeer(name: "react", needs: "^19", installed: "18.3.1")),
            status(.upToDate),
        ].map { String(localized: $0.label) }
        #expect(Set(labels).count == labels.count)
    }

    @Test func usableNowOnlyWhenItAddsSomething() {
        #expect(status(.blockedByRuntime(runtime: "nodejs", needs: ">=18", installed: "16"), usable: "4.5.5").usableNow == "4.5.5")
        #expect(status(.withinRange, usable: "6.0.0").usableNow == nil, "dat is de nieuwste al")
        #expect(status(.blockedByRuntime(runtime: "nodejs", needs: ">=18", installed: "16"), usable: "4.5.0").usableNow == nil,
                "dat is wat er al staat")
    }

    @Test func runtimeNamesAreTheOnesDevelopersUse() {
        #expect(Runtime.name("nodejs") == "Node")
        #expect(Runtime.name("dotnet") == ".NET")
        #expect(Runtime.name("go") == "Go")
    }
}
