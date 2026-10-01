// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PhononDictate",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PhononDictate",
            path: "Sources/PhononDictate",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
