// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Slidebar",
    platforms: [.macOS(.v13)],
    targets: [
        // Thin C layer over the private macOS frameworks (loaded at runtime with dlopen).
        .target(name: "CSlidebarPrivate", path: "Sources/CSlidebarPrivate"),
        // Pure gesture logic, unit tested.
        .target(name: "SlidebarCore", path: "Sources/SlidebarCore"),
        .executableTarget(
            name: "Slidebar",
            dependencies: ["CSlidebarPrivate", "SlidebarCore"],
            path: "Sources/Slidebar",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(name: "SlidebarCoreTests", dependencies: ["SlidebarCore"], path: "Tests/SlidebarCoreTests"),
    ]
)
