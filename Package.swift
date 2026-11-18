// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VolumeMixer",
    platforms: [.macOS("14.4")],
    targets: [
        .target(
            name: "MixerCore",
            path: "Sources/MixerCore"
        ),
        .executableTarget(
            name: "VolumeMixer",
            dependencies: ["MixerCore"],
            path: "Sources/VolumeMixer",
            linkerSettings: [
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("ServiceManagement"),
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
