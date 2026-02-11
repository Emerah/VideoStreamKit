// Package: VideoStreamKit
// File: VideoStreamKitTests.swift
// Path: Tests/VideoStreamKitTests/VideoStreamKitTests.swift
// Date: 2026-02-06
// Author: Ahmed Emerah
// Email:  ahmed.emerah@icloud.com
// Github: https://github.com/Emerah
//
import XCTest
import CoreGraphics
@testable import VideoStreamKit

final class VideoStreamKitTests: XCTestCase {
    func testWindowOptionsDefaults() {
        let options = VideoStreamKit.Discovery.VideoSourceDiscovery.WindowOptions()

        XCTAssertTrue(options.excludeDesktopWindows)
        XCTAssertTrue(options.onScreenOnly)
        XCTAssertFalse(options.currentProcessOnly)
    }

    func testAvailableSourcesWindowFilters() {
        let app1 = VideoStreamKit.Discovery.VideoSourceDiscovery.Application(
            bundleIdentifier: "com.example.app1",
            applicationName: "App One",
            processID: 123
        )

        let app2 = VideoStreamKit.Discovery.VideoSourceDiscovery.Application(
            bundleIdentifier: "com.example.app2",
            applicationName: "App Two",
            processID: 456
        )

        let window1 = VideoStreamKit.Discovery.VideoSourceDiscovery.Window(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            title: "Main Window",
            layer: 5,
            isOnScreen: true,
            isActive: true,
            owningApplication: app1
        )

        let window2 = VideoStreamKit.Discovery.VideoSourceDiscovery.Window(
            id: 2,
            frame: CGRect(x: 10, y: 10, width: 120, height: 120),
            title: "Settings",
            layer: 2,
            isOnScreen: false,
            isActive: false,
            owningApplication: app2
        )

        let sources = VideoStreamKit.Discovery.VideoSourceDiscovery.AvailableSources(
            displays: [],
            windows: [window1, window2],
            applications: [app1, app2]
        )

        XCTAssertEqual(sources.windows(bundleIdentifier: "com.example.app1").map(\.id), [1])
        XCTAssertEqual(sources.windows(processID: 456).map(\.id), [2])
        XCTAssertEqual(sources.windows(title: "main").map(\.id), [1])
        XCTAssertEqual(sources.windows(isOnScreen: true).map(\.id), [1])
        XCTAssertEqual(sources.windows(isActive: false).map(\.id), [2])
        XCTAssertEqual(sources.windows(minLayer: 3).map(\.id), [1])
        XCTAssertEqual(sources.windows(maxLayer: 3).map(\.id), [2])
    }

    func testProviderErrorProperties() {
        let auth = VideoStreamKit.Provider.VideoStreamProvider.StreamProviderError.notAuthorized
        XCTAssertTrue(auth.isAuthorizationError)
        XCTAssertNotNil(auth.recoverySuggestion)
        XCTAssertFalse(auth.userMessage.isEmpty)

        let capture = VideoStreamKit.Provider.VideoStreamProvider.StreamProviderError.captureFailed("sample")
        XCTAssertFalse(capture.isAuthorizationError)
        XCTAssertNotNil(capture.recoverySuggestion)
        XCTAssertTrue(capture.userMessage.contains("sample"))
    }

    func testProviderConfigurationDefaults() {
        let config = VideoStreamKit.Provider.VideoStreamProvider.Configuration()

        XCTAssertEqual(config.framesPerSecond, 30)
        XCTAssertEqual(config.bufferDepth, 4)
        if case .dropOldest = config.dropPolicy {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected default drop policy to be dropOldest")
        }
        XCTAssertTrue(config.showsCursor)
    }
}
