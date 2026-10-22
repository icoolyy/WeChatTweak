// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "WeChatTweak",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "wechattweak",
            targets: [
                "WeChatTweak"
            ]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.6.0")
    ],
    targets: [
        .target(name: "WeChatTweakCore"),
        .executableTarget(name: "core-tests", dependencies: ["WeChatTweakCore"], path: "Tests/WeChatTweakCoreTests"),
        .executableTarget(
            name: "WeChatTweak",
            dependencies: [
                "WeChatTweakCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
