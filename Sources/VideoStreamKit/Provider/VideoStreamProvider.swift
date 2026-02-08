// Package: VideoStreamKit
// File: VideoStreamProvider.swift
// Path: Sources/VideoStreamKit/Provider/VideoStreamProvider.swift
// Date: 2026-02-06
// Author: Ahmed Emerah
// Email: ahmed.emerah@icloud.com
// Github: https://github.com/Emerah
//
import Foundation
import CoreGraphics
import CoreMedia
import CoreVideo
import CoreImage
import ScreenCaptureKit

// MARK: - Provider API
extension VideoStreamKit.Provider {
    /// Actor-based screen video stream provider.
    public actor VideoStreamProvider {
        /// Capture source descriptor.
        public enum Source: Sendable {
            case display(id: CGDirectDisplayID, crop: CGRect?)
            case window(id: CGWindowID, crop: CGRect?)
        }

        /// Policy used when frame buffering reaches capacity.
        public enum DropPolicy: Sendable {
            case dropOldest
            case dropNewest
        }

        /// Authorization status for screen capture.
        public enum AuthorizationStatus: Sendable {
            case notDetermined
            case denied
            case authorized
        }

        /// Internal and externally visible stream lifecycle state.
        public enum State: Sendable {
            case idle
            case starting
            case running
            case stopping
            case failed
        }

        /// Errors produced by the stream provider.
        public enum Error: Swift.Error, Sendable {
            case notAuthorized
            case sourceNotFound
            case invalidConfiguration(String)
            case captureFailed(String)
            case cancelled
        }

        /// Streaming configuration.
        public struct Configuration: Sendable {
            public let framesPerSecond: Int
            public let bufferDepth: Int
            public let dropPolicy: DropPolicy
            public let showsCursor: Bool
            public let outputWidth: Int?
            public let outputHeight: Int?
            public let scalesToFit: Bool

            public init(
                framesPerSecond: Int = 30,
                bufferDepth: Int = 4,
                dropPolicy: DropPolicy = .dropOldest,
                showsCursor: Bool = true,
                outputWidth: Int? = nil,
                outputHeight: Int? = nil,
                scalesToFit: Bool = true
            ) {
                self.framesPerSecond = framesPerSecond
                self.bufferDepth = bufferDepth
                self.dropPolicy = dropPolicy
                self.showsCursor = showsCursor
                self.outputWidth = outputWidth
                self.outputHeight = outputHeight
                self.scalesToFit = scalesToFit
            }
        }

        /// Frame payload produced by the provider.
        public struct Frame: @unchecked Sendable {
            public let pixelBuffer: CVPixelBuffer
            public let timestamp: CMTime
            public let contentRect: CGRect
            public let sequenceNumber: UInt64

            public init(
                pixelBuffer: CVPixelBuffer,
                timestamp: CMTime,
                contentRect: CGRect,
                sequenceNumber: UInt64
            ) {
                self.pixelBuffer = pixelBuffer
                self.timestamp = timestamp
                self.contentRect = contentRect
                self.sequenceNumber = sequenceNumber
            }
        }

        /// Current stream lifecycle state.
        public private(set) var streamState: State

        private let source: Source
        private let configuration: Configuration
        private let frameSink: VideoFrameSink

        private var stream: SCStream?
        private var outputAdapter: StreamOutputAdapter?
        private var isTerminated = false

        /// Asynchronous frame stream for the configured source.
        public nonisolated var frames: AsyncThrowingStream<Frame, Swift.Error> {
            frameSink.stream
        }

        /// Creates a provider for a single source and configuration.
        public init(source: Source, configuration: Configuration = .init()) {
            self.source = source
            self.configuration = configuration
            self.streamState = .idle
            self.frameSink = VideoFrameSink(bufferDepth: max(1, configuration.bufferDepth), dropPolicy: configuration.dropPolicy)
        }

        /// Starts capture.
        public func start() async throws {
            guard streamState == .idle else {
                throw Error.invalidConfiguration("start() is only valid from idle state.")
            }

            guard !isTerminated else {
                throw Error.invalidConfiguration("This provider cannot be restarted after stop/failure.")
            }

            guard configuration.framesPerSecond > 0 else {
                throw Error.invalidConfiguration("framesPerSecond must be greater than zero.")
            }

            guard configuration.bufferDepth > 0 else {
                throw Error.invalidConfiguration("bufferDepth must be greater than zero.")
            }

            guard configuration.bufferDepth <= 8 else {
                throw Error.invalidConfiguration("bufferDepth must not exceed 8.")
            }

            guard await Self.preflightAuthorization() == .authorized else {
                await transitionToFailure(.notAuthorized)
                throw Error.notAuthorized
            }

            streamState = .starting

            do {
                let resolvedSource = try await resolveSource()
                let streamConfiguration = try makeStreamConfiguration(for: resolvedSource)
                let stream = SCStream(filter: resolvedSource.filter, configuration: streamConfiguration, delegate: nil)

                let outputAdapter = StreamOutputAdapter(
                    defaultContentRect: resolvedSource.contentRect,
                    sink: frameSink,
                    failureHandler: { [weak self] (error: Swift.Error) in
                        guard let self else {
                            return
                        }

                        Task {
                            await self.handleCaptureFailure(message: error.localizedDescription)
                        }
                    }
                )

                let outputQueue = DispatchQueue(label: "VideoStreamKit.Provider.Output", qos: .userInitiated)

                self.stream = stream
                self.outputAdapter = outputAdapter

                try stream.addStreamOutput(outputAdapter, type: .screen, sampleHandlerQueue: outputQueue)
                try await stream.startCapture()
                self.streamState = .running
            } catch {
                let providerError = mapCaptureError(error)
                await transitionToFailure(providerError)
                throw providerError
            }
        }

        /// Stops capture.
        public func stop() async {
            guard streamState == .running || streamState == .starting else {
                return
            }

            streamState = .stopping
            await releaseCaptureResources()
            frameSink.finish()
            isTerminated = true
            self.streamState = .idle
        }

        /// Checks capture authorization status without prompting.
        public static func preflightAuthorization() async -> AuthorizationStatus {
            if CGPreflightScreenCaptureAccess() {
                return .authorized
            }

            return .notDetermined
        }

        /// Requests capture authorization from the system.
        public static func requestAuthorization() async -> AuthorizationStatus {
            if CGPreflightScreenCaptureAccess() {
                return .authorized
            }

            if CGRequestScreenCaptureAccess() {
                return .authorized
            }

            return .denied
        }

        /// Returns the best-available authorization status without prompting.
        public static func authorizationStatus() async -> AuthorizationStatus {
            await preflightAuthorization()
        }
    }
}

