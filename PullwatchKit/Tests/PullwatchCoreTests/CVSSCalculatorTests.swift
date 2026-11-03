import Foundation
import Testing
@testable import PullwatchCore

/// De voorbeelden van FIRST zelf: first.org/cvss/v3.1/examples (de basisscore per voorbeeld) en de
/// samenvattingstabellen van first.org/cvss/v4.0/examples (v3.1 en v4.0 naast elkaar).
@Suite struct CVSSCalculatorTests {
    static let v31Examples: [(String, Double)] = [
        ("CVSS:3.1/AV:N/AC:L/PR:L/UI:N/S:C/C:L/I:L/A:N", 6.4),
        ("CVSS:3.1/AV:N/AC:H/PR:N/UI:R/S:U/C:L/I:N/A:N", 3.1),
        ("CVSS:3.1/AV:N/AC:L/PR:L/UI:N/S:C/C:H/I:H/A:H", 9.9),
        ("CVSS:3.1/AV:L/AC:L/PR:H/UI:N/S:U/C:L/I:L/A:L", 4.2),
        ("CVSS:3.1/AV:N/AC:L/PR:H/UI:N/S:U/C:H/I:H/A:H", 7.2),
        ("CVSS:3.1/AV:L/AC:L/PR:N/UI:R/S:U/C:H/I:H/A:H", 7.8),
        ("CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:N/A:N", 7.5),
        ("CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H", 9.8),
        ("CVSS:3.1/AV:N/AC:H/PR:N/UI:N/S:C/C:N/I:H/A:N", 6.8),
        ("CVSS:3.1/AV:P/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H", 6.8),
        ("CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:C/C:L/I:N/A:N", 5.8),
        ("CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:C/C:N/I:L/A:N", 5.8),
        ("CVSS:3.1/AV:A/AC:L/PR:N/UI:N/S:C/C:H/I:N/A:H", 9.3),
        ("CVSS:3.1/AV:N/AC:L/PR:L/UI:R/S:C/C:H/I:H/A:H", 9.0),
        ("CVSS:3.1/AV:A/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H", 8.8),
        ("CVSS:3.1/AV:P/AC:L/PR:N/UI:N/S:U/C:N/I:H/A:N", 4.6),
        ("CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:U/C:H/I:H/A:H", 8.8),
        ("CVSS:3.1/AV:N/AC:H/PR:N/UI:N/S:U/C:H/I:H/A:N", 7.4),
        ("CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:C/C:H/I:H/A:H", 9.6),
        ("CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:C/C:L/I:L/A:N", 6.1),
        ("CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:L/A:L", 8.6),
        ("CVSS:3.1/AV:L/AC:L/PR:H/UI:N/S:C/C:H/I:H/A:H", 8.2),
        ("CVSS:3.1/AV:L/AC:L/PR:H/UI:N/S:U/C:N/I:H/A:H", 6.0),
        ("CVSS:3.1/AV:P/AC:L/PR:N/UI:N/S:C/C:H/I:H/A:H", 7.6),
        // Uit de v4.0-voorbeelden.
        ("CVSS:3.1/AV:L/AC:H/PR:L/UI:N/S:U/C:H/I:H/A:H", 7.0),
        ("CVSS:3.1/AV:N/AC:H/PR:N/UI:N/S:U/C:H/I:H/A:H", 8.1),
        ("CVSS:3.1/AV:L/AC:L/PR:N/UI:R/S:U/C:L/I:N/A:N", 3.3),
        ("CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:C/C:L/I:L/A:N", 7.2),
        ("CVSS:3.1/AV:L/AC:L/PR:H/UI:N/S:C/C:H/I:N/A:N", 6.0),
        ("CVSS:3.1/AV:L/AC:L/PR:N/UI:N/S:C/C:H/I:H/A:H", 9.3),
        ("CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:H/A:N", 7.5),
        ("CVSS:3.1/AV:N/AC:L/PR:L/UI:N/S:U/C:H/I:N/A:N", 6.5),
        ("CVSS:3.1/AV:N/AC:H/PR:N/UI:N/S:U/C:H/I:N/A:N", 5.9),
        ("CVSS:3.1/AV:N/AC:L/PR:L/UI:R/S:C/C:L/I:L/A:N", 5.4),
        ("CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:U/C:N/I:L/A:N", 4.3),
        ("CVSS:3.1/AV:N/AC:L/PR:L/UI:N/S:U/C:H/I:H/A:H", 8.8),
        ("CVSS:3.1/AV:L/AC:L/PR:H/UI:N/S:U/C:H/I:H/A:N", 6.0),
        ("CVSS:3.1/AV:P/AC:H/PR:N/UI:N/S:U/C:H/I:H/A:H", 6.4),
        ("CVSS:3.1/AV:N/AC:L/PR:H/UI:N/S:U/C:H/I:N/A:N", 4.9),
        ("CVSS:3.1/AV:A/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:N", 8.1),
        // Temporal-metrieken tellen niet mee voor de basisscore.
        ("CVSS:3.1/AV:N/AC:L/PR:L/UI:N/S:U/C:N/I:N/A:H/E:U/RL:O/RC:C", 6.5),
    ]

