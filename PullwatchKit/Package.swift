// swift-tools-version: 6.0
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
        // Kiest per account de provider; het enige dat alle providers kent.
        .target(name: "PullwatchProviders", dependencies: ["PullwatchCore", "PullwatchGitHub", "PullwatchAzureDevOps"]),

        // Mocks en fixtures die de testtargets delen; geen product, dus nooit in de app.
        .target(name: "PullwatchTestSupport", dependencies: ["PullwatchCore"], path: "Tests/PullwatchTestSupport"),
        .testTarget(name: "PullwatchCoreTests", dependencies: ["PullwatchCore", "PullwatchTestSupport"]),
        .testTarget(name: "PullwatchGitHubTests", dependencies: ["PullwatchGitHub", "PullwatchTestSupport"]),
        .testTarget(name: "PullwatchAzureDevOpsTests", dependencies: ["PullwatchAzureDevOps", "PullwatchTestSupport"]),
        .testTarget(
            name: "PullwatchProvidersTests",
            dependencies: ["PullwatchProviders", "PullwatchGitHub", "PullwatchAzureDevOps", "PullwatchTestSupport"]
        ),
    ]
)