// MARK: - Error Details
extension VideoStreamKit.Provider.VideoStreamProvider.Error {
    public var userMessage: String {
        switch self {
        case .notAuthorized:
            return "Screen recording permission is required."
        case .sourceNotFound:
            return "The selected capture source is no longer available."
        case .invalidConfiguration(let details):
            return "Invalid stream configuration: \(details)"
        case .captureFailed(let details):
            return "Video capture failed: \(details)"
        case .cancelled:
            return "Video capture was cancelled."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .notAuthorized:
            return "Enable Screen Recording permission in System Settings and retry."
        case .sourceNotFound:
            return "Refresh available sources and select a valid display or window."
        case .invalidConfiguration:
            return "Adjust configuration values and retry."
        case .captureFailed:
            return "Retry capture. If the issue persists, restart the app."
        case .cancelled:
            return nil
        }
    }

    public var isAuthorizationError: Bool {
        if case .notAuthorized = self {
            return true
        }

        return false
    }
}

// MARK: - Provider Helpers
private extension VideoStreamKit.Provider.VideoStreamProvider {
    struct ResolvedSource {
        let filter: SCContentFilter
        let contentRect: CGRect
        let sourceRect: CGRect?
    }

    func handleCaptureFailure(message: String) async {
        await transitionToFailure(.captureFailed(message))
    }

    func mapCaptureError(_ error: Swift.Error) -> Error {
        if let providerError = error as? Error {
            return providerError
        }

        if error is CancellationError {
            return .cancelled
        }

        return .captureFailed(error.localizedDescription)
    }

