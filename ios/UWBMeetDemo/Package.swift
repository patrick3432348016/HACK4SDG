// swift-tools-version: 5.9
import PackageDescription

// Hardware-independent logic tests. This package is NOT the iOS app.
let package = Package(
    name: "MeetCore",
    products: [.library(name: "MeetCore", targets: ["MeetCore"])],
    targets: [
        .target(name: "MeetCore", path: "Core"),
        .testTarget(name: "MeetCoreTests", dependencies: ["MeetCore"], path: "Tests")
    ]
)

