import AVKit
import SwiftUI

private enum ButtonPalette {
    static let toggle = Color(red: 0.07, green: 0.67, blue: 0.72)
    static let compactStart = Color(red: 0.14, green: 0.67, blue: 0.29)
    static let compactStop = Color(red: 0.93, green: 0.49, blue: 0.13)
    static let encoding = Color(red: 0.64, green: 0.36, blue: 0.16)
    static let stabilization = Color(red: 0.28, green: 0.31, blue: 0.82)
    static let focus = Color(red: 0.09, green: 0.72, blue: 0.61)
    static let zoomDuration = Color(red: 0.56, green: 0.27, blue: 0.68)
    static let zoomStart = Color(red: 0.16, green: 0.47, blue: 0.85)
    static let zoomReset = Color(red: 0.12, green: 0.58, blue: 0.78)
    static let zoomEnd = Color(red: 0.89, green: 0.24, blue: 0.53)
    static let playLast = Color(red: 0.00, green: 0.63, blue: 0.86)
    static let programStart = Color(red: 0.10, green: 0.66, blue: 0.24)
    static let fullStop = Color(red: 0.84, green: 0.18, blue: 0.16)
    static let playbackBack = Color(red: 0.34, green: 0.22, blue: 0.73)
}

/// Presents the programmed recording controls and visual stage feedback.
///
/// `CameraRecorder` owns the actual timeline; this view starts or stops it,
/// displays the selected start/end zoom and ramp duration, and changes the
/// recording timer from red to yellow while the zoom-bump stage is active.
struct RecorderScreen: View {
    @StateObject private var recorder = CameraRecorder()
    @State private var isControlsExpanded = true
    @State private var playbackURL: URL?

    var body: some View {
        ZStack {
            CameraPreviewView(session: recorder.session) { devicePoint in
                recorder.focus(at: devicePoint)
            } onOrientationChange: { interfaceOrientation in
                recorder.updateVideoOrientation(interfaceOrientation)
            }
            .ignoresSafeArea()

            LinearGradient(
                colors: [.clear, .black.opacity(0.75)],
                startPoint: .center,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

        }
        .overlay(alignment: .top) {
            if recorder.isRecording {
                recordingStageTimer
                    .padding(.top, 20)
                    .padding(.horizontal, 12)
            }
        }
        .safeAreaInset(edge: .bottom) {
            controlsPanel
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        }
        .background(.black)
        .task {
            recorder.prepareSession()
            recorder.startSession()
        }
        .onDisappear {
            recorder.stopSession()
        }
        .alert("Recorder", isPresented: Binding(
            get: { recorder.alertMessage != nil },
            set: { show in
                if !show {
                    recorder.alertMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {
                recorder.alertMessage = nil
            }
        } message: {
            Text(recorder.alertMessage ?? "")
        }
        .sheet(item: Binding(
            get: {
                playbackURL.map(PlaybackItem.init(url:))
            },
            set: { item in
                playbackURL = item?.url
            }
        )) { item in
            PlaybackView(url: item.url) {
                playbackURL = nil
                collapseControlsForRecording()
                recorder.startProgrammedRecording()
            }
        }
    }

    private var controlsPanel: some View {
        VStack(alignment: .leading, spacing: isControlsExpanded ? 8 : 6) {
            HStack(spacing: isControlsExpanded ? 12 : 8) {
                if isControlsExpanded {
                    Text("iPhone 16 Pro Recorder")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.95))

                    Spacer(minLength: 0)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isControlsExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isControlsExpanded ? "chevron.down" : "chevron.up")
                        .font(.title3.weight(.bold))
                        .frame(width: isControlsExpanded ? 64 : 48, height: isControlsExpanded ? 64 : 48)
                        .background(ButtonPalette.toggle)
                        .foregroundStyle(.white)
                        .clipShape(Circle())
                }

                if !isControlsExpanded {
                    Spacer(minLength: 0)

                    if !recorder.isRecording {
                        Circle()
                            .fill(.white.opacity(0.35))
                            .frame(width: 6, height: 6)

                        Text(recorder.recordingDurationText)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.92))
                    }
                }
            }

            if !isControlsExpanded {
                HStack(spacing: 8) {
                    compactActionButton("Play", color: ButtonPalette.playLast) {
                        playbackURL = recorder.recordedVideoURL
                    }
                    .disabled(recorder.recordedVideoURL == nil || recorder.isRecording)

                    compactActionButton(
                        "Start",
                        color: recorder.isRecording
                            ? ButtonPalette.compactStart.opacity(0.45)
                            : ButtonPalette.compactStart
                    ) {
                        collapseControlsForRecording()
                        recorder.startProgrammedRecording()
                    }
                    .disabled(!recorder.isConfigured || recorder.isRecording)

                    compactActionButton("Stop", color: ButtonPalette.compactStop) {
                        recorder.stopRecording()
                    }
                    .disabled(!recorder.isRecording)

                    compactActionButton("Delete", color: ButtonPalette.fullStop) {
                        if recorder.deleteLastRecording() {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isControlsExpanded = true
                            }
                        }
                    }
                    .disabled(recorder.recordedVideoURL == nil || recorder.isRecording)
                }
            }

