// swift-tools-version: 6.2
// Runs the app's model tests (matching, parity with the web version, the store) natively on the Mac, with no
// simulator: `swift test --package-path ios`. The app itself builds from DailyGames.xcodeproj.
import PackageDescription

let package = Package(
    name: "DailyGamesModel",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "DailyGames",
            path: "DailyGames/Model",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "DailyGamesTests",
            dependencies: ["DailyGames"],
            path: "DailyGamesTests",
            // The capture and touch tests need UIKit; they run in Xcode. ParityTests finds the fixtures by path here.
            exclude: ["CaptureTests.swift", "TouchTests.swift", "Fixtures"]
        ),
    ]
)
