// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PullwatchCore",
    defaultLocalization: "nl",
    platforms: [.macOS("26.6")],
    products: [
        .library(name: "PullwatchCore", targets: ["PullwatchCore"]),
    ],
    targets: [
        .target(name: "PullwatchCore", resources: [.process("Localizable.xcstrings")]),
        .testTarget(name: "PullwatchCoreTests", dependencies: ["PullwatchCore"]),
    ]
)
