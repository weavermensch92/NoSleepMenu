// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "NoSleepMenu",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "NoSleepMenu", targets: ["NoSleepMenu"])],
    targets: [
        .executableTarget(name: "NoSleepMenu", dependencies: ["NoSleepMenuSupport"], linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreAudio")]),
        .target(name: "NoSleepMenuSupport", publicHeadersPath: "include"),
        .testTarget(name: "NoSleepMenuTests", dependencies: ["NoSleepMenu"])
    ]
)
