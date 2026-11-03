import Foundation
import Testing
@testable import PullwatchCore

/// Of `range` de versies in `inside` bevat en die in `outside` niet.
private func check(_ range: VersionRange?, _ text: String, in inside: [String], out outside: [String],
                   sourceLocation: SourceLocation = #_sourceLocation) {
    guard let range else {
        Issue.record("\(text) is geen bereik", sourceLocation: sourceLocation)
        return
    }
    for version in inside {
        #expect(range.contains(version), "\(text) bevat \(version)", sourceLocation: sourceLocation)
    }
    for version in outside {
        #expect(!range.contains(version), "\(text) bevat \(version) niet", sourceLocation: sourceLocation)
    }
}

/// Versies vergelijken: semver.org §11, PEP 440 en hetzelfde als `VersionChecker.isOlder`.
@Suite struct VersionOrderTests {
    private func ascending(_ versions: [String], implicitPostRelease: Bool = false, sourceLocation: SourceLocation = #_sourceLocation) {
        let parsed = versions.compactMap { Version($0, implicitPostRelease: implicitPostRelease) }
        #expect(parsed.count == versions.count, "alle versies te lezen", sourceLocation: sourceLocation)
        for (a, b) in zip(parsed, parsed.dropFirst()) {
            #expect(a < b, "\(a) < \(b)", sourceLocation: sourceLocation)
        }
    }

    /// https://semver.org/#spec-item-11
    @Test func semverPrecedence() {
        ascending(["1.0.0", "2.0.0", "2.1.0", "2.1.1"])
        ascending(["1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta", "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0"])
        #expect(Version("1.0.0+20130313144700") == Version("1.0.0"))
        #expect(Version("1.0.0-alpha+001") == Version("1.0.0-alpha"))
    }

    /// https://packaging.python.org/en/latest/specifications/version-specifiers/#summary-of-permitted-suffixes-and-relative-ordering
    @Test func pep440Ordering() {
        ascending([
            "1.dev0", "1.0.dev456", "1.0a1", "1.0a2.dev456", "1.0a12.dev456", "1.0a12", "1.0b1.dev456", "1.0b2",
            "1.0b2.post345.dev456", "1.0b2.post345", "1.0rc1.dev456", "1.0rc1", "1.0", "1.0.post456.dev34",
            "1.0.post456", "1.0.15", "1.1.dev1",
        ])
        #expect(Version("1!1.0")! > Version("2.0")!)
        // Andere spellingen van hetzelfde (normalisatie).
        #expect(Version("1.0alpha1") == Version("1.0a1"))
        #expect(Version("1.0-c1") == Version("1.0rc1"))
        #expect(Version("1.0-1", implicitPostRelease: true) == Version("1.0.post1"))
        #expect(Version("1.0.rev2") == Version("1.0.post2"))
    }

    @Test func otherEcosystems() {
        // RubyGems: een letter maakt een pre-release.
        ascending(["1.0.0.a", "1.0.0.beta1", "1.0.0.beta2", "1.0.0.rc1", "1.0.0", "1.0.1"])
        // Composer: dev < alpha < beta < RC < stabiel < patch.
        ascending(["1.0.0-dev", "1.0.0-alpha1", "1.0.0-beta2", "1.0.0-RC1", "1.0.0", "1.0.0-patch1", "1.0.1"])
        // NuGet: vier delen, "1.0" is "1.0.0.0".
        ascending(["1.0.0.1", "1.0.0.2", "1.0.1"])
        #expect(Version("1.0") == Version("1.0.0.0"))
        // Go: "v" vooraan en +incompatible tellen niet.
        #expect(Version("v2.0.0+incompatible") == Version("2.0.0"))
        #expect(Version("v0.0.0-20240101120000-abcdef123456")!.isPrerelease)
        #expect(Version("latest") == nil)
        #expect(Version("dev-main") == nil)
    }

    @Test func agreesWithIsOlderOnReleases() {
        let versions = ["1", "1.0", "1.0.0", "1.9", "1.10", "1.10.1", "2", "8", "8.0", "10.0.0.1", "0.0.1"]
        for a in versions {
            for b in versions {
                #expect((Version(a)! < Version(b)!) == VersionChecker.isOlder(a, than: b), "\(a) en \(b)")
            }
        }
    }

