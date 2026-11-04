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
        .library(name: "PullwatchMCP", targets: ["PullwatchMCP"]),
    ],
    dependencies: [
        // De officiële MCP Swift SDK, op een exacte release: JSON-RPC, de levenscyclus en de
        // transports komen daarvandaan, Pullwatch schrijft geen eigen protocollaag.
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1"),
        // Het `Logger`-type dat het `Transport`-protocol van de SDK vraagt; dezelfde versie als de SDK
        // zelf gebruikt (Package.resolved legt hem vast).
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
    ],
    targets: [
        // Alles zonder venster en zonder provider-API: modellen, protocollen, polling, historie, versies.
        .target(name: "PullwatchCore", resources: [.process("Localizable.xcstrings")]),
        .target(name: "PullwatchGitHub", dependencies: ["PullwatchCore"], resources: [.process("Localizable.xcstrings")]),
        .target(name: "PullwatchAzureDevOps", dependencies: ["PullwatchCore"]),
        .target(name: "PullwatchGitLab", dependencies: ["PullwatchCore"]),
        // Kiest per account de provider; het enige dat alle providers kent.
        .target(name: "PullwatchProviders", dependencies: ["PullwatchCore", "PullwatchGitHub", "PullwatchAzureDevOps", "PullwatchGitLab"]),
        // De MCP-server voor agents: het toolregister en de begrenzing bovenop de SDK.
        .target(
            name: "PullwatchMCP",
            dependencies: ["PullwatchCore", .product(name: "MCP", package: "swift-sdk"), .product(name: "Logging", package: "swift-log")]
        ),

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
        .testTarget(name: "PullwatchMCPTests", dependencies: ["PullwatchMCP", "PullwatchCore", .product(name: "MCP", package: "swift-sdk")]),
    ]
)

// Swift 6-taalmodus met de upcoming features die de app ook aan heeft: `any` voor elk
// existential, imports zichtbaar per bestand, async functies erven de actor van de aanroeper
// (nonisolated(nonsending)), conformances op een actor afgeleid, een gewone `import` is internal
// (`public import` alleen waar publieke API een type uit die module gebruikt) en `[weak x]`
// captures zijn onveranderlijk. Dat zijn alle standaarden van Swift 7. PullwatchKit blijft
// standaard nonisolated; alleen het app-target is standaard @MainActor.
let upcomingFeatures: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("ImmutableWeakCaptures"),
]
for target in package.targets {
    target.swiftSettings = (target.swiftSettings ?? []) + upcomingFeatures
}
