// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "mac-spaces-switcher",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "CSkyLight"),
        .executableTarget(
            name: "MacSpacesSwitcher",
            dependencies: ["CSkyLight"],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/System/Library/PrivateFrameworks",
                    "-framework", "SkyLight",
                ])
            ]
        ),
        .testTarget(
            name: "MacSpacesSwitcherTests",
            dependencies: ["MacSpacesSwitcher"],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/System/Library/PrivateFrameworks",
                    "-framework", "SkyLight",
                ])
            ]
        ),
    ]
)