    @Test func stepSize() {
        #expect(UpdateStep(from: Version("4.17.15")!, to: Version("4.17.21")!) == .patch)
        #expect(UpdateStep(from: Version("4.17.15")!, to: Version("4.18.0")!) == .minor)
        #expect(UpdateStep(from: Version("18.3.1")!, to: Version("19.0.0")!) == .major)
        #expect(UpdateStep(from: Version("1.0.0")!, to: Version("1.0.0")!) == nil)
        #expect(UpdateStep(from: Version("2.0.0")!, to: Version("1.0.0")!) == nil)
        #expect(UpdateStep.patch < .minor && UpdateStep.minor < .major)
    }
}

/// https://github.com/npm/node-semver#ranges
@Suite struct NpmRangeTests {
    private func npm(_ text: String) -> VersionRange? { NpmRange.parse(text) }

    @Test func comparatorsAndSets() {
        check(npm(">=1.2.7"), ">=1.2.7", in: ["1.2.7", "1.2.8", "2.5.3", "1.3.9"], out: ["1.2.6", "1.1.0"])
        check(npm(">=1.2.7 <1.3.0"), ">=1.2.7 <1.3.0", in: ["1.2.7", "1.2.8", "1.2.99"], out: ["1.2.6", "1.3.0", "1.1.0"])
        check(npm("1.2.7 || >=1.2.9 <2.0.0"), "1.2.7 || >=1.2.9 <2.0.0", in: ["1.2.7", "1.2.9", "1.4.6"], out: ["1.2.8", "2.0.0"])
        check(npm(">= 1.2.7 < 1.3.0"), "spaties na de operator", in: ["1.2.8"], out: ["1.3.0"])
        check(npm("=v1.2.3"), "=v1.2.3", in: ["1.2.3"], out: ["1.2.4"])
    }

    @Test func prereleaseNeedsTheSameTuple() {
        check(npm(">1.2.3-alpha.3"), ">1.2.3-alpha.3", in: ["1.2.3-alpha.7", "3.4.5"], out: ["3.4.5-alpha.9", "1.2.3-alpha.2"])
        check(npm("^1.2.3"), "^1.2.3", in: ["1.9.0"], out: ["1.9.0-beta.1", "2.0.0-alpha"])
    }

    @Test func hyphenRanges() {
        check(npm("1.2.3 - 2.3.4"), "1.2.3 - 2.3.4", in: ["1.2.3", "2.3.4"], out: ["1.2.2", "2.3.5"])
        check(npm("1.2 - 2.3.4"), "1.2 - 2.3.4", in: ["1.2.0"], out: ["1.1.9"])
        check(npm("1.2.3 - 2.3"), "1.2.3 - 2.3", in: ["2.3.9"], out: ["2.4.0", "2.4.0-0"])
        check(npm("1.2.3 - 2"), "1.2.3 - 2", in: ["2.9.9"], out: ["3.0.0"])
    }

    @Test func xRanges() {
        check(npm("*"), "*", in: ["0.0.1", "1.0.0", "99.0.0"], out: ["1.0.0-beta"])
        check(npm(""), "leeg", in: ["0.0.1", "5.0.0"], out: [])
        check(npm("1.x"), "1.x", in: ["1.0.0", "1.9.9"], out: ["2.0.0", "0.9.9"])
        check(npm("1.2.x"), "1.2.x", in: ["1.2.0", "1.2.9"], out: ["1.3.0"])
        check(npm("1"), "1", in: ["1.0.0", "1.9.9"], out: ["2.0.0"])
        check(npm("1.2"), "1.2", in: ["1.2.0", "1.2.9"], out: ["1.3.0"])
        check(npm("1.2.*"), "1.2.*", in: ["1.2.5"], out: ["1.3.0"])
        check(npm(">1.2"), ">1.2", in: ["1.3.0"], out: ["1.2.9"])
        check(npm("<=1.2"), "<=1.2", in: ["1.2.9"], out: ["1.3.0"])
        check(npm("<1.2"), "<1.2", in: ["1.1.9"], out: ["1.2.0"])
    }

