import AppKit
import AVFoundation
import CoreMedia
import ScreenCaptureKit

enum RecordingError: LocalizedError {
    case noDisplay

    var errorDescription: String? {
        switch self {
        case .noDisplay:
            return "No display is available to record."
        }
    }
}

/// Captures an entire display plus system audio via a single ScreenCaptureKit
/// stream, and feeds the samples into a MovieWriter.
final class Recorder: NSObject, SCStreamOutput {
    private var stream: SCStream?
    private let writer = MovieWriter()
    private let sampleQueue = DispatchQueue(label: "com.david.screenrec.samples")
    private var firstPTS: CMTime?
    private var outputURL: URL?
    private var stopping = false

    var isRecording: Bool { stream != nil }

    func start(display: SCDisplay, outputURL: URL) async throws {
        guard stream == nil else { return }
        stopping = false
        firstPTS = nil
        self.outputURL = outputURL

        let (pixelWidth, pixelHeight) = Self.pixels(for: display)
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = pixelWidth
        config.height = pixelHeight
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.queueDepth = 3
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        try writer.begin(outputURL: outputURL, pixelWidth: pixelWidth, pixelHeight: pixelHeight)
        try await stream.startCapture()
        self.stream = stream
    }

    /// Stops capture, finalizes the file, and returns its URL.
    func stop() async throws -> URL? {
        guard let stream else { return nil }
        stopping = true
        self.stream = nil
        try await stream.stopCapture()
        try await writer.finish()
        return outputURL
    }

    /// Pixel dimensions of the display, honoring Retina scale factor.
    private static func pixels(for display: SCDisplay) -> (Int, Int) {
        let scale = NSScreen.screens
            .first(where: { screen in
                guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                    return false
                }
                return id.int32Value == display.displayID
            })?
            .backingScaleFactor ?? 2
        return (Int(CGFloat(display.width) * scale), Int(CGFloat(display.height) * scale))
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid, !stopping else { return }
        switch type {
        case .screen:
            if let buffer = retime(sampleBuffer) {
                writer.appendVideo(buffer)
            }
        case .audio:
            if let buffer = retime(sampleBuffer) {
                writer.appendAudio(buffer)
            }
        case .microphone:
            break // not captured in v1
        @unknown default:
            break
        }
    }

    /// Retimes every sample relative to the first one received, so the movie
    /// starts at 0:00 and audio/video share the same timeline.
    private func retime(_ raw: CMSampleBuffer) -> CMSampleBuffer? {
        let pts = raw.presentationTimeStamp
        if firstPTS == nil { firstPTS = pts }
        let offset = firstPTS!

        var timing = CMSampleTimingInfo(
            duration: raw.duration,
            presentationTimeStamp: pts - offset,
            decodeTimeStamp: .invalid
        )
        if raw.decodeTimeStamp.isValid {
            timing.decodeTimeStamp = raw.decodeTimeStamp - offset
        }
        return try? CMSampleBuffer(copying: raw, withNewTiming: [timing])
    }
}
