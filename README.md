# VideoStreamKit

VideoStreamKit is a focused macOS package for screen capture on top of `ScreenCaptureKit`.

It provides:
- source discovery (`Display`, `Window`, `Application`)
- frame streaming as `CVPixelBuffer` with timestamps and metadata

The public API is organized under:
- `VideoStreamKit.Discovery`
- `VideoStreamKit.Provider`

## Requirements

- macOS 15.0+
- Swift 6+
- Screen Recording permission at runtime

## Installation

Add the package to your `Package.swift` dependencies:

```swift
.package(url: "https://github.com/Emerah/VideoStreamKit.git", from: "1.0.0")
```

Then add `VideoStreamKit` to your target dependencies.

## Tutorial: First Capture

This section is for first-time users. It walks through the complete happy path.

### Step 1: Import and check authorization

```swift
import VideoStreamKit

let status = await VideoStreamProvider.preflightAuthorization()
if status != .authorized {
    let requested = await VideoStreamProvider.requestAuthorization()
    guard requested == .authorized else {
        throw VideoStreamProvider.StreamProviderError.notAuthorized
    }
}
```

Notes:
- `preflightAuthorization()` does not prompt the user.
- `requestAuthorization()` can prompt and may return `.denied`.

### Step 2: Discover available sources

```swift
let sources = try await VideoSourceDiscovery.availableSources()
print("Displays: \(sources.displays.count)")
print("Windows: \(sources.windows.count)")
print("Applications: \(sources.applications.count)")
```

Pick a source:

```swift
guard let display = sources.displays.first else {
    throw VideoStreamProvider.StreamProviderError.sourceNotFound
}
```

### Step 3: Create provider configuration

```swift
let config = VideoStreamProvider.Configuration(
    framesPerSecond: 30,
    bufferDepth: 4,
    dropPolicy: .dropOldest,
    showsCursor: true,
    outputWidth: nil,
    outputHeight: nil,
    scalesToFit: true
)
```

Tips:
- Keep `bufferDepth` small for lower latency.
- Use `dropOldest` for near-real-time consumers.
- Use `dropNewest` to preserve temporal continuity in queued frames.

### Step 4: Start stream and consume frames

```swift
import CoreMedia

let provider = VideoStreamProvider(source: display.asSource(), configuration: config)
try await provider.start()

for try await frame in provider.frames {
    let t = CMTimeGetSeconds(frame.timestamp)
    print("frame=\(frame.sequenceNumber) t=\(t) rect=\(frame.contentRect)")

    // frame.pixelBuffer is BGRA (kCVPixelFormatType_32BGRA)
    // Process frame here...
}
```

### Step 5: Stop cleanly

```swift
await provider.stop()
```

Important:
- Provider instances are one-shot in the current implementation.
- After `stop()` or failure, create a new `VideoStreamProvider` for the next session.

## Tutorial: Capture a Specific Window

```swift
import CoreGraphics
import VideoStreamKit

let sources = try await VideoSourceDiscovery.availableSources()
guard let window = sources.windows(title: "My Window").first else {
    throw VideoStreamProvider.StreamProviderError.sourceNotFound
}

let crop = CGRect(x: 100, y: 100, width: 800, height: 600)
let provider = VideoStreamProvider(source: window.asSource(crop: crop))
try await provider.start()

Task {
    for try await frame in provider.frames {
        _ = frame.pixelBuffer
    }
}
```

## Package Types (Reference)

### `VideoStreamKit.Discovery.VideoSourceDiscovery`
Discovery entry point.

Main APIs:
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
Aggregated discovery result:
- `displays`
- `windows`
- `applications`

Filter helpers:
- `windows(bundleIdentifier:)`
- `windows(processID:)`
- `windows(title:)`
- `windows(isOnScreen:)`
- `windows(isActive:)`
- `windows(minLayer:)`
- `windows(maxLayer:)`

### `Display`
Fields:
- `id`
- `width`
- `height`
- `frame`

Conversion:
- `asSource(crop:) -> VideoStreamProvider.Source`

### `Window`
Fields:
- `id`
- `frame`
- `title`
- `layer`
- `isOnScreen`
- `isActive`
- `owningApplication`

Helpers:
- `matches(bundleIdentifier:)`
- `matches(processID:)`
- `matches(title:)`

Conversion:
- `asSource(crop:) -> VideoStreamProvider.Source`

### `Application`
Fields:
- `bundleIdentifier`
- `applicationName`
- `processID`

### `VideoStreamKit.Provider.VideoStreamProvider`
Actor-based streaming provider.

Main types:
- `Source`: `.display(id:crop:)`, `.window(id:crop:)`
- `Configuration`
- `DropPolicy`: `.dropOldest`, `.dropNewest`
- `Frame`: `pixelBuffer`, `timestamp`, `contentRect`, `sequenceNumber`
- `State`: `.idle`, `.starting`, `.running`, `.stopping`, `.failed`
- `AuthorizationStatus`: `.notDetermined`, `.denied`, `.authorized`
- `StreamProviderError`: `.notAuthorized`, `.sourceNotFound`, `.invalidConfiguration`, `.captureFailed`, `.cancelled`

Main members:
- `frames: AsyncThrowingStream<Frame, Error>`
- `streamState`
- `start()`
- `stop()`
- `preflightAuthorization()`
- `requestAuthorization()`
- `authorizationStatus()`

## Error Handling

Common failures and what to do:
- `.notAuthorized`: ask user to enable Screen Recording permission.
- `.sourceNotFound`: refresh sources and pick another target.
- `.invalidConfiguration`: verify FPS, buffer depth, and output size.
- `.captureFailed`: retry; if persistent, recreate provider and retry.

## Troubleshooting

- No sources found:
  Ensure the app has Screen Recording permission and retry discovery.
- `start()` fails after a source was selected:
  The source may have disappeared. Run discovery again.
- High memory/latency:
  Lower `bufferDepth`, reduce output size, or reduce FPS.