    @Test func tildeRanges() {
        check(npm("~1.2.3"), "~1.2.3", in: ["1.2.3", "1.2.9"], out: ["1.3.0", "1.2.2"])
        check(npm("~1.2"), "~1.2", in: ["1.2.0", "1.2.9"], out: ["1.3.0"])
        check(npm("~1"), "~1", in: ["1.0.0", "1.9.0"], out: ["2.0.0"])
        check(npm("~0.2.3"), "~0.2.3", in: ["0.2.3", "0.2.9"], out: ["0.3.0"])
        check(npm("~0.2"), "~0.2", in: ["0.2.0"], out: ["0.3.0"])
        check(npm("~0"), "~0", in: ["0.0.0", "0.9.9"], out: ["1.0.0"])
        check(npm("~1.2.3-beta.2"), "~1.2.3-beta.2", in: ["1.2.3-beta.4", "1.2.3", "1.2.9"], out: ["1.2.4-beta.2", "1.2.3-beta.1"])
    }

    @Test func caretRanges() {
        check(npm("^1.2.3"), "^1.2.3", in: ["1.2.3", "1.9.9"], out: ["2.0.0", "1.2.2"])
        check(npm("^0.2.3"), "^0.2.3", in: ["0.2.3", "0.2.9"], out: ["0.3.0"])
        check(npm("^0.0.3"), "^0.0.3", in: ["0.0.3"], out: ["0.0.4"])
        check(npm("^1.2.3-beta.2"), "^1.2.3-beta.2", in: ["1.2.3-beta.4", "1.9.0"], out: ["1.2.4-beta.2"])
        check(npm("^0.0.3-beta"), "^0.0.3-beta", in: ["0.0.3-pr.2", "0.0.3"], out: ["0.0.4"])
        check(npm("^1.2.x"), "^1.2.x", in: ["1.2.0", "1.9.0"], out: ["2.0.0"])
        check(npm("^0.0.x"), "^0.0.x", in: ["0.0.9"], out: ["0.1.0"])
        check(npm("^0.0"), "^0.0", in: ["0.0.9"], out: ["0.1.0"])
        check(npm("^1.x"), "^1.x", in: ["1.0.0", "1.9.9"], out: ["2.0.0"])
        check(npm("^0.x"), "^0.x", in: ["0.9.9"], out: ["1.0.0"])
    }

    @Test func aliasesAndNonRanges() {
        check(npm("npm:string-width@^4.2.0"), "alias", in: ["4.2.3"], out: ["5.0.0"])
        check(npm("npm:^4.17.0"), "Berry-descriptor", in: ["4.17.21"], out: ["5.0.0"])
        for text in ["latest", "next", "file:../lib", "git+https://github.com/a/b.git", "github:a/b", "a/b", "workspace:*", "npm:lodash"] {
            #expect(npm(text) == nil, "\(text) is geen bereik")
        }
    }
}

/// https://doc.rust-lang.org/cargo/reference/specifying-dependencies.html
@Suite struct CargoRequirementTests {
    private func cargo(_ text: String) -> VersionRange? { CargoRequirement.parse(text) }

    @Test func defaultIsCaret() {
        check(cargo("1.2.3"), "1.2.3", in: ["1.2.3", "1.9.0"], out: ["2.0.0", "1.2.2"])
        check(cargo("1.2"), "1.2", in: ["1.2.0"], out: ["2.0.0"])
        check(cargo("1"), "1", in: ["1.0.0"], out: ["2.0.0"])
        check(cargo("0.2.3"), "0.2.3", in: ["0.2.3"], out: ["0.3.0"])
        check(cargo("0.2"), "0.2", in: ["0.2.0"], out: ["0.3.0"])
        check(cargo("0.0.3"), "0.0.3", in: ["0.0.3"], out: ["0.0.4"])
        check(cargo("0.0"), "0.0", in: ["0.0.9"], out: ["0.1.0"])
        check(cargo("0"), "0", in: ["0.9.0"], out: ["1.0.0"])
        check(cargo("^1.2.3"), "^1.2.3", in: ["1.9.0"], out: ["2.0.0"])
    }