            if !isControlsExpanded, let recordedVideoDetailsText = recorder.recordedVideoDetailsText {
                Text(recordedVideoDetailsText)
                    .font(.system(size: 20, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isControlsExpanded {
                Text("4K 60 fps • \(recorder.selectedStartZoom.title) for 2s • eased zoom to \(recorder.selectedEndZoom.title) over \(recorder.selectedZoomDuration.rawValue)s • hold 3s")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.72))

                Text(recorder.statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))

                if !recorder.isRecording {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(.white.opacity(0.35))
                            .frame(width: 8, height: 8)

                        Text(recorder.recordingDurationText)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.92))
                    }
                }

                Text(recorder.focusStatusText)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.72))

                HStack(spacing: 12) {
                    Menu {
                        ForEach(recorder.availableVideoEncodings) { encoding in
                            Button {
                                recorder.setVideoEncoding(encoding)
                            } label: {
                                if recorder.selectedVideoEncoding == encoding {
                                    Label(encoding.title, systemImage: "checkmark")
                                } else {
                                    Text(encoding.title)
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text("Encoding \(recorder.selectedVideoEncoding.title)")
                                .font(.caption.weight(.semibold))
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(ButtonPalette.encoding)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(!recorder.isConfigured || recorder.availableVideoEncodings.isEmpty)

                    Menu {
                        ForEach(recorder.supportedStabilizationModes) { mode in
                            Button {
                                recorder.setStabilizationMode(mode)
                            } label: {
                                if recorder.selectedStabilizationMode == mode {
                                    Label(mode.title, systemImage: "checkmark")
                                } else {
                                    Text(mode.title)
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text("Stabilization \(recorder.selectedStabilizationMode.shortTitle)")
                                .font(.caption.weight(.semibold))
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(ButtonPalette.stabilization)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(!recorder.isConfigured || recorder.supportedStabilizationModes.isEmpty)

                    Button {
                        recorder.toggleFocusLock()
                    } label: {
                        Text(recorder.focusModeState == .locked ? "Focus is locked" : "Auto focus is on")
                            .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(ButtonPalette.focus)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(!recorder.isConfigured)
                }

                Text(recorder.activeStabilizationStatusText)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.72))

                HStack(spacing: 12) {
                    Menu {
                        ForEach(CameraRecorder.ZoomDurationOption.allCases) { option in
                            Button {
                                recorder.selectedZoomDuration = option
                            } label: {
                                if recorder.selectedZoomDuration == option {
                                    Label(option.title, systemImage: "checkmark")
                                } else {
                                    Text(option.title)
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text("Zoom \(recorder.selectedZoomDuration.rawValue)s")
                                .font(.caption.weight(.semibold))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2.weight(.semibold))
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(ButtonPalette.zoomDuration)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    Menu {
                        ForEach(CameraRecorder.StartZoomOption.allCases) { option in
                            Button {
                                recorder.selectedStartZoom = option
                                recorder.resetZoomToStartValue()
                            } label: {
                                if recorder.selectedStartZoom == option {
                                    Label(option.title, systemImage: "checkmark")
                                } else {
                                    Text(option.title)
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text("Start \(recorder.selectedStartZoom.title)")
                                .font(.caption.weight(.semibold))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2.weight(.semibold))
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(ButtonPalette.zoomStart)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(!recorder.isConfigured)

                    Button {
                        recorder.resetZoomToStartValue()
                    } label: {
                        HStack {
                            Text("Reset to Start")
                                .font(.caption.weight(.semibold))
                            Image(systemName: "arrow.counterclockwise")
                                .font(.caption2.weight(.semibold))
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(ButtonPalette.zoomReset)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(!recorder.isConfigured)

                    Menu {
                        ForEach(CameraRecorder.EndZoomOption.allCases) { option in
                            Button {
                                recorder.selectedEndZoom = option
                                recorder.setZoomToEndValue()
                            } label: {
                                if recorder.selectedEndZoom == option {
                                    Label(option.title, systemImage: "checkmark")
                                } else {
                                    Text(option.title)
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text("End \(recorder.selectedEndZoom.title)")
                                .font(.caption.weight(.semibold))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2.weight(.semibold))
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(ButtonPalette.zoomEnd)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(!recorder.isConfigured)
                }

                HStack(spacing: 12) {
                    Button {
                        collapseControlsForRecording()
                        recorder.startTwoToFourEightRecording()
                    } label: {
                        Text("2x-4.8x")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(recorder.isRecording ? ButtonPalette.zoomEnd.opacity(0.45) : ButtonPalette.zoomEnd)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(!recorder.isConfigured || recorder.isRecording)
                }

                HStack(spacing: 12) {
                    Button {
                        playbackURL = recorder.recordedVideoURL
                    } label: {
                        Text("Play Last")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(ButtonPalette.playLast)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(recorder.recordedVideoURL == nil || recorder.isRecording)

                    Button {
                        collapseControlsForRecording()
                        recorder.startProgrammedRecording()
                    } label: {
                        Text(recorder.isRecording ? "Recording..." : "Start Program")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(recorder.isRecording ? ButtonPalette.programStart.opacity(0.45) : ButtonPalette.programStart)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(!recorder.isConfigured || recorder.isRecording)

                    Button {
                        recorder.stopRecording()
                    } label: {
                        Text("Stop")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(ButtonPalette.fullStop)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(!recorder.isRecording)
                }
            }
        }
        .padding(isControlsExpanded ? 14 : 10)
    }

    private var recordingStageTimer: some View {
        HStack(spacing: 6) {
            stageTimerCell(
                title: "HOLD 1",
                elapsed: recorder.recordingStageTimers.initialHold,
                stage: .initialHold
            )
            stageTimerCell(
                title: "ZOOM",
                elapsed: recorder.recordingStageTimers.zoom,
                stage: .zoom
            )
            stageTimerCell(
                title: "HOLD 2",
                elapsed: recorder.recordingStageTimers.finalHold,
                stage: .finalHold
            )
            focusValueCell
        }
        .padding(6)
        .background(.black.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var focusValueCell: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "scope")
                    .font(.system(size: 9, weight: .bold))

                Text("FOCUS")
                    .font(.system(size: 10, weight: .bold))
            }

            Text(String(format: "%.2f", recorder.focusLensPosition))
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .contentTransition(.numericText())

            Text(
                recorder.lensAperture > 0
                    ? String(format: "ƒ/%.2f", recorder.lensAperture)
                    : "ƒ/—"
            )
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(.cyan)
        .frame(minWidth: 72)
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .background(.cyan.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func stageTimerCell(
        title: String,
        elapsed: TimeInterval,
        stage: CameraRecorder.RecordingProgramStage
    ) -> some View {
        let isActive = recorder.recordingStageTimers.activeStage == stage
        let color: Color = stage == .zoom ? .yellow : .red

        return VStack(spacing: 2) {
            HStack(spacing: 4) {
                Circle()
                    .fill(isActive ? color : .white.opacity(0.35))
                    .frame(width: 6, height: 6)

                Text(title)
                    .font(.system(size: 10, weight: .bold))
            }

            Text(formatStageTime(elapsed))
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .contentTransition(.numericText())
        }
        .foregroundStyle(isActive ? color : .white.opacity(0.88))
        .frame(minWidth: 78)
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(isActive ? color.opacity(0.14) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func formatStageTime(_ seconds: TimeInterval) -> String {
        String(format: "%04.1f", max(0, seconds))
    }

    private func compactActionButton(
        _ title: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(color)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func collapseControlsForRecording() {
        guard isControlsExpanded else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            isControlsExpanded = false
        }
    }
}

private struct PlaybackItem: Identifiable {
    let url: URL

    var id: URL { url }
}

private struct PlaybackView: View {
    let url: URL
    let onStartRecording: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer
    @State private var isPlaying = true
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var timeObserver: Any?
    @State private var isScrubbing = false

    init(url: URL, onStartRecording: @escaping () -> Void) {
        self.url = url
        self.onStartRecording = onStartRecording
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        PlaybackPlayerView(player: player)
            .background(.black)
            .ignoresSafeArea()
            .onAppear {
                UIApplication.shared.isIdleTimerDisabled = true
                player.seek(to: .zero)
                player.play()
                isPlaying = true
                configurePlaybackObservation()
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
                if let timeObserver {
                    player.removeTimeObserver(timeObserver)
                    self.timeObserver = nil
                }
                player.pause()
            }
            .persistentSystemOverlays(.visible)
            .overlay {
                playbackControls
            }
    }

    private var playbackControls: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Label("Back", systemImage: "chevron.backward")
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .background(ButtonPalette.playbackBack.opacity(0.92))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }

                Button {
                    player.pause()
                    dismiss()
                    onStartRecording()
                } label: {
                    Label("Start", systemImage: "record.circle")
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .background(ButtonPalette.programStart)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }

                Spacer()
            }
            .padding(.top, 20)
            .padding(.horizontal, 20)

            Spacer()

            VStack(spacing: 10) {
                Slider(
                    value: Binding(
                        get: { duration > 0 ? currentTime : 0 },
                        set: { newValue in
                            isScrubbing = true
                            currentTime = newValue
                        }
                    ),
                    in: 0...(duration > 0 ? duration : 1),
                    onEditingChanged: { editing in
                        if editing {
                            return
                        }

                        let targetTime = CMTime(seconds: currentTime, preferredTimescale: 600)
                        player.seek(to: targetTime)
                        isScrubbing = false
                    }
                )
                .tint(.white)

                HStack {
                    Button {
                        if isPlaying {
                            player.pause()
                        } else {
                            player.play()
                        }
                        isPlaying.toggle()
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3.weight(.bold))
                            .frame(width: 44, height: 44)
                            .background(.white.opacity(0.16))
                            .foregroundStyle(.white)
                            .clipShape(Circle())
                    }

                    Spacer()

                    Text("\(formattedPlaybackTime(currentTime)) / \(formattedPlaybackTime(duration))")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.96))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 20)
        }
    }

    private func configurePlaybackObservation() {
        duration = CMTimeGetSeconds(player.currentItem?.asset.duration ?? .zero)
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }

        let observer = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.2, preferredTimescale: 600),
            queue: .main
        ) { time in
            guard !isScrubbing else { return }
            currentTime = CMTimeGetSeconds(time)
            if let itemDuration = player.currentItem?.duration.seconds, itemDuration.isFinite {
                duration = itemDuration
            }
            isPlaying = player.timeControlStatus == .playing
        }

        timeObserver = observer
    }

    private func formattedPlaybackTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let totalSeconds = Int(seconds.rounded(.down))
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}

private struct PlaybackPlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        uiView.playerLayer.player = player
    }
}

private final class PlayerContainerView: UIView {
    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.videoGravity = .resizeAspect
        backgroundColor = .black
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
