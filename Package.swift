// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Streamlet",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Streamlet",
            path: "Sources/Streamlet",
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