    @Test func tildeWildcardAndComparisons() {
        check(cargo("~1.2.3"), "~1.2.3", in: ["1.2.9"], out: ["1.3.0"])
        check(cargo("~1.2"), "~1.2", in: ["1.2.0"], out: ["1.3.0"])
        check(cargo("~1"), "~1", in: ["1.9.0"], out: ["2.0.0"])
        check(cargo("*"), "*", in: ["0.0.1", "9.0.0"], out: [])
        check(cargo("1.*"), "1.*", in: ["1.0.0"], out: ["2.0.0"])
        check(cargo("1.2.*"), "1.2.*", in: ["1.2.9"], out: ["1.3.0"])
        check(cargo(">= 1.2.0"), ">= 1.2.0", in: ["1.2.0", "5.0.0"], out: ["1.1.9"])
        check(cargo("> 1"), "> 1", in: ["2.0.0"], out: ["1.9.9"])
        check(cargo("< 2"), "< 2", in: ["1.9.9"], out: ["2.0.0"])
        check(cargo("= 1.2.3"), "= 1.2.3", in: ["1.2.3"], out: ["1.2.4"])
        check(cargo(">= 1.2, < 1.5"), ">= 1.2, < 1.5", in: ["1.2.0", "1.4.9"], out: ["1.5.0", "1.1.0"])
    }

    @Test func prereleases() {
        check(cargo("1.0.0-alpha"), "1.0.0-alpha", in: ["1.0.0-beta", "1.5.0"], out: ["1.5.0-beta"])
        check(cargo("^1.0.0"), "^1.0.0", in: ["1.1.0"], out: ["1.1.0-beta"])
        #expect(cargo("1.0,") == nil)
    }
}

/// https://getcomposer.org/doc/articles/versions.md
@Suite struct ComposerConstraintTests {
    private func composer(_ text: String) -> VersionRange? { ComposerConstraint.parse(text) }

    @Test func rangesAndLogic() {
        check(composer(">=1.0"), ">=1.0", in: ["1.0.0", "3.0.0"], out: ["0.9.0"])
        check(composer(">=1.0 <2.0"), ">=1.0 <2.0", in: ["1.9.9"], out: ["2.0.0"])
        check(composer(">=1.0,<2.0"), ">=1.0,<2.0", in: ["1.9.9"], out: ["2.0.0"])
        check(composer(">=1.0 <1.1 || >=1.2"), ">=1.0 <1.1 || >=1.2", in: ["1.0.5", "1.2.0", "3.0.0"], out: ["1.1.0", "0.9.0"])
        check(composer("^1.0 | ^2.0"), "^1.0 | ^2.0", in: ["1.5.0", "2.5.0"], out: ["3.0.0"])
        check(composer("!=1.0.1"), "!=1.0.1", in: ["1.0.2"], out: ["1.0.1"])
    }

    @Test func exactHyphenAndWildcard() {
        check(composer("1.0.2"), "1.0.2", in: ["1.0.2"], out: ["1.0.3"])
        check(composer("1.0"), "1.0", in: ["1.0.0"], out: ["1.0.1"])
        check(composer("1.0 - 2.0"), "1.0 - 2.0", in: ["1.0.0", "2.0.9"], out: ["2.1.0"])
        check(composer("1.0.0 - 2.1.0"), "1.0.0 - 2.1.0", in: ["2.1.0"], out: ["2.1.1"])
        check(composer("1.0.*"), "1.0.*", in: ["1.0.0", "1.0.9"], out: ["1.1.0"])
        check(composer("*"), "*", in: ["1.0.0"], out: [])
    }

    @Test func tildeAndCaret() {
        check(composer("~1.2"), "~1.2", in: ["1.2.0", "1.9.0"], out: ["2.0.0"])
        check(composer("~1.2.3"), "~1.2.3", in: ["1.2.3", "1.2.9"], out: ["1.3.0"])
        check(composer("~1"), "~1", in: ["1.9.0"], out: ["2.0.0"])
        check(composer("^1.2.3"), "^1.2.3", in: ["1.9.9"], out: ["2.0.0"])
        check(composer("^0.3"), "^0.3", in: ["0.3.9"], out: ["0.4.0"])
        check(composer("v1.2.*"), "v-voorvoegsel", in: ["1.2.5"], out: ["1.3.0"])
    }

    @Test func stability() {
        check(composer("^1.0"), "^1.0", in: ["1.2.0"], out: ["1.2.0-beta1"])
        check(composer("^1.0@beta"), "^1.0@beta", in: ["1.2.0-beta1"], out: ["2.0.0-beta1"])
        check(composer(">=1.0.0-RC1"), ">=1.0.0-RC1", in: ["1.0.0-RC2", "1.0.0"], out: ["1.0.0-beta1"])
        check(composer("1.0.x-dev as 1.0.0"), "alias", in: ["1.0.5"], out: ["1.1.0"])
        #expect(composer("dev-main") == nil)
    }
}

