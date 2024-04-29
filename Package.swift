// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RealTimeMassengerAPI",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.89.0"),
        .package(url: "https://github.com/YusukeHosonuma/SwiftPrettyPrint.git", .upToNextMajor(from: "1.4.0")),
        .package(url: "https://github.com/dankinsoid/VaporToOpenAPI.git", from: "4.4.6")
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "SwiftPrettyPrint", package: "SwiftPrettyPrint"),
                .product(name: "VaporToOpenAPI", package: "VaporToOpenAPI")
            ]
        )
    ]
)
