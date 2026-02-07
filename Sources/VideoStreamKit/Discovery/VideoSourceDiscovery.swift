// Package: VideoStreamKit
// File: VideoSourceDiscovery.swift
// Path: Sources/VideoStreamKit/Discovery/VideoSourceDiscovery.swift
// Date: 2026-02-06
// Author: Ahmed Emerah
// Email: ahmed.emerah@icloud.com
// Github: https://github.com/Emerah
//
import Foundation
import CoreGraphics
import ScreenCaptureKit

// MARK: - Discovery API
extension VideoStreamKit.Discovery {
    /// Utilities for discovering shareable displays, windows, and applications.
    public enum SourceDiscovery {
        /// Options used when querying shareable windows and applications.
        public struct WindowOptions: Sendable {
            public let excludeDesktopWindows: Bool
            public let onScreenOnly: Bool
            public let currentProcessOnly: Bool

            public init(
                excludeDesktopWindows: Bool = true,
                onScreenOnly: Bool = true,
                currentProcessOnly: Bool = false
            ) {
                self.excludeDesktopWindows = excludeDesktopWindows
                self.onScreenOnly = onScreenOnly
                self.currentProcessOnly = currentProcessOnly
            }
        }

        /// Aggregate result for all currently available sources.
        public struct AvailableSources: Sendable {
            public let displays: [Display]
            public let windows: [Window]
            public let applications: [Application]

            public init(displays: [Display], windows: [Window], applications: [Application]) {
                self.displays = displays
                self.windows = windows
                self.applications = applications
            }

            public func windows(bundleIdentifier: String) -> [Window] {
                windows.filter { $0.matches(bundleIdentifier: bundleIdentifier) }
            }

            public func windows(processID: pid_t) -> [Window] {
                windows.filter { $0.matches(processID: processID) }
            }

            public func windows(title: String) -> [Window] {
                windows.filter { $0.matches(title: title) }
            }

            public func windows(isOnScreen: Bool) -> [Window] {
                windows.filter { $0.isOnScreen == isOnScreen }
            }

            public func windows(isActive: Bool) -> [Window] {
                windows.filter { $0.isActive == isActive }
            }

            public func windows(minLayer: Int) -> [Window] {
                windows.filter { $0.layer >= minLayer }
            }

            public func windows(maxLayer: Int) -> [Window] {
                windows.filter { $0.layer <= maxLayer }
            }
        }

        /// Display metadata discoverable from ScreenCaptureKit.
        public struct Display: Sendable {
            public let id: CGDirectDisplayID
            public let width: Int
            public let height: Int
            public let frame: CGRect

            public init(id: CGDirectDisplayID, width: Int, height: Int, frame: CGRect) {
                self.id = id
                self.width = width
                self.height = height
                self.frame = frame
            }

            public func asSource(crop: CGRect? = nil) -> VideoStreamKit.Provider.VideoStreamProvider.Source {
                .display(id: id, crop: crop)
            }
        }

        /// Window metadata discoverable from ScreenCaptureKit.
        public struct Window: Sendable {
            public let id: CGWindowID
            public let frame: CGRect
            public let title: String?
            public let layer: Int
            public let isOnScreen: Bool
            public let isActive: Bool
            public let owningApplication: Application?

            public init(
                id: CGWindowID,
                frame: CGRect,
                title: String?,
                layer: Int,
                isOnScreen: Bool,
                isActive: Bool,
                owningApplication: Application?
            ) {
                self.id = id
                self.frame = frame
                self.title = title
                self.layer = layer
                self.isOnScreen = isOnScreen
                self.isActive = isActive
                self.owningApplication = owningApplication
            }

            public func asSource(crop: CGRect? = nil) -> VideoStreamKit.Provider.VideoStreamProvider.Source {
                .window(id: id, crop: crop)
            }

            public func matches(bundleIdentifier: String) -> Bool {
                owningApplication?.bundleIdentifier == bundleIdentifier
            }

            public func matches(processID: pid_t) -> Bool {
                owningApplication?.processID == processID
            }

            public func matches(title: String) -> Bool {
                guard let currentTitle = self.title else {
                    return false
                }

                return currentTitle.localizedCaseInsensitiveContains(title)
            }
        }

        /// Application metadata discoverable from ScreenCaptureKit.
        public struct Application: Sendable {
            public let bundleIdentifier: String?
            public let applicationName: String
            public let processID: pid_t

            public init(bundleIdentifier: String?, applicationName: String, processID: pid_t) {
                self.bundleIdentifier = bundleIdentifier
                self.applicationName = applicationName
                self.processID = processID
            }
        }

        public static func displays() async throws -> [Display] {
            let content = try await content(options: .init())
            return content.displays.map(Self.mapDisplay)
        }

        public static func windows(options: WindowOptions) async throws -> [Window] {
            let content = try await content(options: options)
            return content.windows.map(Self.mapWindow)
        }

        public static func applications(options: WindowOptions) async throws -> [Application] {
            let content = try await content(options: options)
            return content.applications.map(Self.mapApplication)
        }

        public static func availableSources(options: WindowOptions = .init()) async throws -> AvailableSources {
            let content = try await content(options: options)
            return AvailableSources(
                displays: content.displays.map(Self.mapDisplay),
                windows: content.windows.map(Self.mapWindow),
                applications: content.applications.map(Self.mapApplication)
            )
        }
    }
}

// MARK: - Mapping
private extension VideoStreamKit.Discovery.SourceDiscovery {
    
    static func content(options: WindowOptions) async throws -> SCShareableContent {
        if options.currentProcessOnly {
            return try await SCShareableContent.currentProcess
        }

        return try await SCShareableContent.excludingDesktopWindows(
            options.excludeDesktopWindows,
            onScreenWindowsOnly: options.onScreenOnly
        )
    }

    static func mapDisplay(_ display: SCDisplay) -> Display {
        Display(
            id: display.displayID,
            width: Int(display.width),
            height: Int(display.height),
            frame: display.frame
        )
    }

    static func mapWindow(_ window: SCWindow) -> Window {
        Window(
            id: window.windowID,
            frame: window.frame,
            title: window.title,
            layer: Int(window.windowLayer),
            isOnScreen: window.isOnScreen,
            isActive: window.isActive,
            owningApplication: window.owningApplication.map(mapApplication)
        )
    }

    static func mapApplication(_ application: SCRunningApplication) -> Application {
        Application(
            bundleIdentifier: application.bundleIdentifier,
            applicationName: application.applicationName,
            processID: application.processID
        )
    }
}