/// https://packaging.python.org/en/latest/specifications/version-specifiers/
@Suite struct PEP440SpecifierTests {
    private func pep(_ text: String) -> VersionRange? { PEP440Specifier.parse(text) }

    @Test func compatibleRelease() {
        check(pep("~= 2.2"), "~= 2.2", in: ["2.2", "2.9"], out: ["3.0", "2.1"])
        check(pep("~= 1.4.5"), "~= 1.4.5", in: ["1.4.5", "1.4.9"], out: ["1.5.0", "1.4.4"])
        check(pep("~= 2.2.post3"), "~= 2.2.post3", in: ["2.2.post3", "2.9"], out: ["2.2", "3.0"])
        check(pep("~= 1.4.5a4"), "~= 1.4.5a4", in: ["1.4.5a4", "1.4.5", "1.4.9"], out: ["1.5.0", "1.4.5a3"])
        #expect(pep("~=1") == nil)
    }

    @Test func versionMatching() {
        // Het voorbeeld van de specificatie: 1.1.post1.
        check(pep("== 1.1"), "== 1.1", in: ["1.1", "1.1.0"], out: ["1.1.post1"])
        check(pep("== 1.1.post1"), "== 1.1.post1", in: ["1.1.post1"], out: ["1.1"])
        check(pep("== 1.1.*"), "== 1.1.*", in: ["1.1.post1", "1.1.5"], out: ["1.2"])
        check(pep("== 3.1"), "== 3.1", in: ["3.1.0"], out: ["3.1.1"])
        check(pep("!= 1.1"), "!= 1.1", in: ["1.1.post1"], out: ["1.1"])
        check(pep("!= 1.1.*"), "!= 1.1.*", in: ["1.2"], out: ["1.1.post1", "1.1.9"])
        check(pep("===1.0"), "===1.0", in: ["1.0"], out: ["1.0.0"])
        check(pep("== 1.0"), "lokaal label telt niet", in: ["1.0+ubuntu.1"], out: [])
    }

    @Test func exclusiveComparisons() {
        check(pep(">1.7"), ">1.7", in: ["1.7.1"], out: ["1.7", "1.7.0.post1"])
        check(pep(">1.7.post2"), ">1.7.post2", in: ["1.7.1", "1.7.0.post3"], out: ["1.7.0.post2"])
        check(pep(">=3.0a1, <3.1"), ">=3.0a1, <3.1", in: ["3.0b1", "3.0.5"], out: ["3.1rc1", "3.1.dev0"])
        check(pep("<3.1a2"), "<3.1a2", in: ["3.1a1", "3.0"], out: ["3.1a2"])
        check(pep(">=2.28,<3"), ">=2.28,<3", in: ["2.28.0", "2.32.3"], out: ["3.0.0", "2.27.1"])
    }

    @Test func prereleasesOnlyWhenNamed() {
        check(pep(">=1.0"), ">=1.0", in: ["2.0"], out: ["2.0b1", "2.0.dev1"])
        check(pep(">=1.0b1"), ">=1.0b1", in: ["2.0b1", "1.0b1"], out: [])
    }

    @Test func poetrySyntax() {
        check(pep("^1.2.3"), "^1.2.3", in: ["1.9.0"], out: ["2.0.0"])
        check(pep("^0.2.3"), "^0.2.3", in: ["0.2.9"], out: ["0.3.0"])
        check(pep("~1.2"), "~1.2", in: ["1.2.9"], out: ["1.3.0"])
        check(pep("1.2.*"), "1.2.*", in: ["1.2.5"], out: ["1.3.0"])
        check(pep("*"), "*", in: ["0.1"], out: [])
        check(pep("2.0.1"), "kale versie", in: ["2.0.1"], out: ["2.0.2"])
        check(pep(">=1.2,<1.5 || ^2.0"), "||", in: ["1.3", "2.5"], out: ["1.6", "3.0"])
    }
}

/// https://learn.microsoft.com/nuget/concepts/package-versioning#version-ranges
@Suite struct NuGetRangeTests {
    private func nuget(_ text: String) -> VersionRange? { NuGetRange.parse(text) }