    func makeStreamConfiguration(for resolvedSource: ResolvedSource) throws -> SCStreamConfiguration {
        let resolvedWidth = Int(resolvedSource.contentRect.width.rounded(.towardZero))
        let resolvedHeight = Int(resolvedSource.contentRect.height.rounded(.towardZero))

        guard resolvedWidth > 0, resolvedHeight > 0 else {
            throw Error.invalidConfiguration("Resolved source rect must be non-empty.")
        }

        if (configuration.outputWidth == nil) != (configuration.outputHeight == nil) {
            throw Error.invalidConfiguration("outputWidth and outputHeight must both be set or both be nil.")
        }

        let outputWidth = configuration.outputWidth ?? resolvedWidth
        let outputHeight = configuration.outputHeight ?? resolvedHeight

        guard outputWidth > 0, outputHeight > 0 else {
            throw Error.invalidConfiguration("outputWidth and outputHeight must be greater than zero.")
        }

        let streamConfiguration = SCStreamConfiguration()
        streamConfiguration.width = max(1, outputWidth)
        streamConfiguration.height = max(1, outputHeight)
        streamConfiguration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(configuration.framesPerSecond))
        streamConfiguration.queueDepth = configuration.bufferDepth
        streamConfiguration.showsCursor = configuration.showsCursor
        streamConfiguration.scalesToFit = configuration.scalesToFit
        streamConfiguration.pixelFormat = kCVPixelFormatType_32BGRA

        if let sourceRect = resolvedSource.sourceRect {
            streamConfiguration.sourceRect = sourceRect
        }

        return streamConfiguration
    }

    func resolveSource() async throws -> ResolvedSource {
        let shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        switch source {
        case .display(let id, let crop):
            guard let display = shareableContent.displays.first(where: { $0.displayID == id }) else {
                throw Error.sourceNotFound
            }

            let fullRect = display.frame
            let resolvedRect = try resolvedContentRect(fullRect: fullRect, crop: crop)
            let filter = SCContentFilter(display: display, excludingWindows: [])
            return ResolvedSource(filter: filter, contentRect: resolvedRect, sourceRect: crop == nil ? nil : resolvedRect)

        case .window(let id, let crop):
            guard let window = shareableContent.windows.first(where: { $0.windowID == id }) else {
                throw Error.sourceNotFound
            }

            let fullRect = window.frame
            let resolvedRect = try resolvedContentRect(fullRect: fullRect, crop: crop)
            let filter = SCContentFilter(desktopIndependentWindow: window)
            return ResolvedSource(filter: filter, contentRect: resolvedRect, sourceRect: crop == nil ? nil : resolvedRect)
        }
    }

    func resolvedContentRect(fullRect: CGRect, crop: CGRect?) throws -> CGRect {
        guard let crop else {
            return fullRect
        }

        let intersection = fullRect.intersection(crop)
        guard !intersection.isNull, !intersection.isEmpty else {
            throw Error.invalidConfiguration("Crop rect does not intersect with source bounds.")
        }

        return intersection
    }

    func transitionToFailure(_ error: Error) async {
        streamState = .failed
        await releaseCaptureResources()
        frameSink.finish(throwing: error)
        isTerminated = true
    }

    func releaseCaptureResources() async {
        if let stream, let outputAdapter {
            try? stream.removeStreamOutput(outputAdapter, type: .screen)
        }

        if let stream {
            try? await stream.stopCapture()
        }

        self.stream = nil
        self.outputAdapter = nil
    }
}

// MARK: - Stream Adapter
private final class StreamOutputAdapter: NSObject, SCStreamOutput {
    private let defaultContentRect: CGRect
    private let sink: VideoFrameSink
    private let failureHandler: @Sendable (Swift.Error) -> Void
    private let ciContext: CIContext

    init(
        defaultContentRect: CGRect,
        sink: VideoFrameSink,
        failureHandler: @escaping @Sendable (Swift.Error) -> Void
    ) {
        self.defaultContentRect = defaultContentRect
        self.sink = sink
        self.failureHandler = failureHandler
        self.ciContext = CIContext(options: [.cacheIntermediates: false])
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .screen else {
            return
        }

        autoreleasepool {
            do {
                guard let status = frameStatus(from: sampleBuffer) else {
                    return
                }

                guard status == .complete || status == .started else {
                    return
                }

                guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                    return
                }

                let bgraBuffer = try bgraPixelBuffer(from: imageBuffer)
                let contentRect = sampleContentRect(from: sampleBuffer) ?? defaultContentRect
                let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                let sequenceNumber = sink.nextSequenceNumber()

                let frame = VideoStreamKit.Provider.VideoStreamProvider.Frame(
                    pixelBuffer: bgraBuffer,
                    timestamp: timestamp,
                    contentRect: contentRect,
                    sequenceNumber: sequenceNumber
                )

                sink.push(frame)
            } catch {
                failureHandler(error)
            }
        }
    }
}

