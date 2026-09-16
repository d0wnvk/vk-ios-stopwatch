import AVFoundation
import AVKit
import SwiftUI

struct Insta360RecorderView: View {
    @EnvironmentObject private var recorder: RecorderController
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var showingPlayer = false
    @State private var pinchStartZoom: CGFloat?

    var body: some View {
        ZStack {
            CameraPreview(session: recorder.session)
                .ignoresSafeArea()
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            guard recorder.canAdjustZoom else { return }
                            let startingZoom = pinchStartZoom ?? recorder.currentZoom
                            if pinchStartZoom == nil { pinchStartZoom = startingZoom }
                            recorder.setZoom(startingZoom * value.magnification)
                        }
                        .onEnded { _ in
                            pinchStartZoom = nil
                        }
                )

            VStack(spacing: isCompactHeight ? 6 : 16) {
                VStack(spacing: isCompactHeight ? 4 : 8) {
                    HStack {
                        Text("1. 4K · 60 FPS")
                            .padding(.horizontal, 10)
                            .padding(.vertical, isCompactHeight ? 6 : 8)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(recorder.gimbalConnected ? .green : .red)
                                .frame(width: 10, height: 10)
                            Text(recorder.gimbalConnected
                                 ? "2. Gimbal detected"
                                 : "2. Gimbal not detected")
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(recorder.gimbalConnected
                                            ? "Gimbal detected"
                                            : "Gimbal not detected")
                        .padding(.horizontal, 10)
                        .padding(.vertical, isCompactHeight ? 6 : 8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }

                    HStack(spacing: 18) {
                        batteryLabel(
                            number: 3,
                            title: "iPhone",
                            level: recorder.iPhoneBatteryLevel,
                            systemImage: "iphone"
                        )
                        .padding(.horizontal, 10)
                        .padding(.vertical, isCompactHeight ? 6 : 8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        Spacer()
                        batteryLabel(
                            number: 4,
                            title: "Gimbal",
                            level: recorder.gimbalBatteryLevel,
                            systemImage: recorder.gimbalIsCharging
                                ? "battery.100percent.bolt"
                                : "battery.100percent"
                        )
                        .padding(.horizontal, 10)
                        .padding(.vertical, isCompactHeight ? 6 : 8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .font(.subheadline.weight(.semibold))

                Spacer()

                Text("5. \(recorder.status)")
                    .multilineTextAlignment(.center)
                    .font(isCompactHeight ? .caption : .body)
                    .padding(isCompactHeight ? 7 : 12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .frame(maxWidth: .infinity, alignment: .trailing)

                if recorder.isRecording {
                    Text("6. REC  \(formattedTime(recorder.recordingElapsed, showTenths: true))")
                        .font(.title3.monospacedDigit().weight(.bold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 14)
                        .padding(.vertical, isCompactHeight ? 4 : 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .accessibilityLabel("Recording time \(formattedTime(recorder.recordingElapsed))")
                }

                HStack(spacing: 8) {
                    Image(systemName: "hand.pinch.fill")
                    Text(String(format: "7. %.1f×", recorder.currentZoom))
                        .font(.headline.monospacedDigit())
                        .frame(minWidth: 60)
                        .accessibilityLabel("Current zoom \(String(format: "%.1f", recorder.currentZoom)) times")

                    Text("8. Pinch preview to zoom")
                        .font(.subheadline.weight(.medium))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, isCompactHeight ? 6 : 10)
                .background(.ultraThinMaterial, in: Capsule())
                .frame(maxWidth: .infinity, alignment: .trailing)

                Button {
                    Task { await recorder.rememberRecordOneEndpoint() }
                } label: {
                    Label(
                        String(format: "9. Set End Zoom & Position: %.1f×", recorder.currentZoom),
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: isCompactHeight ? 34 : 42)
                }
                .buttonStyle(.borderedProminent)
                .tint((recorder.recordOneEndOrientation == nil ? Color.indigo : .green).opacity(0.5))
                .disabled(!recorder.canSetRecordOneEndpoint)
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(String(
                    format: "10. Record 1 endpoint: %.1f× • gimbal %@",
                    recorder.recordOneEndZoom,
                    recorder.recordOneEndOrientation == nil ? "not saved" : "saved"
                ))
                    .font(.caption.monospacedDigit())
                    .frame(maxWidth: .infinity, alignment: .trailing)

                HStack(spacing: 12) {
                    Button(action: recorder.record) {
                        Label(operationLabel(number: 11, default: "Record 1"),
                              systemImage: recorder.isRecording ? "record.circle.fill" : "arrow.up.right.video.fill")
                            .font(.headline)
                            .frame(minHeight: isCompactHeight ? 42 : 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint((recorder.isRecording ? Color.gray : .red).opacity(0.5))
                    .disabled(!recorder.canAttemptRecording)
                    .accessibilityLabel("Record delayed upward tilt and zoom-out shot")

                    Button(action: recorder.recordVerticalZoomOut) {
                        Label(operationLabel(number: 12, default: "Record 2"),
                              systemImage: recorder.isRecording ? "record.circle.fill" : "arrow.up.video.fill")
                            .font(.headline)
                            .frame(minHeight: isCompactHeight ? 42 : 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint((recorder.isRecording ? Color.gray : .blue).opacity(0.5))
                    .disabled(!recorder.canAttemptRecording)
                    .accessibilityLabel("Record vertical tilt and zoom-out shot")

                    Button(action: recorder.cancelRecording) {
                        Label("13. Stop", systemImage: "stop.fill")
                            .font(.headline)
                            .frame(minHeight: isCompactHeight ? 42 : 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.gray.opacity(0.5))
                    .disabled(!recorder.isRecording)
                    .accessibilityLabel("Stop recording")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    showingPlayer = true
                } label: {
                    Label("14. Library", systemImage: "play.rectangle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.black.opacity(0.5))
                .disabled(recorder.lastRecordingURL == nil || recorder.isRecording)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(isCompactHeight ? 8 : 16)
        }
        .task { await recorder.start() }
        .fullScreenCover(isPresented: $showingPlayer) {
            if let url = recorder.lastRecordingURL {
                RecordingPlayer(url: url)
            }
        }
    }

    private var isCompactHeight: Bool { verticalSizeClass == .compact }

    private func operationLabel(number: Int, default defaultLabel: String) -> String {
        if recorder.isRecording { return "\(number). Recording…" }
        if recorder.isReturningGimbal { return "\(number). Returning…" }
        return "\(number). \(defaultLabel)"
    }

    private func batteryLabel(number: Int,
                              title: String,
                              level: Int?,
                              systemImage: String) -> some View {
        Label {
            Text("\(number). \(title) \(level.map { "\($0)%" } ?? "—")")
                .monospacedDigit()
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.white)
        }
        .accessibilityLabel("\(title) battery \(level.map { "\($0) percent" } ?? "unavailable")")
    }
}

private struct RecordingPlayer: View {
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0

    init(url: URL) {
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: player)
                .ignoresSafeArea()

            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Label("15. Back", systemImage: "chevron.left")
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.black.opacity(0.5), in: Capsule())
                    }
                    .foregroundStyle(.white)

                    Spacer()
                }

                Spacer()

                Text("16. \(formattedTime(currentTime)) / \(formattedTime(duration))")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .padding()
        }
        .onAppear { player.play() }
        .onDisappear { player.pause() }
        .task {
            while !Task.isCancelled {
                let playbackTime = player.currentTime().seconds
                let itemDuration = player.currentItem?.duration.seconds ?? 0
                currentTime = playbackTime.isFinite ? max(0, playbackTime) : 0
                duration = itemDuration.isFinite ? max(0, itemDuration) : 0
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }
}

private func formattedTime(_ interval: TimeInterval, showTenths: Bool = false) -> String {
    let safeInterval = interval.isFinite ? max(0, interval) : 0
    let minutes = Int(safeInterval) / 60
    let seconds = Int(safeInterval) % 60
    if showTenths {
        let tenths = Int((safeInterval * 10).rounded(.down)) % 10
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }
    return String(format: "%02d:%02d", minutes, seconds)
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if uiView.videoPreviewLayer.session !== session {
            uiView.videoPreviewLayer.session = session
        }
        uiView.updateVideoOrientation()
    }
}

private final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateVideoOrientation()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateVideoOrientation()
    }

    func updateVideoOrientation() {
        guard let orientation = window?.windowScene?.interfaceOrientation,
              let connection = videoPreviewLayer.connection else { return }
        let angle = correctedVideoRotationAngle(for: orientation)
        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }
}

func videoRotationAngle(for orientation: UIInterfaceOrientation) -> CGFloat {
    switch orientation {
    case .portrait: return 90
    case .portraitUpsideDown: return 270
    case .landscapeRight: return 180
    case .landscapeLeft: return 0
    default: return 90
    }
}

func correctedVideoRotationAngle(for orientation: UIInterfaceOrientation) -> CGFloat {
    let angle = videoRotationAngle(for: orientation)
    switch orientation {
    case .landscapeLeft, .landscapeRight:
        return (angle + 180).truncatingRemainder(dividingBy: 360)
    default:
        return angle
    }
}
