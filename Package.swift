// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RetailBrainSDK",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "RetailBrainSDK",
            targets: ["RetailBrainSDK"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/MappedIn/ios.git",
            exact: "6.4.0"
        )
    ],
    targets: [
        .target(
            name: "RetailBrainSDK",
            dependencies: [
                .product(
                    name: "Mappedin",
                    package: "ios"
                ),
                "VusionSDK"
            ],
            path: "Sources/RetailBrainSDK"
        ),

        .binaryTarget(
            name: "VusionSDK",
            path: "Frameworks/VusionSDK.xcframework"
        ),

        .testTarget(
            name: "RetailBrainSDKTests",
            dependencies: [
                "RetailBrainSDK"
            ],
            path: "Tests/RetailBrainSDKTests"
        )
    ],
    swiftLanguageModes: [
        .v5
    ]
)