// MARK: - Adapter Helpers
private extension StreamOutputAdapter {
    func frameStatus(from sampleBuffer: CMSampleBuffer) -> SCFrameStatus? {
        guard
            let array = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
            let attachments = array.first,
            let rawStatus = attachments[.status] as? Int,
            let status = SCFrameStatus(rawValue: rawStatus)
        else {
            return nil
        }

        return status
    }

    func sampleContentRect(from sampleBuffer: CMSampleBuffer) -> CGRect? {
        guard
            let array = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
            let attachments = array.first,
            let rectDictionary = attachments[.contentRect] as? NSDictionary
        else {
            return nil
        }

        return CGRect(dictionaryRepresentation: rectDictionary)
    }

    func bgraPixelBuffer(from pixelBuffer: CVPixelBuffer) throws -> CVPixelBuffer {
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        if pixelFormat == kCVPixelFormatType_32BGRA {
            return pixelBuffer
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any],
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]

        var convertedBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &convertedBuffer
        )

        guard status == kCVReturnSuccess, let convertedBuffer else {
            throw VideoStreamKit.Provider.VideoStreamProvider.Error.captureFailed("Failed to allocate BGRA pixel buffer.")
        }

        ciContext.render(CIImage(cvPixelBuffer: pixelBuffer), to: convertedBuffer)
        return convertedBuffer
    }
}

// MARK: - Frame Sink
private final class VideoFrameSink: @unchecked Sendable {
    typealias Frame = VideoStreamKit.Provider.VideoStreamProvider.Frame

    let stream: AsyncThrowingStream<Frame, Swift.Error>

    private let continuation: AsyncThrowingStream<Frame, Swift.Error>.Continuation
    private let bufferDepth: Int
    private let dropPolicy: VideoStreamKit.Provider.VideoStreamProvider.DropPolicy

    private let lock = NSLock()
    private var bufferedFrames: [Frame] = []
    private var isDraining = false
    private var isFinished = false
    private var sequenceNumber: UInt64 = 0

    init(
        bufferDepth: Int,
        dropPolicy: VideoStreamKit.Provider.VideoStreamProvider.DropPolicy
    ) {
        self.bufferDepth = max(1, bufferDepth)
        self.dropPolicy = dropPolicy

        var continuation: AsyncThrowingStream<Frame, Swift.Error>.Continuation?
        self.stream = AsyncThrowingStream { streamContinuation in
            continuation = streamContinuation
        }

        guard let continuation else {
            preconditionFailure("Failed to create stream continuation.")
        }

        self.continuation = continuation
    }

    func nextSequenceNumber() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }

        let current = sequenceNumber
        sequenceNumber &+= 1
        return current
    }

    func push(_ frame: Frame) {
        var initialBatch: [Frame] = []

        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }

        if bufferedFrames.count >= bufferDepth {
            switch dropPolicy {
            case .dropOldest:
                bufferedFrames.removeFirst()
                bufferedFrames.append(frame)
            case .dropNewest:
                lock.unlock()
                return
            }
        } else {
            bufferedFrames.append(frame)
        }

        if !isDraining {
            isDraining = true
            initialBatch = bufferedFrames
            bufferedFrames.removeAll(keepingCapacity: true)
        }
        lock.unlock()

        guard !initialBatch.isEmpty else {
            return
        }

        drain(initialBatch)
    }

    func finish(throwing error: Swift.Error? = nil) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }

        isFinished = true
        bufferedFrames.removeAll(keepingCapacity: false)
        lock.unlock()

        if let error {
            continuation.finish(throwing: error)
        } else {
            continuation.finish()
        }
    }

    private func drain(_ firstBatch: [Frame]) {
        var batch = firstBatch

        while true {
            for frame in batch {
                continuation.yield(frame)
            }

            lock.lock()
            if bufferedFrames.isEmpty {
                isDraining = false
                lock.unlock()
                return
            }

            batch = bufferedFrames
            bufferedFrames.removeAll(keepingCapacity: true)
            lock.unlock()
        }
    }
}