    @Test func documentationTable() {
        check(nuget("1.0"), "1.0", in: ["1.0", "1.0.0", "5.0"], out: ["0.9"])
        check(nuget("[1.0,)"), "[1.0,)", in: ["1.0", "2.0"], out: ["0.9"])
        check(nuget("(1.0,)"), "(1.0,)", in: ["1.0.1"], out: ["1.0"])
        check(nuget("[1.0]"), "[1.0]", in: ["1.0", "1.0.0.0"], out: ["1.0.1"])
        check(nuget("(,1.0]"), "(,1.0]", in: ["1.0", "0.1"], out: ["1.0.1"])
        check(nuget("(,1.0)"), "(,1.0)", in: ["0.9"], out: ["1.0"])
        check(nuget("[1.0,2.0]"), "[1.0,2.0]", in: ["1.0", "2.0"], out: ["2.0.1"])
        check(nuget("(1.0,2.0)"), "(1.0,2.0)", in: ["1.5"], out: ["1.0", "2.0"])
        check(nuget("[1.0,2.0)"), "[1.0,2.0)", in: ["1.0", "1.9.9"], out: ["2.0"])
        check(nuget("[13.0.1, )"), "spatie in het bereik", in: ["13.0.3"], out: ["13.0.0"])
        #expect(nuget("(1.0)") == nil)
        #expect(nuget("$(NewtonsoftVersion)") == nil)
    }

    @Test func floatingVersions() {
        check(nuget("1.*"), "1.*", in: ["1.0.0", "1.9.0"], out: ["2.0.0"])
        check(nuget("1.0.*"), "1.0.*", in: ["1.0.9"], out: ["1.1.0"])
        check(nuget("*"), "*", in: ["0.1.0", "9.0.0"], out: ["9.0.0-beta"])
        check(nuget("1.0.0-*"), "1.0.0-*", in: ["1.0.0-beta", "1.0.0", "1.2.0"], out: ["0.9.0"])
        check(nuget("[1.0.0-beta, 2.0)"), "pre-release als ondergrens", in: ["1.5.0-rc.1"], out: ["2.0.0"])
        check(nuget("1.0"), "zonder pre-release", in: [], out: ["2.0.0-beta"])
    }
}

/// https://guides.rubygems.org/patterns/#pessimistic-version-constraint
@Suite struct GemRequirementTests {
    private func gem(_ text: String) -> VersionRange? { GemRequirement.parse(text) }

    @Test func pessimisticAndOperators() {
        check(gem("~> 2.2"), "~> 2.2", in: ["2.2", "2.9.9"], out: ["3.0", "2.1"])
        check(gem("~> 2.2.0"), "~> 2.2.0", in: ["2.2.0", "2.2.5"], out: ["2.3", "2.1"])
        check(gem("~> 2"), "~> 2", in: ["2.0", "2.9"], out: ["3.0"])
        check(gem("~> 7.1, >= 7.1.2"), "~> 7.1, >= 7.1.2", in: ["7.1.2", "7.9.0"], out: ["7.1.1", "8.0.0"])
        check(gem(">= 1.0, < 2"), ">= 1.0, < 2", in: ["1.5"], out: ["2.0"])
        check(gem("!= 1.0.1"), "!= 1.0.1", in: ["1.0.2"], out: ["1.0.1"])
        check(gem("= 1.0"), "= 1.0", in: ["1.0.0"], out: ["1.0.1"])
        check(gem("1.0"), "kale versie", in: ["1.0"], out: ["1.1"])
    }

    @Test func prereleases() {
        check(gem(">= 1.0"), ">= 1.0", in: ["2.0.0"], out: ["2.0.0.beta1"])
        check(gem(">= 2.0.0.a"), ">= 2.0.0.a", in: ["2.0.0.beta1", "2.0.0"], out: [])
        // bump laat pre-releasedelen weg: ~> 1.0.0.beta is >= 1.0.0.beta, < 1.1.
        check(gem("~> 1.0.0.beta"), "~> 1.0.0.beta", in: ["1.0.0.rc1", "1.0.5"], out: ["1.1.0"])
        #expect(gem("") == nil)
    }
}

