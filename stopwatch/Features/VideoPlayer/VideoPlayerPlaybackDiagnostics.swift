import Foundation

enum PlaybackDiagnosticState: String {
    case playing = "Playing"
    case paused = "Paused"
    case buffering = "Buffering"
    case stopped = "Stopped"
    case error = "Error"
}

enum PlaybackDiagnosticStatus: String {
    case healthy = "Healthy"
    case buffering = "Buffering"
    case videoStalled = "Video stalled"
    case playbackError = "Playback error"
}

struct PlaybackDiagnosticSample {
    var state: PlaybackDiagnosticState
    var inputBitrate: Double?
    var demuxBitrate: Double?
    var decodedVideo: Int?
    var displayedPictures: Int?
    var lostPictures: Int?
    var playedAudioBuffers: Int?
    var lostAudioBuffers: Int?
    var corruptedPackets: Int?
    var discontinuities: Int?
    var playbackTime: TimeInterval
    var brightnessPercent: Int
}

struct PlaybackDiagnosticsSnapshot {
    static let empty = PlaybackDiagnosticsSnapshot(
        status: .healthy,
        state: .stopped,
        inputBitrate: nil,
        demuxBitrate: nil,
        decodedVideo: nil,
        displayedPictures: nil,
        lostPictures: nil,
        playedAudioBuffers: nil,
        lostAudioBuffers: nil,
        corruptedPackets: nil,
        discontinuities: nil,
        playbackTime: 0,
        playbackAdvance: nil,
        brightnessPercent: 100
    )

    var status: PlaybackDiagnosticStatus
    var state: PlaybackDiagnosticState
    var inputBitrate: Double?
    var demuxBitrate: Double?
    var decodedVideo: Int?
    var displayedPictures: Int?
    var lostPictures: Int?
    var playedAudioBuffers: Int?
    var lostAudioBuffers: Int?
    var corruptedPackets: Int?
    var discontinuities: Int?
    var playbackTime: TimeInterval
    var playbackAdvance: TimeInterval?
    var brightnessPercent: Int

    var lines: [String] {
        [
            "STATUS  \(status.rawValue)  •  STATE  \(state.rawValue)",
            "RATE    input \(Self.bitrate(inputBitrate))  •  demux \(Self.bitrate(demuxBitrate))",
            "VIDEO   decoded \(Self.count(decodedVideo))  •  shown \(Self.count(displayedPictures))  •  lost \(Self.count(lostPictures))",
            "AUDIO   played \(Self.count(playedAudioBuffers))  •  lost \(Self.count(lostAudioBuffers))",
            "DEMUX   corrupt \(Self.count(corruptedPackets))  •  discontinuities \(Self.count(discontinuities))",
            "TIME    \(Self.time(playbackTime))  •  advance \(Self.advance(playbackAdvance))  •  brightness \(brightnessPercent == 100 ? "off" : "on \(brightnessPercent)%")"
        ]
    }

    private static func count(_ value: Int?) -> String {
        value.map(String.init) ?? "—"
    }

    private static func bitrate(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.2f Mb/s", value * 8)
    }

    private static func time(_ value: TimeInterval) -> String {
        String(format: "%.1fs", value)
    }

    private static func advance(_ value: TimeInterval?) -> String {
        guard let value else { return "—" }
        return String(format: "%+.1fs", value)
    }
}

struct PlaybackDiagnosticsSampler {
    private var previousSample: PlaybackDiagnosticSample?
    private var consecutiveNonAdvancingSamples = 0

    mutating func reset() {
        previousSample = nil
        consecutiveNonAdvancingSamples = 0
    }

    mutating func snapshot(for sample: PlaybackDiagnosticSample) -> PlaybackDiagnosticsSnapshot {
        let playbackAdvance = previousSample.map { sample.playbackTime - $0.playbackTime }
        let timeAdvanced = playbackAdvance.map { $0 > 0.01 } ?? true
        let framesAdvanced: Bool = if
            let current = sample.displayedPictures,
            let previous = previousSample?.displayedPictures
        {
            current > previous
        } else {
            true
        }

        if sample.state == .playing, !timeAdvanced, !framesAdvanced {
            consecutiveNonAdvancingSamples += 1
        } else {
            consecutiveNonAdvancingSamples = 0
        }

        let status: PlaybackDiagnosticStatus
        switch sample.state {
        case .error:
            status = .playbackError
        case .buffering:
            status = .buffering
        case .playing where consecutiveNonAdvancingSamples >= 2:
            status = .videoStalled
        default:
            status = .healthy
        }

        previousSample = sample
        return PlaybackDiagnosticsSnapshot(
            status: status,
            state: sample.state,
            inputBitrate: sample.inputBitrate,
            demuxBitrate: sample.demuxBitrate,
            decodedVideo: sample.decodedVideo,
            displayedPictures: sample.displayedPictures,
            lostPictures: sample.lostPictures,
            playedAudioBuffers: sample.playedAudioBuffers,
            lostAudioBuffers: sample.lostAudioBuffers,
            corruptedPackets: sample.corruptedPackets,
            discontinuities: sample.discontinuities,
            playbackTime: sample.playbackTime,
            playbackAdvance: playbackAdvance,
            brightnessPercent: sample.brightnessPercent
        )
    }
}