    static let v40Examples: [(String, Double)] = [
        ("CVSS:4.0/AV:L/AC:L/AT:P/PR:L/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N", 7.3),
        ("CVSS:4.0/AV:L/AC:L/AT:N/PR:N/UI:A/VC:L/VI:N/VA:N/SC:N/SI:N/SA:N", 4.6),
        ("CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:N/VI:N/VA:N/SC:L/SI:L/SA:N", 6.9),
        ("CVSS:4.0/AV:L/AC:L/AT:N/PR:H/UI:N/VC:N/VI:N/VA:N/SC:H/SI:N/SA:N", 5.9),
        ("CVSS:4.0/AV:L/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:H/SI:H/SA:H", 9.4),
        ("CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:N/VI:H/VA:N/SC:H/SI:H/SA:H", 9.3),
        ("CVSS:4.0/AV:P/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:H/SA:N/S:P/V:D", 8.3),
        ("CVSS:4.0/AV:A/AC:L/AT:N/PR:N/UI:N/VC:N/VI:L/VA:N/SC:H/SI:N/SA:H", 6.4),
        ("CVSS:4.0/AV:L/AC:L/AT:N/PR:H/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N/R:I", 8.4),
        ("CVSS:4.0/AV:L/AC:L/AT:P/PR:H/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N/R:I", 7.1),
        ("CVSS:4.0/AV:P/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N", 7.0),
        ("CVSS:4.0/AV:N/AC:H/AT:P/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N/E:P", 8.2),
        ("CVSS:4.0/AV:N/AC:H/AT:P/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N/E:P/MAC:L/MAT:N/MVC:N/MVI:N/MVA:L", 5.5),
        ("CVSS:4.0/AV:N/AC:L/AT:N/PR:L/UI:N/VC:H/VI:N/VA:N/SC:N/SI:N/SA:N", 7.1),
        ("CVSS:4.0/AV:N/AC:L/AT:P/PR:N/UI:N/VC:H/VI:N/VA:N/SC:N/SI:N/SA:N", 8.2),
        ("CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:A/VC:N/VI:N/VA:N/SC:L/SI:L/SA:N", 5.1),
        ("CVSS:4.0/AV:N/AC:L/AT:N/PR:L/UI:P/VC:N/VI:N/VA:N/SC:L/SI:L/SA:N", 5.1),
        ("CVSS:4.0/AV:N/AC:L/AT:N/PR:L/UI:A/VC:H/VI:H/VA:H/SC:L/SI:L/SA:N", 8.5),
        ("CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:A/VC:N/VI:L/VA:N/SC:N/SI:N/SA:N", 5.1),
        ("CVSS:4.0/AV:N/AC:L/AT:P/PR:L/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N", 7.7),
        ("CVSS:4.0/AV:L/AC:L/AT:N/PR:N/UI:P/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N", 8.5),
        ("CVSS:4.0/AV:N/AC:L/AT:P/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N/E:A", 9.2),
        ("CVSS:4.0/AV:P/AC:L/AT:P/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N", 5.4),
        ("CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:N/VA:N/SC:N/SI:N/SA:N", 8.7),
        ("CVSS:4.0/AV:N/AC:L/AT:N/PR:H/UI:N/VC:H/VI:N/VA:N/SC:N/SI:N/SA:N", 6.9),
        ("CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N", 9.3),
    ]