/// https://go.dev/ref/mod#major-version-suffixes
@Suite struct GoModuleRequirementTests {
    private func go(_ module: String, _ version: String) -> VersionRange? { GoModuleRequirement.parse(module: module, version: version) }

    @Test func majorIsInThePath() {
        check(go("github.com/a/b", "v1.2.3"), "v1", in: ["1.2.3", "1.9.0"], out: ["1.2.2", "2.0.0"])
        check(go("github.com/a/b", "v0.3.1"), "v0 deelt het pad met v1", in: ["0.9.0", "1.5.0"], out: ["2.0.0"])
        check(go("github.com/a/b/v2", "v2.1.0"), "/v2", in: ["2.5.0"], out: ["3.0.0", "2.0.9"])
        check(go("gopkg.in/yaml.v3", "v3.0.1"), "gopkg.in", in: ["3.0.2"], out: ["4.0.0"])
        check(go("github.com/a/b", "v2.0.0+incompatible"), "+incompatible", in: ["2.1.0", "5.0.0+incompatible"], out: ["1.9.0"])
        #expect(go("github.com/a/b", "latest") == nil)
    }
}

/// https://developer.apple.com/documentation/packagedescription/package/dependency
@Suite struct SwiftRequirementTests {
    private func swift(_ text: String) -> VersionRange? { SwiftRequirement.parse(text) }

    @Test func requirements() {
        check(swift(#"from: "1.2.3""#), "from", in: ["1.2.3", "1.9.0"], out: ["2.0.0", "1.2.2"])
        check(swift(#".upToNextMajor(from: "5.0.0")"#), "upToNextMajor", in: ["5.9.0"], out: ["6.0.0"])
        check(swift(#".upToNextMinor(from: "1.2.3")"#), "upToNextMinor", in: ["1.2.9"], out: ["1.3.0"])
        check(swift(#"exact: "1.2.3""#), "exact", in: ["1.2.3"], out: ["1.2.4"])
        check(swift(#".exact("1.2.3")"#), ".exact", in: ["1.2.3"], out: ["1.2.4"])
        check(swift(#""1.2.3"..<"1.5.0""#), "..<", in: ["1.4.9"], out: ["1.5.0"])
        check(swift(#""1.2.3"..."1.5.0""#), "...", in: ["1.5.0"], out: ["1.5.1"])
        check(swift(#"from: "1.0.0""#), "zonder pre-release", in: [], out: ["1.5.0-beta.1"])
        #expect(swift(#"branch: "main""#) == nil)
        #expect(swift(#"revision: "abc123""#) == nil)
    }
}

@Suite struct VersionRangeDispatchTests {
    @Test func parsesPerEcosystem() {
        #expect(VersionRange.parse(ecosystem: "npm", name: "lodash", requested: "^4.17.0")?.allowsUpdate(to: "4.17.21") == true)
        #expect(VersionRange.parse(ecosystem: "Packagist", name: "a/b", requested: "~1.2")?.allowsUpdate(to: "1.9.0") == true)
        #expect(VersionRange.parse(ecosystem: "PyPI", name: "requests", requested: ">=2.28,<3")?.allowsUpdate(to: "3.0.0") == false)
        #expect(VersionRange.parse(ecosystem: "crates.io", name: "serde", requested: "1.0")?.allowsUpdate(to: "1.0.210") == true)
        #expect(VersionRange.parse(ecosystem: "NuGet", name: "X", requested: "[13.0.1, )")?.allowsUpdate(to: "13.0.3") == true)
        #expect(VersionRange.parse(ecosystem: "RubyGems", name: "rails", requested: "~> 7.1")?.allowsUpdate(to: "8.0.0") == false)
        #expect(VersionRange.parse(ecosystem: "Go", name: "github.com/a/b/v2", requested: "v2.1.0")?.allowsUpdate(to: "2.3.0") == true)
        #expect(VersionRange.parse(ecosystem: "SwiftURL", name: "github.com/apple/swift-nio", requested: #"from: "2.0.0""#)?.allowsUpdate(to: "3.0.0") == false)
        #expect(VersionRange.parse(ecosystem: "Hex", name: "x", requested: "~> 1.0") == nil)
        #expect(VersionRange.parse(ecosystem: "npm", name: "x", requested: "^1")?.allowsUpdate(to: "geen versie") == false)
    }
}
