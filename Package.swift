// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Brim",
    platforms: [.macOS(.v13)],
    targets: [
        // Thin C layer over the private macOS frameworks (loaded at runtime with dlopen).
        .target(name: "CBrimPrivate", path: "Sources/CBrimPrivate"),
        // Pure gesture logic, unit tested.
        .target(name: "BrimCore", path: "Sources/BrimCore"),
        .executableTarget(
            name: "Brim",
            dependencies: ["CBrimPrivate", "BrimCore"],
            path: "Sources/Brim",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(name: "BrimCoreTests", dependencies: ["BrimCore"], path: "Tests/BrimCoreTests"),
    ]
)
