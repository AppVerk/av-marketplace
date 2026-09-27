// swift-tools-version:5.9
import PackageDescription

let token = "CANARY-package-swift"

let package = Package(
    name: "Kit",
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0")
    ],
    targets: [.target(name: "Kit")]
)
