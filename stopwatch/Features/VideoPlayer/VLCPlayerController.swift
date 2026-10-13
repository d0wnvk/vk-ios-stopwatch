import Combine
import MobileVLCKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum VideoDisplayMode {
    case fit
    case fill
}

final class VLCPlayerController: NSObject, ObservableObject, VLCMediaPlayerDelegate {
    @Published private(set) var isPlaying = false
    @Published private(set) var failureCount = 0
    @Published private(set) var completionCount = 0
    @Published private(set) var position = 0.0
    @Published private(set) var elapsedTime = 0.0
    @Published private(set) var duration = 0.0
    @Published private(set) var isSeekable = false
    @Published private(set) var isMuted = false
    @Published private(set) var isExternalDisplayConnected = false
    @Published private(set) var displayMode: VideoDisplayMode = .fit
    @Published private(set) var brightnessPercent = 100
    @Published private(set) var volumePercent = 100
    @Published private(set) var videoParameters =
        "Resolution: —  •  Codec: —  •  FPS: —  •  Bitrate: —  •  Size: —"
    @Published private(set) var diagnostics = PlaybackDiagnosticsSnapshot.empty

    var canSeekNearEnd: Bool {
        isSeekable && duration > 0
    }

    private let mediaPlayer = VLCMediaPlayer()
    private weak var outputView: UIView?
    private var shouldMuteOnStart = false
    private var mediaChangeID = UUID()
    private var isChangingMedia = false
    private var diagnosticsTask: Task<Void, Never>?
    private var diagnosticsSampler = PlaybackDiagnosticsSampler()

    override init() {
        super.init()
        mediaPlayer.delegate = self
    }

    deinit {
        diagnosticsTask?.cancel()
        ExternalDisplayManager.shared.unregister(controller: self)
    }

    func attachPhoneView(_ view: UIView) {
        ExternalDisplayManager.shared.register(controller: self, phoneView: view)
    }

    func setOutputView(_ view: UIView?, isExternal: Bool) {
        outputView = view
        isExternalDisplayConnected = isExternal
        mediaPlayer.drawable = view
        applyDisplayMode()
    }

    func outputViewDidLayout() {
        applyDisplayMode()
    }

    func play(url: URL) async {
        let requestID = UUID()
        mediaChangeID = requestID

        if !isChangingMedia {
            isChangingMedia = true
            mediaPlayer.stop()
            mediaPlayer.media = nil
        }

        diagnosticsSampler.reset()
        diagnostics = .empty
        isPlaying = false
        isSeekable = false
        position = 0
        elapsedTime = 0
        duration = 0
        videoParameters = Self.videoParameters(for: url, media: nil)

        // libVLC stops and tears down its input asynchronously. Replacing the
        // media immediately can mix callbacks from the old and new inputs.
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled, mediaChangeID == requestID else { return }

        mediaPlayer.media = VLCMedia(url: url)
        shouldMuteOnStart = true
        mediaPlayer.audio?.isMuted = true
        isMuted = true
        mediaPlayer.play()
        mediaPlayer.audio?.isMuted = true
        isChangingMedia = false
    }

    func togglePlayback() {
        if mediaPlayer.isPlaying {
            mediaPlayer.pause()
        } else {
            mediaPlayer.play()
        }
    }

    func skip(seconds: Int32) {
        guard mediaPlayer.isSeekable else { return }
        diagnosticsSampler.reset()
        if seconds < 0 {
            mediaPlayer.jumpBackward(-seconds)
        } else {
            mediaPlayer.jumpForward(seconds)
        }
    }

    func seek(to position: Double) {
        guard mediaPlayer.isSeekable else { return }
        diagnosticsSampler.reset()
        mediaPlayer.position = Float(position)
        self.position = position
    }

    func seekToThirtySecondsBeforeEnd() {
        guard canSeekNearEnd else { return }
        seek(to: max(0, duration - 30) / duration)
    }

    func restartFromBeginning() {
        guard mediaPlayer.isSeekable else { return }
        diagnosticsSampler.reset()
        mediaPlayer.position = 0
        position = 0
        mediaPlayer.play()
    }

