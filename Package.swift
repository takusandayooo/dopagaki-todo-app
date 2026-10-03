// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DopagakiCore",
    platforms: [.iOS(.v17), .macOS(.v13), .watchOS(.v10)],
    products: [
        .library(name: "DopagakiCore", targets: ["DopagakiCore"]),
        .executable(name: "DopagakiChecks", targets: ["DopagakiChecks"])
    ],
    targets: [
        .target(name: "DopagakiCore", path: "Core"),
        .testTarget(name: "DopagakiCoreTests", dependencies: ["DopagakiCore"], path: "CoreTests"),
        .target(name: "DopagakiPersistence", dependencies: ["DopagakiCore"], path: "Shared", exclude: ["ScreenTimePolicy.swift"], sources: ["Persistence.swift", "WidgetSnapshotRepository.swift", "WatchProgressRepository.swift"]),
        .testTarget(name: "DopagakiPersistenceTests", dependencies: ["DopagakiPersistence", "DopagakiCore"], path: "PersistenceTests"),
        .executableTarget(name: "DopagakiChecks", dependencies: ["DopagakiCore", "DopagakiPersistence"], path: "Verification")
    ]
)
