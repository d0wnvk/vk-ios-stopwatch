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
            CameraPreview(
                session: recorder.session,
                focusFeedback: recorder.focusFeedback,
                onFocus: { cameraPoint in
                    recorder.focusAndExpose(at: cameraPoint, lockAfterAdjustment: false)
                },
                onFocusLock: { cameraPoint in
                    recorder.focusAndExpose(at: cameraPoint, lockAfterAdjustment: true)
                },
                onFocusReset: {
                    recorder.restoreContinuousFocusAndExposure()
                }
            )
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
                    Text(String(
                        format: "7. %.1f× · %@",
                        recorder.displayedZoom,
                        recorder.activeCameraName
                    ))
                        .font(.headline.monospacedDigit())
                        .accessibilityLabel(
                            "Current zoom \(String(format: "%.1f", recorder.displayedZoom)) times, "
                            + "using the \(recorder.activeCameraName) camera"
                        )
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
    let focusFeedback: FocusFeedbackState
    let onFocus: (CGPoint) -> Void
    let onFocusLock: (CGPoint) -> Void
    let onFocusReset: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onFocus: onFocus,
            onFocusLock: onFocusLock,
            onFocusReset: onFocusReset
        )
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        context.coordinator.installGestures(on: view)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        context.coordinator.onFocus = onFocus
        context.coordinator.onFocusLock = onFocusLock
        context.coordinator.onFocusReset = onFocusReset
        if uiView.videoPreviewLayer.session !== session {
            uiView.videoPreviewLayer.session = session
        }
        uiView.applyFocusFeedback(focusFeedback)
        uiView.updateVideoOrientation()
    }

    final class Coordinator: NSObject {
        var onFocus: (CGPoint) -> Void
        var onFocusLock: (CGPoint) -> Void
        var onFocusReset: () -> Void

        init(
            onFocus: @escaping (CGPoint) -> Void,
            onFocusLock: @escaping (CGPoint) -> Void,
            onFocusReset: @escaping () -> Void
        ) {
            self.onFocus = onFocus
            self.onFocusLock = onFocusLock
            self.onFocusReset = onFocusReset
        }

        func installGestures(on view: PreviewView) {
            let singleTap = UITapGestureRecognizer(target: self, action: #selector(focus(_:)))
            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(resetFocus(_:)))
            doubleTap.numberOfTapsRequired = 2
            singleTap.require(toFail: doubleTap)

            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(lockFocus(_:)))
            longPress.minimumPressDuration = 0.6
            singleTap.require(toFail: longPress)

            view.addGestureRecognizer(singleTap)
            view.addGestureRecognizer(doubleTap)
            view.addGestureRecognizer(longPress)
        }

        @objc private func focus(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? PreviewView else { return }
            let previewPoint = gesture.location(in: view)
            let cameraPoint = view.videoPreviewLayer.captureDevicePointConverted(
                fromLayerPoint: previewPoint
            )
            view.showFocusReticle(at: previewPoint, isLocked: false)
            onFocus(cameraPoint)
        }

        @objc private func lockFocus(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let view = gesture.view as? PreviewView else { return }
            let previewPoint = gesture.location(in: view)
            let cameraPoint = view.videoPreviewLayer.captureDevicePointConverted(
                fromLayerPoint: previewPoint
            )
            view.showFocusReticle(at: previewPoint, isLocked: true)
            onFocusLock(cameraPoint)
        }

        @objc private func resetFocus(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            (gesture.view as? PreviewView)?.hideFocusReticle()
            onFocusReset()
        }
    }
}

private final class PreviewView: UIView {
    private let focusReticleView = UIView(frame: CGRect(x: 0, y: 0, width: 68, height: 68))
    private let focusLockImageView = UIImageView(image: UIImage(systemName: "lock.fill"))
    private var lockRequested = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureFocusReticle()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureFocusReticle()
    }

    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    func showFocusReticle(at point: CGPoint, isLocked: Bool) {
        focusReticleView.center = point
        lockRequested = isLocked
        focusLockImageView.isHidden = !isLocked
        focusReticleView.isHidden = false
        applyFocusFeedback(.focusing)
    }

    func hideFocusReticle() {
        lockRequested = false
        focusReticleView.isHidden = true
    }

    func applyFocusFeedback(_ state: FocusFeedbackState) {
        guard !focusReticleView.isHidden || state == .hidden else { return }

        let color: UIColor
        switch state {
        case .hidden:
            hideFocusReticle()
            return
        case .focusing:
            color = .systemYellow
            focusReticleView.accessibilityLabel = "Focusing"
        case .focused:
            color = .systemGreen
            focusReticleView.accessibilityLabel = "Focus settled"
        case .failed:
            color = .systemRed
            focusReticleView.accessibilityLabel = "Unable to focus"
        case .locked:
            color = .systemGreen
            focusReticleView.accessibilityLabel = "Focus and exposure locked"
        }

        focusReticleView.layer.borderColor = color.cgColor
        focusLockImageView.tintColor = color
        focusLockImageView.isHidden = !lockRequested
    }

    private func configureFocusReticle() {
        focusReticleView.isHidden = true
        focusReticleView.isUserInteractionEnabled = false
        focusReticleView.layer.borderColor = UIColor.systemYellow.cgColor
        focusReticleView.layer.borderWidth = 2
        focusReticleView.layer.cornerRadius = 6
        focusReticleView.layer.shadowColor = UIColor.black.cgColor
        focusReticleView.layer.shadowOpacity = 0.7
        focusReticleView.layer.shadowRadius = 2
        focusReticleView.layer.shadowOffset = .zero

        focusLockImageView.tintColor = .systemYellow
        focusLockImageView.contentMode = .center
        focusLockImageView.frame = focusReticleView.bounds
        focusLockImageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        focusReticleView.addSubview(focusLockImageView)
        addSubview(focusReticleView)
    }

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
