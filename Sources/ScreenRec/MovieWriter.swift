import AVFoundation
import CoreMedia

/// Writes the captured screen video (H.264) and system audio (AAC) into an MP4.
///
/// The writer is created up front with the expected pixel size (derived from the
/// display's scale factor) and a fixed 48 kHz stereo AAC audio track, which is
/// what ScreenCaptureKit is configured to deliver.
final class MovieWriter {
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?

    func begin(outputURL: URL, pixelWidth: Int, pixelHeight: Int) throws {
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        let bitrate = min(max(pixelWidth * pixelHeight * 5, 8_000_000), 50_000_000)
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: pixelWidth,
            AVVideoHeightKey: pixelHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: 60
            ]
        ])
        video.expectsMediaDataInRealTime = true
        writer.add(video)

        let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 192_000
        ])
        audio.expectsMediaDataInRealTime = true
        writer.add(audio)

        writer.startWriting()
        // All incoming samples are retimed to start at zero, so the session starts at 0.
        writer.startSession(atSourceTime: .zero)

        assetWriter = writer
        videoInput = video
        audioInput = audio
    }

    func appendVideo(_ buffer: CMSampleBuffer) {
        guard let writer = assetWriter,
              let input = videoInput,
              writer.status == .writing,
              input.isReadyForMoreMediaData else { return }
        input.append(buffer)
    }

    func appendAudio(_ buffer: CMSampleBuffer) {
        guard let writer = assetWriter,
              let input = audioInput,
              writer.status == .writing,
              input.isReadyForMoreMediaData else { return }
        input.append(buffer)
    }

    func finish() async throws {
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        guard let writer = assetWriter else { return }
        assetWriter = nil
        videoInput = nil
        audioInput = nil
        await writer.finishWriting()
    }
}