    func toggleMute() {
        shouldMuteOnStart = false
        mediaPlayer.audio?.isMuted.toggle()
        isMuted = mediaPlayer.audio?.isMuted ?? false
    }

    func setVolumeToTenPercent() {
        shouldMuteOnStart = false
        mediaPlayer.audio?.volume = 10
        mediaPlayer.audio?.isMuted = false
        volumePercent = 10
        isMuted = false
    }

    func adjustVolume(by percentagePoints: Int) {
        shouldMuteOnStart = false
        volumePercent = min(100, max(0, volumePercent + percentagePoints))
        mediaPlayer.audio?.volume = Int32(volumePercent)
        mediaPlayer.audio?.isMuted = volumePercent == 0
        isMuted = volumePercent == 0
    }

    func adjustBrightness(by percentagePoints: Int) {
        brightnessPercent = min(200, max(0, brightnessPercent + percentagePoints))
        mediaPlayer.adjustFilter.brightness.value = NSNumber(
            value: Double(brightnessPercent) / 100
        )
    }

    func toggleDisplayMode() {
        displayMode = displayMode == .fit ? .fill : .fit
        applyDisplayMode()
    }

    func stop() {
        mediaChangeID = UUID()
        isChangingMedia = false
        setDiagnosticsEnabled(false)
        mediaPlayer.stop()
        mediaPlayer.media = nil
        isPlaying = false
        position = 0
        elapsedTime = 0
        duration = 0
        isSeekable = false
    }

