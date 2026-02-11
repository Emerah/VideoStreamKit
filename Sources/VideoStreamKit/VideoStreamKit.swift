// Package: VideoStreamKit
// File: VideoStreamKit.swift
// Path: Sources/VideoStreamKit/VideoStreamKit.swift
// Date: 2026-02-06
// Author: Ahmed Emerah
// Email: ahmed.emerah@icloud.com
// Github: https://github.com/Emerah
//
import Foundation

public typealias VideoStreamProvider = VideoStreamKit.Provider.VideoStreamProvider
public typealias VideoSourceDiscovery = VideoStreamKit.Discovery.VideoSourceDiscovery

/// Namespace for the VideoStreamKit public API.
public enum VideoStreamKit {
    /// Namespace for source discovery APIs.
    public enum Discovery {}

    /// Namespace for video streaming provider APIs.
    public enum Provider {}
}
