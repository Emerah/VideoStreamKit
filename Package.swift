// swift-tools-version: 6.0

// Package: VideoStreamKit
// File: Package.swift
// Path: Package.swift
// Date: 2026-02-06
// Author: Ahmed Emerah
// Email: ahmed.emerah@icloud.com
// Github: https://github.com/Emerah
//

import PackageDescription

let package = Package(
    name: "VideoStreamKit",
    platforms: [.macOS(.v15)],
    products: [.library(name: "VideoStreamKit", targets: ["VideoStreamKit"])],
    dependencies: [/*add-as-needed*/],
    targets: [
        .target(
            name: "VideoStreamKit",
            dependencies: [/*add-as-needed*/],
            path: "Sources/VideoStreamKit",
            swiftSettings: [.define("VIDEO_STREAM_KIT")],
            linkerSettings: [
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreImage"),
                .linkedFramework("CoreGraphics"),
                
            ]
        ),
        .testTarget(
            name: "VideoStreamKitTests",
            dependencies: ["VideoStreamKit"],
            path: "Tests/VideoStreamKitTests"
        )
    ]
)