    func setDiagnosticsEnabled(_ enabled: Bool) {
        diagnosticsTask?.cancel()
        diagnosticsTask = nil
        guard enabled else { return }

        sampleDiagnostics()
        diagnosticsTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.sampleDiagnostics()
            }
        }
    }

    func mediaPlayerStateChanged(_ notification: Notification) {
        if shouldMuteOnStart {
            mediaPlayer.audio?.isMuted = true
            isMuted = true

            if mediaPlayer.state == .playing {
                shouldMuteOnStart = false
            }
        }

        let newIsPlaying = mediaPlayer.isPlaying
        if isPlaying != newIsPlaying {
            isPlaying = newIsPlaying
        }

        let newIsSeekable = mediaPlayer.isSeekable
        if isSeekable != newIsSeekable {
            isSeekable = newIsSeekable
        }

        let newVolumePercent = min(100, max(0, Int(mediaPlayer.audio?.volume ?? 0)))
        if volumePercent != newVolumePercent {
            volumePercent = newVolumePercent
        }

        if !shouldMuteOnStart {
            let newIsMuted = mediaPlayer.audio?.isMuted ?? false
            if isMuted != newIsMuted {
                isMuted = newIsMuted
            }
        }

        if mediaPlayer.state == .error, !isChangingMedia {
            failureCount += 1
        } else if mediaPlayer.state == .ended, !isChangingMedia {
            completionCount += 1
        }

        if let media = mediaPlayer.media {
            let newVideoParameters = Self.videoParameters(for: media.url, media: media)
            if videoParameters != newVideoParameters {
                videoParameters = newVideoParameters
            }
        }
    }

    func mediaPlayerTimeChanged(_ notification: Notification) {
        let newPosition = Double(mediaPlayer.position)
        if abs(position - newPosition) >= 0.001 {
            position = newPosition
        }

        let newElapsedTime = max(0, Double(mediaPlayer.time.intValue) / 1_000)
        if abs(elapsedTime - newElapsedTime) >= 0.05 {
            elapsedTime = newElapsedTime
        }

        let newDuration = max(
            0,
            Double(mediaPlayer.media?.length.intValue ?? 0) / 1_000
        )
        if duration != newDuration {
            duration = newDuration
        }

        let newIsSeekable = mediaPlayer.isSeekable
        if isSeekable != newIsSeekable {
            isSeekable = newIsSeekable
        }
    }

    private func applyDisplayMode() {
        guard displayMode == .fill, let outputView else {
            mediaPlayer.videoCropGeometry = nil
            return
        }

        let size = outputView.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        let geometry = "\(Int(size.width)):\(Int(size.height))"
        geometry.withCString {
            mediaPlayer.videoCropGeometry = UnsafeMutablePointer(mutating: $0)
        }
    }

    private func sampleDiagnostics() {
        let media = mediaPlayer.media
        let statistics = media?.statistics
        let sample = PlaybackDiagnosticSample(
            state: diagnosticState,
            inputBitrate: statistics.map { Double($0.inputBitrate) },
            demuxBitrate: statistics.map { Double($0.demuxBitrate) },
            decodedVideo: statistics.map { Int($0.decodedVideo) },
            displayedPictures: statistics.map { Int($0.displayedPictures) },
            lostPictures: statistics.map { Int($0.lostPictures) },
            playedAudioBuffers: statistics.map { Int($0.playedAudioBuffers) },
            lostAudioBuffers: statistics.map { Int($0.lostAudioBuffers) },
            corruptedPackets: statistics.map { Int($0.demuxCorrupted) },
            discontinuities: statistics.map { Int($0.demuxDiscontinuity) },
            playbackTime: max(0, Double(mediaPlayer.time.intValue) / 1_000),
            brightnessPercent: brightnessPercent
        )
        diagnostics = diagnosticsSampler.snapshot(for: sample)
    }

    private var diagnosticState: PlaybackDiagnosticState {
        switch mediaPlayer.state {
        case .playing: .playing
        case .paused: .paused
        case .buffering, .opening: .buffering
        case .error: .error
        default: .stopped
        }
    }

    private static func videoParameters(for url: URL?, media: VLCMedia?) -> String {
        let fileSize = url.flatMap {
            try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize
        }
        let formattedSize = fileSize.map {
            ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file)
        } ?? "—"

        guard
            let videoTrack = media?.tracksInformation.first(where: { track in
                (track as? [String: Any])?[VLCMediaTracksInformationType]
                    as? String == VLCMediaTracksInformationTypeVideo
            }) as? [String: Any]
        else {
            return "Resolution: —  •  Codec: —  •  FPS: —  •  Bitrate: —  •  Size: \(formattedSize)"
        }

        let width = (videoTrack[VLCMediaTracksInformationVideoWidth] as? NSNumber)?.intValue
        let height = (videoTrack[VLCMediaTracksInformationVideoHeight] as? NSNumber)?.intValue
        let resolution = if let width, let height, width > 0, height > 0 {
            "\(width)×\(height)"
        } else {
            "—"
        }

        let codec = (videoTrack[VLCMediaTracksInformationCodec] as? NSNumber)
            .map { fourCC($0.uint32Value) } ?? "—"

        let frameRate = (videoTrack[VLCMediaTracksInformationFrameRate] as? NSNumber)?
            .doubleValue
        let frameRateDenominator =
            (videoTrack[VLCMediaTracksInformationFrameRateDenominator] as? NSNumber)?
            .doubleValue
        let framesPerSecond = if
            let frameRate,
            let frameRateDenominator,
            frameRate > 0,
            frameRateDenominator > 0
        {
            formattedFrameRate(frameRate / frameRateDenominator)
        } else {
            "—"
        }

        let bitrate = (videoTrack[VLCMediaTracksInformationBitrate] as? NSNumber)?
            .doubleValue
        let formattedBitrate = if let bitrate, bitrate > 0 {
            String(format: "%.1f Mbps", bitrate / 1_000_000)
        } else {
            "—"
        }

        return "Resolution: \(resolution)  •  Codec: \(codec)  •  FPS: \(framesPerSecond)  •  Bitrate: \(formattedBitrate)  •  Size: \(formattedSize)"
    }

    private static func formattedFrameRate(_ framesPerSecond: Double) -> String {
        if abs(framesPerSecond.rounded() - framesPerSecond) < 0.001 {
            return String(Int(framesPerSecond.rounded()))
        }
        return String(format: "%.2f", framesPerSecond)
    }

    private static func fourCC(_ value: UInt32) -> String {
        let bytes = [
            UInt8(value & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 24) & 0xff)
        ]
        let text = String(bytes: bytes, encoding: .ascii)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? "—" : text.uppercased()
    }
}

extension Double {
    var formattedPlaybackTime: String {
        guard isFinite, self >= 0 else { return "00:00" }
        let totalSeconds = Int(self)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
