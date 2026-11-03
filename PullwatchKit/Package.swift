// swift-tools-version: 6.4
import PackageDescription

// Modules heten Pullwatch… zodat ze niet botsen met de typen erin (een module `GitHubProvider`
// met een type `GitHubProvider` maakt `GitHubProvider.x` dubbelzinnig).
let package = Package(
    name: "PullwatchKit",
    defaultLocalization: "nl",
    platforms: [.macOS("26.6")],
    products: [
        .library(name: "PullwatchCore", targets: ["PullwatchCore"]),
        .library(name: "PullwatchGitHub", targets: ["PullwatchGitHub"]),
        .library(name: "PullwatchProviders", targets: ["PullwatchProviders"]),
    ],
    targets: [
        // Alles zonder venster en zonder provider-API: modellen, protocollen, polling, historie, versies.
        .target(name: "PullwatchCore", resources: [.process("Localizable.xcstrings")]),
        .target(name: "PullwatchGitHub", dependencies: ["PullwatchCore"], resources: [.process("Localizable.xcstrings")]),
        .target(name: "PullwatchAzureDevOps", dependencies: ["PullwatchCore"]),
        .target(name: "PullwatchGitLab", dependencies: ["PullwatchCore"]),
        // Kiest per account de provider; het enige dat alle providers kent.
        .target(name: "PullwatchProviders", dependencies: ["PullwatchCore", "PullwatchGitHub", "PullwatchAzureDevOps", "PullwatchGitLab"]),

        // Mocks en fixtures die de testtargets delen; geen product, dus nooit in de app.
        .target(name: "PullwatchTestSupport", dependencies: ["PullwatchCore"], path: "Tests/PullwatchTestSupport"),
        // Echte OSV-records (api.osv.dev) van elke database, voor de bronnen van een kwetsbaarheid.
        .testTarget(name: "PullwatchCoreTests", dependencies: ["PullwatchCore", "PullwatchTestSupport"], resources: [.copy("Fixtures")]),
        .testTarget(name: "PullwatchGitHubTests", dependencies: ["PullwatchGitHub", "PullwatchTestSupport"]),
        .testTarget(name: "PullwatchAzureDevOpsTests", dependencies: ["PullwatchAzureDevOps", "PullwatchTestSupport"]),
        .testTarget(name: "PullwatchGitLabTests", dependencies: ["PullwatchGitLab", "PullwatchTestSupport"]),
        .testTarget(
            name: "PullwatchProvidersTests",
            dependencies: ["PullwatchProviders", "PullwatchGitHub", "PullwatchAzureDevOps", "PullwatchGitLab", "PullwatchTestSupport"]
        ),
    ]
)

// Swift 6-taalmodus met de upcoming features die de app ook aan heeft: `any` voor elk
// existential, imports zichtbaar per bestand, async functies erven de actor van de aanroeper
// (nonisolated(nonsending)), en conformances op een actor afgeleid. PullwatchKit blijft
// standaard nonisolated; alleen het app-target is standaard @MainActor.
let upcomingFeatures: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]
for target in package.targets {
    target.swiftSettings = (target.swiftSettings ?? []) + upcomingFeatures
}