    @Test(arguments: v31Examples)
    func scoresFIRSTsVersion31Examples(vector: String, score: Double) {
        #expect(CVSSCalculator.score(vector) == score)
    }

    @Test(arguments: v40Examples)
    func scoresFIRSTsVersion40Examples(vector: String, score: Double) {
        #expect(CVSSCalculator.score(vector) == score)
    }

    @Test func version30RoundsUpWithoutTheFloatingPointFix() {
        #expect(CVSSCalculator.score("CVSS:3.0/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H") == 9.8)
        #expect(CVSSCalculator.score("CVSS:3.0/AV:N/AC:L/PR:N/UI:R/S:C/C:L/I:L/A:N") == 6.1)
    }

    @Test func noImpactScoresZero() {
        #expect(CVSSCalculator.score("CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:N") == 0)
        #expect(CVSSCalculator.score("CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:N/VI:N/VA:N/SC:N/SI:N/SA:N") == 0)
        // Omgevingsmetrieken die elk gevolg wegnemen.
        #expect(CVSSCalculator.score("CVSS:4.0/AV:L/AC:L/AT:N/PR:L/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N/E:A/MVC:N/MVI:N/MVA:N") == 0)
    }

    @Test func undefinedMetricsCountAsLeftOut() {
        // GHSA-262p-vjx5-45xh noemt elke metriek, de meeste met X.
        let full = "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:N/VI:H/VA:N/SC:H/SI:H/SA:N/E:X/CR:X/IR:X/AR:X/MAV:X/MAC:X/MAT:X"
            + "/MPR:X/MUI:X/MVC:X/MVI:X/MVA:X/MSC:X/MSI:X/MSA:X/S:X/AU:X/R:X/V:X/RE:X/U:X"
        #expect(CVSSCalculator.score(full) == CVSSCalculator.score("CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:N/VI:H/VA:N/SC:H/SI:H/SA:N"))
        #expect(CVSSCalculator.score(full) == 9.3)
    }

    @Test func rejectsWhatIsNoValidVector() {
        #expect(CVSSCalculator.score("AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H") == nil)
        #expect(CVSSCalculator.score("CVSS:3.1/AV:N/AC:L/PR:N/UI:N/C:H/I:H/A:H") == nil)
        #expect(CVSSCalculator.score("CVSS:3.1/AV:X/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H") == nil)
        #expect(CVSSCalculator.score("CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N") == nil)
        #expect(CVSSCalculator.score("CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N/E:Q") == nil)
        #expect(CVSSCalculator.score("CVSS:4.0/AV:N/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N") == nil)
        #expect(CVSSCalculator.score("CVSS:2.0/AV:N/AC:L/Au:N/C:P/I:P/A:P") == nil)
    }

    @Test func ratingFollowsTheSpecification() {
        #expect(CVSSCalculator.rating(0) == nil)
        #expect(CVSSCalculator.rating(0.1) == "LOW")
        #expect(CVSSCalculator.rating(3.9) == "LOW")
        #expect(CVSSCalculator.rating(4.0) == "MODERATE")
        #expect(CVSSCalculator.rating(6.9) == "MODERATE")
        #expect(CVSSCalculator.rating(7.0) == "HIGH")
        #expect(CVSSCalculator.rating(8.9) == "HIGH")
        #expect(CVSSCalculator.rating(9.0) == "CRITICAL")
        #expect(CVSSCalculator.rating(10) == "CRITICAL")
    }
}
