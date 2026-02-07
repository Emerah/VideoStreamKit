# VideoStreamKit

VideoStreamKit is a focused macOS package for screen capture using `ScreenCaptureKit`.

It provides two core capabilities:
- source discovery (displays, windows, applications)
- frame streaming as `CVPixelBuffer` with timestamp and metadata using Swift concurrency

The public API is organized under:
- `VideoStreamKit.Discovery`
- `VideoStreamKit.Provider`

## Purpose

Use this package when you need a small, modern API for screen capture without directly managing low-level ScreenCaptureKit stream plumbing.

Typical use cases:
- screen/video analysis pipelines
- custom recording/transcoding workflows
- computer vision processing of desktop/window content

## Package Types

### `VideoStreamKit.Discovery.SourceDiscovery`
Discovers currently shareable macOS capture sources.

Main functions:
- `displays() async throws -> [Display]`
- `windows(options:) async throws -> [Window]`
- `applications(options:) async throws -> [Application]`
- `availableSources(options:) async throws -> AvailableSources`

### `WindowOptions`
Controls discovery behavior:
- `excludeDesktopWindows`
- `onScreenOnly`
- `currentProcessOnly`

### `AvailableSources`
Aggregate of discovered sources:
- `displays`
- `windows`
- `applications`

Includes window filtering helpers:
- `windows(bundleIdentifier:)`
- `windows(processID:)`
- `windows(title:)`
- `windows(isOnScreen:)`
- `windows(isActive:)`
- `windows(minLayer:)`
- `windows(maxLayer:)`

### `Display`
Represents one shareable display.

Fields:
- `id`, `width`, `height`, `frame`

Conversion:
- `asSource(crop:) -> VideoStreamProvider.Source`

### `Window`
Represents one shareable window.

Fields:
- `id`, `frame`, `title`, `layer`, `isOnScreen`, `isActive`, `owningApplication`

Helpers:
- `matches(bundleIdentifier:)`
- `matches(processID:)`
- `matches(title:)`

Conversion:
- `asSource(crop:) -> VideoStreamProvider.Source`

### `Application`
Represents one running app from discovery.

Fields:
- `bundleIdentifier`, `applicationName`, `processID`

### `VideoStreamKit.Provider.VideoStreamProvider`
Actor-based streaming provider.

Key types:
- `Source`: `.display(id:crop:)`, `.window(id:crop:)`
- `Configuration`: `framesPerSecond`, `bufferDepth`, `dropPolicy`, `showsCursor`
- `DropPolicy`: `.dropOldest`, `.dropNewest`
- `Frame`: `pixelBuffer`, `timestamp`, `contentRect`, `sequenceNumber`
- `State`: `.idle`, `.starting`, `.running`, `.stopping`, `.failed`
- `AuthorizationStatus`: `.notDetermined`, `.denied`, `.authorized`
- `Error`: `.notAuthorized`, `.sourceNotFound`, `.invalidConfiguration`, `.captureFailed`, `.cancelled`

Key members:
- `frames: AsyncThrowingStream<Frame, Swift.Error>`
- `streamState`
- `start()`
- `stop()`
- `preflightAuthorization()`
- `requestAuthorization()`
- `authorizationStatus()`

## How Components Work Together

1. Discover sources using `SourceDiscovery`.
2. Select one source (`Display` or `Window`) and convert it via `asSource(crop:)`.
3. Build a `VideoStreamProvider` with source and optional `Configuration`.
4. Start the provider with `start()`.
5. Consume `frames` asynchronously.
6. Stop cleanly with `stop()`.

Internally, the provider:
- resolves source IDs into `SCContentFilter`
- configures and starts `SCStream`
- receives `CMSampleBuffer` callbacks
- guarantees BGRA output (`kCVPixelFormatType_32BGRA`) with conversion fallback
- pushes frames through a bounded sink applying configured drop policy

## Lifecycle Notes

- `start()` requires authorization; otherwise throws `.notAuthorized`.
- `start()` can fail with `.sourceNotFound` if selected IDs are no longer available.
- `stop()` transitions stream to idle and finishes the frame stream.
- Current implementation treats provider instances as one-shot after stop/failure. Create a new provider instance for a new session.

## Usage Examples

### 1) Discover sources

```swift
import VideoStreamKit

let sources = try await VideoStreamKit.Discovery.SourceDiscovery.availableSources()

print("Displays: \(sources.displays.count)")
print("Windows: \(sources.windows.count)")
print("Apps: \(sources.applications.count)")

let chromeWindows = sources.windows(bundleIdentifier: "com.google.Chrome")
print("Chrome windows: \(chromeWindows.count)")
```

### 2) Start capture from first display

```swift
import VideoStreamKit
import CoreMedia

let sources = try await VideoStreamKit.Discovery.SourceDiscovery.availableSources()
guard let display = sources.displays.first else {
    throw NSError(domain: "Example", code: 1, userInfo: [NSLocalizedDescriptionKey: "No display found"])
}

let provider = VideoStreamKit.Provider.VideoStreamProvider(
    source: display.asSource(),
    configuration: .init(framesPerSecond: 30, bufferDepth: 4, dropPolicy: .dropOldest, showsCursor: true)
)

try await provider.start()

for try await frame in provider.frames {
    let seconds = CMTimeGetSeconds(frame.timestamp)
    print("Frame #\(frame.sequenceNumber) t=\(seconds) rect=\(frame.contentRect)")

    // Use frame.pixelBuffer (BGRA)
}
```

### 3) Capture a specific window with crop and stop later

```swift
import VideoStreamKit
import CoreGraphics

let sources = try await VideoStreamKit.Discovery.SourceDiscovery.availableSources()
guard let window = sources.windows(title: "My Window").first else {
    throw NSError(domain: "Example", code: 2, userInfo: [NSLocalizedDescriptionKey: "Window not found"])
}

let crop = CGRect(x: 100, y: 100, width: 800, height: 600)
let provider = VideoStreamKit.Provider.VideoStreamProvider(source: window.asSource(crop: crop))

try await provider.start()

Task {
    for try await frame in provider.frames {
        // Process frame
        _ = frame.pixelBuffer
    }
}

// Later...
await provider.stop()
```

### 4) Authorization flow

```swift
import VideoStreamKit

let status = await VideoStreamKit.Provider.VideoStreamProvider.preflightAuthorization()
if status != .authorized {
    let requested = await VideoStreamKit.Provider.VideoStreamProvider.requestAuthorization()
    guard requested == .authorized else {
        // Inform user and exit capture path
        return
    }
}
```
