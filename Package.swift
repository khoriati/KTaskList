// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KTaskList",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "KTaskList",
            path: "Sources/KTaskList",
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        ),
        .testTarget(
            name: "KTaskListTests",
            dependencies: ["KTaskList"],
            path: "Tests/KTaskListTests"
        ),
    ]
)
