// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VolumeMixer",
    platforms: [.macOS("14.4")],
    dependencies: [
        // Updates. The binary framework is copied into the app by scripts/bundle.sh.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0")
    ],
    targets: [
        .target(
            name: "MixerCore",
            path: "Sources/MixerCore"
        ),
        .executableTarget(
            name: "VolumeMixer",
            dependencies: ["MixerCore", .product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/VolumeMixer",
            linkerSettings: [
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("ServiceManagement"),
                // The app carries Sparkle.framework in Contents/Frameworks.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        // Command Line Tools ship neither XCTest nor Swift Testing, so the checks are a plain executable.
        .executableTarget(
            name: "MixerCoreChecks",
            dependencies: ["MixerCore"],
            path: "Checks/MixerCoreChecks"
        ),
    ]
)
