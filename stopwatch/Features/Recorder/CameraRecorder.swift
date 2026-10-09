import AVFoundation
import Combine
import Photos
import SwiftUI
import UIKit

/// Owns the automated recording program and its frame-driven zoom timeline.
///
/// A recording proceeds through these stages:
/// 1. Before writing begins, move to the selected start zoom and wait for it to
///    settle, be reconfirmed, and remain ready for several video frames. This
///    keeps the setup movement out of the saved clip.
/// 2. Record a two-second hold at the start zoom.
/// 3. Perform the "zoom bump": interpolate from the selected start zoom to the
///    selected end zoom once per video frame, using smoothstep easing so the
///    movement accelerates gently and decelerates near the end.
/// 4. Hold the end zoom for the configured final-hold duration, anchored to the
///    frame on which the end zoom is actually reached.
/// 5. Stop appending samples, finalize the movie, and save it to Photos.
///
/// `isZoomRampActive` is true only during stage 3, allowing the UI to show a
/// yellow recording timer during the bump and a red timer during both holds.
final class CameraRecorder: NSObject, ObservableObject {
    enum RecordingProgramStage: Equatable, Sendable {
        case initialHold
        case zoom
        case finalHold
    }

    private enum PhysicalCamera {
        case wide
        case telephoto

        var deviceType: AVCaptureDevice.DeviceType {
            switch self {
            case .wide:
                return .builtInWideAngleCamera
            case .telephoto:
                return .builtInTelephotoCamera
            }
        }

        var title: String {
            switch self {
            case .wide:
                return "Main camera"
            case .telephoto:
                return "5x Telephoto camera"
            }
        }
    }

    struct RecordingStageTimers: Sendable {
        var initialHold: TimeInterval = 0
        var zoom: TimeInterval = 0
        var finalHold: TimeInterval = 0
        var activeStage: RecordingProgramStage = .initialHold
    }

    enum VideoEncodingOption: CaseIterable, Identifiable {
        case hevc
        case h264
        case appleProRes422
        case appleProRes422HQ
        case appleProRes422LT
        case appleProRes422Proxy
        case appleProRes4444
        case appleProRes4444XQ

        var id: String { title }

        var title: String {
            switch self {
            case .hevc:
                return "HEVC"
            case .h264:
                return "H.264"
            case .appleProRes422:
                return "ProRes 422"
            case .appleProRes422HQ:
                return "ProRes 422 HQ"
            case .appleProRes422LT:
                return "ProRes 422 LT"
            case .appleProRes422Proxy:
                return "ProRes 422 Proxy"
            case .appleProRes4444:
                return "ProRes 4444"
            case .appleProRes4444XQ:
                return "ProRes 4444 XQ"
            }
        }

        var codecType: AVVideoCodecType {
            switch self {
            case .hevc:
                return .hevc
            case .h264:
                return .h264
            case .appleProRes422:
                return .proRes422
            case .appleProRes422HQ:
                return .proRes422HQ
            case .appleProRes422LT:
                return .proRes422LT
            case .appleProRes422Proxy:
                return .proRes422Proxy
            case .appleProRes4444:
                return .proRes4444
            case .appleProRes4444XQ:
                if #available(iOS 18.0, *) {
                    return .appleProRes4444XQ
                }
                return .proRes4444
            }
        }

        static func from(_ codecType: AVVideoCodecType) -> VideoEncodingOption? {
            switch codecType {
            case .hevc:
                return .hevc
            case .h264:
                return .h264
            case .proRes422:
                return .appleProRes422
            case .proRes422HQ:
                return .appleProRes422HQ
            case .proRes422LT:
                return .appleProRes422LT
            case .proRes422Proxy:
                return .appleProRes422Proxy
            case .proRes4444:
                return .appleProRes4444
            default:
                if #available(iOS 18.0, *), codecType == .appleProRes4444XQ {
                    return .appleProRes4444XQ
                }
                return nil
            }
        }

        static var allCases: [VideoEncodingOption] {
            var cases: [VideoEncodingOption] = [
                .hevc,
                .h264,
                .appleProRes422,
                .appleProRes422HQ,
                .appleProRes422LT,
                .appleProRes422Proxy,
                .appleProRes4444
            ]

            if #available(iOS 18.0, *) {
                cases.append(.appleProRes4444XQ)
            }

            return cases
        }
    }

    enum StartZoomOption: String, CaseIterable, Identifiable {
        case twoPointOne = "2.1"
        case three = "3"
        case four = "4"
        case fivePointOne = "5.1"
        case six = "6"
        case eight = "8"
        case ten = "10"

        var id: String { rawValue }

        var title: String {
            "\(rawValue)x"
        }

        var factor: CGFloat {
            CGFloat(Double(rawValue) ?? 2.1)
        }
    }

    enum EndZoomOption: String, CaseIterable, Identifiable {
        case fourPointNine = "4.9"
        case eight = "8"
        case ten = "10"
        case twelve = "12"
        case fourteen = "14"
        case nine = "9"

        var id: String { rawValue }

        var title: String {
            "\(rawValue)x"
        }

        var factor: CGFloat {
            CGFloat(Double(rawValue) ?? 4.9)
        }
    }

    enum ZoomDurationOption: Int, CaseIterable, Identifiable {
        case four = 4
        case eight = 8
        case twelve = 12
        case sixteen = 16
        case twenty = 20

        var id: Int { rawValue }

        var title: String {
            "\(rawValue) seconds"
        }

        var duration: TimeInterval {
            TimeInterval(rawValue)
        }
    }

    enum FocusModeState: String {
        case auto = "Auto Focus"
        case locked = "Focus Locked"
    }

    enum StabilizationModeOption: String, CaseIterable, Identifiable {
        case auto
        case off
        case standard
        case cinematic
        case cinematicExtended
        case previewOptimized
        case cinematicExtendedEnhanced

        var id: String { rawValue }

        var title: String {
            switch self {
            case .auto:
                return "Auto"
            case .off:
                return "Off"
            case .standard:
                return "Standard"
            case .cinematic:
                return "Cinematic"
            case .cinematicExtended:
                return "Cinematic Extended"
            case .previewOptimized:
                return "Preview Optimized"
            case .cinematicExtendedEnhanced:
                return "Cinematic Enhanced"
            }
        }

        var shortTitle: String {
            switch self {
            case .cinematicExtended:
                return "Cine Ext"
            case .previewOptimized:
                return "Preview"
            case .cinematicExtendedEnhanced:
                return "Cine+"
            default:
                return title
            }
        }

        var avMode: AVCaptureVideoStabilizationMode? {
            switch self {
            case .auto:
                return .auto
            case .off:
                return .off
            case .standard:
                return .standard
            case .cinematic:
                return .cinematic
            case .cinematicExtended:
                return .cinematicExtended
            case .previewOptimized:
                if #available(iOS 17.0, *) {
                    return .previewOptimized
                }
                return nil
            case .cinematicExtendedEnhanced:
                if #available(iOS 18.0, *) {
                    return .cinematicExtendedEnhanced
                }
                return nil
            }
        }

        static func from(_ mode: AVCaptureVideoStabilizationMode) -> StabilizationModeOption {
            switch mode {
            case .off:
                return .off
            case .standard:
                return .standard
            case .cinematic:
                return .cinematic
            case .cinematicExtended:
                return .cinematicExtended
            case .auto:
                return .auto
            default:
                if #available(iOS 18.0, *), mode == .cinematicExtendedEnhanced {
                    return .cinematicExtendedEnhanced
                }
                if #available(iOS 17.0, *), mode == .previewOptimized {
                    return .previewOptimized
                }
                return .off
            }
        }
    }

    enum RecorderError: LocalizedError {
        case unsupportedDevice
        case cameraPermissionDenied
        case microphonePermissionDenied
        case missingVideoDevice
        case missingRequestedCamera(String)
        case missingAudioDevice
        case unsupportedFormat
        case cannotAddInput
        case cannotAddOutput
        case configurationFailed

        var errorDescription: String? {
            switch self {
            case .unsupportedDevice:
                return "This app is configured for an iPhone camera path that supports 4K 60 fps recording with a 2.1x to 4.5x zoom program."
            case .cameraPermissionDenied:
                return "Camera access is required."
            case .microphonePermissionDenied:
                return "Microphone access is required."
            case .missingVideoDevice:
                return "The back camera is not available."
            case let .missingRequestedCamera(cameraName):
                return "The \(cameraName) is not available on this iPhone."
            case .missingAudioDevice:
                return "The microphone is not available."
            case .unsupportedFormat:
                return "4K 60 fps is not available for the selected camera configuration."
            case .cannotAddInput:
                return "Unable to add a capture input."
            case .cannotAddOutput:
                return "Unable to add a movie output."
            case .configurationFailed:
                return "Camera configuration failed."
            }
        }
    }

    private enum Constants {
        static let defaultInitialZoom: CGFloat = 2.1
        static let defaultTargetZoom: CGFloat = 4.9
        static let initialHold: TimeInterval = 2
        static let defaultRampDuration: TimeInterval = 8
        static let finalHold: TimeInterval = 3
        static let zoomSettleDelay: TimeInterval = 0.25
        static let zoomSettleConfirmationDelay: TimeInterval = 0.2
        static let recordingStartReadyFrameCount = 6
        static let recordingStartDelayAfterZoomReady: TimeInterval = 0.5
        static let zoomSettleTimeout: TimeInterval = 1.5
        static let zoomTolerance: CGFloat = 0.02
        static let zoomRampStepInterval: TimeInterval = 1.0 / 60.0
        static let zoomRampEaseExponent: CGFloat = 1
        static let frameDuration = CMTime(value: 1, timescale: 60)
        static let videoSize = CGSize(width: 3840, height: 2160)
    }

    @Published private(set) var statusText = "Requesting permissions..."
    @Published private(set) var isConfigured = false
    @Published private(set) var isRecording = false
    @Published private(set) var isZoomRampActive = false
    @Published private(set) var recordingStageTimers = RecordingStageTimers()
    @Published private(set) var focusLensPosition: Float = 0
    @Published private(set) var lensAperture: Float = 0
    @Published private(set) var recordedVideoURL: URL?
    @Published private(set) var recordingDurationText = "00:00"
    @Published private(set) var focusModeState: FocusModeState = .auto
    @Published private(set) var focusStatusText = "Continuous autofocus"
    @Published private(set) var supportedStabilizationModes: [StabilizationModeOption] = []
    @Published private(set) var selectedStabilizationMode: StabilizationModeOption = .auto
    @Published private(set) var activeStabilizationStatusText = "Stabilization not configured"
    @Published private(set) var activePhysicalCameraTitle = "Main/Wide"
    @Published private(set) var availableVideoEncodings: [VideoEncodingOption] = []
    @Published private(set) var selectedVideoEncoding: VideoEncodingOption = .hevc
    @Published private(set) var recordedVideoDetailsText: String?
    @Published var selectedStartZoom: StartZoomOption = .twoPointOne
    @Published var selectedEndZoom: EndZoomOption = .fourPointNine
    @Published var selectedZoomDuration: ZoomDurationOption = .four
    @Published var alertMessage: String?

    nonisolated(unsafe) let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "videorecorder.session")
    private let writerQueue = DispatchQueue(label: "videorecorder.writer")
    private nonisolated(unsafe) let videoDataOutput = AVCaptureVideoDataOutput()
    private nonisolated(unsafe) let audioDataOutput = AVCaptureAudioDataOutput()
    private nonisolated(unsafe) var videoDevice: AVCaptureDevice?
    private var recordingTimerTask: Task<Void, Never>?
    private var pendingRecordingStartWorkItem: DispatchWorkItem?
    private var recordingStartedAt: Date?
    private var isPreparingRecordingStart = false
    @Published private(set) var isSwitchingCamera = false
    private var currentVideoOrientation: AVCaptureVideoOrientation = .portrait
    private nonisolated(unsafe) var assetWriter: AVAssetWriter?
    private nonisolated(unsafe) var videoWriterInput: AVAssetWriterInput?
    private nonisolated(unsafe) var audioWriterInput: AVAssetWriterInput?
    private nonisolated(unsafe) var recordingOutputURL: URL?
    private nonisolated(unsafe) var writerIsPrepared = false
    private nonisolated(unsafe) var writerHasStartedSession = false
    private nonisolated(unsafe) var isFinishingRecording = false
    private nonisolated(unsafe) var recordingStartTime: CMTime?
    private nonisolated(unsafe) var plannedRecordingEndTime: CMTime?
    private nonisolated(unsafe) var hasReachedPlannedEndTime = false
    private nonisolated(unsafe) var shouldStopAppendingSamples = false
    private nonisolated(unsafe) var recordingStopTime: CMTime?
    private nonisolated(unsafe) var programmedFinalHoldStartTime: CMTime?
    private nonisolated(unsafe) var readyVideoFrameCountBeforeStart = 0
    private nonisolated(unsafe) var programmedStartZoomFactor = Constants.defaultInitialZoom
    private nonisolated(unsafe) var programmedEndZoomFactor = Constants.defaultTargetZoom
    private nonisolated(unsafe) var programmedRampDuration = Constants.defaultRampDuration
    private nonisolated(unsafe) var programmedInitialHoldDuration = Constants.initialHold
    private nonisolated(unsafe) var programmedFinalHoldDuration = Constants.finalHold
    private nonisolated(unsafe) var programmedFocusLockEnabled = false
    private nonisolated(unsafe) var lockedFocusLensPosition: Float?
    private nonisolated(unsafe) var usesLinearZoomRamp = false
    private nonisolated(unsafe) var usesCosineZoomRamp = false
    private nonisolated(unsafe) var programmedStartZoomTitle = "\(Constants.defaultInitialZoom)x"
    private nonisolated(unsafe) var programmedEndZoomTitle = "\(Constants.defaultTargetZoom)x"

    override init() {
        selectedStartZoom = StartZoomOption.allCases.first(where: {
            $0.factor == Constants.defaultInitialZoom
        }) ?? .twoPointOne
        selectedEndZoom = EndZoomOption.allCases.first(where: {
            $0.factor == Constants.defaultTargetZoom
        }) ?? .fourPointNine
        selectedZoomDuration = ZoomDurationOption.allCases.first(where: {
            $0.duration == Constants.defaultRampDuration
        }) ?? .four
        super.init()
    }

    func prepareSession() {
        Task {
            do {
                try await requestPermissions()
                try await configureSession()
            } catch {
                statusText = error.localizedDescription
                alertMessage = error.localizedDescription
            }
        }
    }

    func startSession() {
        sessionQueue.async {
            guard !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func selectMainCamera() {
        selectCameraForPreview(.wide, zoomFactor: 1.0)
    }

    func selectTelephotoCamera() {
        selectCameraForPreview(.telephoto, zoomFactor: 1.0)
    }

    private func selectCameraForPreview(_ camera: PhysicalCamera, zoomFactor: CGFloat) {
        guard isConfigured, !isRecording, !isPreparingRecordingStart, !isSwitchingCamera else { return }

        isSwitchingCamera = true
        statusText = "Switching to \(camera.title)"

        switchToCamera(camera, startZoom: zoomFactor, endZoom: zoomFactor) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isSwitchingCamera = false

                switch result {
                case .success:
                    self.activePhysicalCameraTitle = camera.title
                    self.statusText = "\(camera.title) selected"
                case let .failure(error):
                    self.statusText = error.localizedDescription
                    self.alertMessage = error.localizedDescription
                }
            }
        }
    }

    func stopSession() {
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func startProgrammedRecording() {
        startProgrammedRecording(
            startZoom: selectedStartZoom.factor,
            endZoom: selectedEndZoom.factor,
            initialHold: Constants.initialHold,
            rampDuration: selectedZoomDuration.duration,
            finalHold: Constants.finalHold,
            usesLinearRamp: false,
            usesCosineRamp: false,
            startZoomTitle: selectedStartZoom.title,
            endZoomTitle: selectedEndZoom.title
        )
    }

    func startTwoToFourEightRecording() {
        startCosineRecording(
            startZoom: 2.0,
            endZoom: 4.8,
            camera: .wide,
            startZoomTitle: "2x",
            endZoomTitle: "4.8x"
        )
    }

    func startOneOneToFourNineRecording() {
        startCosineRecording(
            startZoom: 1.1,
            endZoom: 4.9,
            camera: .wide,
            startZoomTitle: "1.1x",
            endZoomTitle: "4.9x"
        )
    }

    func startFiveOneToEightOneRecording() {
        startCosineRecording(
            startZoom: 5.1 / 5.0,
            endZoom: 8.1 / 5.0,
            camera: .telephoto,
            startZoomTitle: "5.1x",
            endZoomTitle: "8.1x"
        )
    }

    private func startCosineRecording(
        startZoom: CGFloat,
        endZoom: CGFloat,
        camera: PhysicalCamera,
        startZoomTitle: String,
        endZoomTitle: String
    ) {
        guard isConfigured, !isRecording, !isPreparingRecordingStart, !isSwitchingCamera else { return }

        isSwitchingCamera = true
        statusText = "Switching to \(camera.title)"

        switchToCamera(camera, startZoom: startZoom, endZoom: endZoom) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isSwitchingCamera = false

                switch result {
                case .success:
                    self.activePhysicalCameraTitle = camera.title
                    self.startProgrammedRecording(
                        startZoom: startZoom,
                        endZoom: endZoom,
                        initialHold: 4,
                        rampDuration: 6,
                        finalHold: 6,
                        usesLinearRamp: false,
                        usesCosineRamp: true,
                        startZoomTitle: startZoomTitle,
                        endZoomTitle: endZoomTitle
                    )
                case let .failure(error):
                    self.statusText = error.localizedDescription
                    self.alertMessage = error.localizedDescription
                }
            }
        }
    }

    private func startProgrammedRecording(
        startZoom: CGFloat,
        endZoom: CGFloat,
        initialHold: TimeInterval,
        rampDuration: TimeInterval,
        finalHold: TimeInterval,
        usesLinearRamp: Bool,
        usesCosineRamp: Bool,
        startZoomTitle: String,
        endZoomTitle: String
    ) {
        guard isConfigured, !isRecording, !isPreparingRecordingStart else { return }
        guard let videoDevice,
              endZoom <= videoDevice.activeFormat.videoMaxZoomFactor else {
            let maximumZoom = videoDevice?.activeFormat.videoMaxZoomFactor ?? 1
            statusText = "The active camera does not support \(endZoomTitle) zoom"
            alertMessage = String(
                format: "The active camera supports zoom only up to %.1fx.",
                maximumZoom
            )
            return
        }

        programmedStartZoomFactor = startZoom
        programmedEndZoomFactor = endZoom
        programmedInitialHoldDuration = initialHold
        programmedRampDuration = rampDuration
        programmedFinalHoldDuration = finalHold
        programmedFocusLockEnabled = focusModeState == .locked
        usesLinearZoomRamp = usesLinearRamp
        usesCosineZoomRamp = usesCosineRamp
        programmedStartZoomTitle = startZoomTitle
        programmedEndZoomTitle = endZoomTitle
        recordingStageTimers = RecordingStageTimers()
        isPreparingRecordingStart = true
        statusText = "Setting zoom to \(programmedStartZoomTitle)"
        recordedVideoURL = nil
        recordedVideoDetailsText = nil

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        try? FileManager.default.removeItem(at: outputURL)

        sessionQueue.async {
            do {
                try self.setZoom(self.programmedStartZoomFactor, cancelExistingRamp: true)
                if self.programmedFocusLockEnabled {
                    try self.lockCurrentFocusConfiguration(useStoredLensPosition: true)
                }
            } catch {
                Task { @MainActor in
                    self.isPreparingRecordingStart = false
                    self.alertMessage = error.localizedDescription
                    self.statusText = error.localizedDescription
                }
                return
            }

            if self.programmedFocusLockEnabled {
                Task { @MainActor in
                    self.focusModeState = .locked
                    self.focusStatusText = "Focus and exposure locked for recording"
                }
            }

            self.pendingRecordingStartWorkItem?.cancel()
            self.scheduleRecordingStartWhenZoomReady(
                to: outputURL,
                targetZoomFactor: self.programmedStartZoomFactor,
                deadline: Date().addingTimeInterval(Constants.zoomSettleTimeout)
            )
        }
    }

    func updateVideoOrientation(_ interfaceOrientation: UIInterfaceOrientation) {
        guard let videoOrientation = AVCaptureVideoOrientation(interfaceOrientation) else {
            return
        }

        sessionQueue.async {
            self.currentVideoOrientation = videoOrientation
        }
    }

    func stopRecording() {
        guard isRecording || isPreparingRecordingStart else { return }
        cancelRecordingTimer()
        cancelPendingRecordingStart()

        if !isRecording {
            isPreparingRecordingStart = false
            statusText = "Recording start cancelled"
            return
        }

        sessionQueue.async {
            self.finishRecording()
        }
    }

    @discardableResult
    func deleteLastRecording() -> Bool {
        guard !isRecording, let recordedVideoURL else { return false }

        do {
            if FileManager.default.fileExists(atPath: recordedVideoURL.path) {
                try FileManager.default.removeItem(at: recordedVideoURL)
            }
            self.recordedVideoURL = nil
            recordedVideoDetailsText = nil
            recordingDurationText = "00:00"
            statusText = "Last recording deleted"
            return true
        } catch {
            statusText = "Unable to delete last recording"
            alertMessage = error.localizedDescription
            return false
        }
    }

    func setStabilizationMode(_ mode: StabilizationModeOption) {
        sessionQueue.async {
            self.applyStabilizationMode(mode)
        }
    }

    func setVideoEncoding(_ encoding: VideoEncodingOption) {
        sessionQueue.async {
            self.applyVideoEncoding(encoding)
        }
    }

    func toggleFocusLock() {
        if focusModeState == .locked {
            enableContinuousAutoFocus()
        } else {
            lockCurrentFocus()
        }
    }

    func resetZoomToStartValue() {
        do {
            try setZoom(selectedStartZoom.factor, cancelExistingRamp: true)
            statusText = "Zoom reset to \(selectedStartZoom.title)"
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func setZoomToEndValue() {
        do {
            try setZoom(selectedEndZoom.factor, cancelExistingRamp: true)
            statusText = "Zoom set to \(selectedEndZoom.title)"
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func focus(at devicePoint: CGPoint) {
        sessionQueue.async {
            do {
                let shouldKeepFocusLocked = self.focusModeState == .locked
                try self.applyFocus(at: devicePoint, keepFocusLocked: shouldKeepFocusLocked)
                Task { @MainActor in
                    self.focusStatusText = String(
                        format: shouldKeepFocusLocked
                            ? "Focus locked at %.0f%%, %.0f%%"
                            : "Focused at %.0f%%, %.0f%%",
                        devicePoint.x * 100,
                        devicePoint.y * 100
                    )
                }
            } catch {
                Task { @MainActor in
                    self.alertMessage = error.localizedDescription
                }
            }
        }
    }

    private func requestPermissions() async throws {
        let cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
        guard cameraGranted else {
            throw RecorderError.cameraPermissionDenied
        }

        let microphoneGranted = await AVCaptureDevice.requestAccess(for: .audio)
        guard microphoneGranted else {
            throw RecorderError.microphonePermissionDenied
        }
    }

    private func configureSession() async throws {
        if isConfigured {
            return
        }

        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                do {
                    self.session.beginConfiguration()
                    self.session.sessionPreset = .inputPriority
                    defer { self.session.commitConfiguration() }

                    self.session.inputs.forEach { self.session.removeInput($0) }
                    self.session.outputs.forEach { self.session.removeOutput($0) }

                    guard UIDevice.current.userInterfaceIdiom == .phone else {
                        throw RecorderError.unsupportedDevice
                    }

                    guard
                        let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                            ?? AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back)
                            ?? AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
                            ?? AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back)
                            ?? AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back)
                    else {
                        throw RecorderError.missingVideoDevice
                    }

                    let audioDevice = AVCaptureDevice.default(for: .audio)
                    guard let audioDevice else {
                        throw RecorderError.missingAudioDevice
                    }

                    let videoInput = try AVCaptureDeviceInput(device: videoDevice)
                    let audioInput = try AVCaptureDeviceInput(device: audioDevice)

                    guard self.session.canAddInput(videoInput), self.session.canAddInput(audioInput) else {
                        throw RecorderError.cannotAddInput
                    }

                    self.session.addInput(videoInput)
                    self.session.addInput(audioInput)

                    self.videoDataOutput.alwaysDiscardsLateVideoFrames = true
                    self.videoDataOutput.setSampleBufferDelegate(self, queue: self.writerQueue)
                    self.audioDataOutput.setSampleBufferDelegate(self, queue: self.writerQueue)

                    guard
                        self.session.canAddOutput(self.videoDataOutput),
                        self.session.canAddOutput(self.audioDataOutput)
                    else {
                        throw RecorderError.cannotAddOutput
                    }

                    self.session.addOutput(self.videoDataOutput)
                    self.session.addOutput(self.audioDataOutput)

                    try self.configure(
                        device: videoDevice,
                        startZoom: self.selectedStartZoom.factor,
                        endZoom: self.selectedEndZoom.factor
                    )
                    self.videoDevice = videoDevice
                    self.applyPreferredVideoEncoding()
                    self.applyStabilizationMode(self.selectedStabilizationMode)

                    Task { @MainActor in
                        self.isConfigured = true
                        self.activePhysicalCameraTitle = "Main camera"
                        self.statusText = "Ready for 4K 60 fps capture"
                        self.focusModeState = .auto
                        self.focusStatusText = "Continuous autofocus"
                    }

                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func switchToCamera(
        _ camera: PhysicalCamera,
        startZoom: CGFloat,
        endZoom: CGFloat,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        sessionQueue.async {
            do {
                if self.videoDevice?.deviceType == camera.deviceType {
                    guard let videoDevice = self.videoDevice,
                          endZoom <= videoDevice.activeFormat.videoMaxZoomFactor else {
                        throw RecorderError.unsupportedDevice
                    }
                    try self.setZoom(startZoom, cancelExistingRamp: true)
                    completion(.success(()))
                    return
                }

                guard let newDevice = AVCaptureDevice.default(
                    camera.deviceType,
                    for: .video,
                    position: .back
                ) else {
                    throw RecorderError.missingRequestedCamera(camera.title)
                }

                try self.configure(device: newDevice, startZoom: startZoom, endZoom: endZoom)
                let newInput = try AVCaptureDeviceInput(device: newDevice)
                let oldInput = self.session.inputs
                    .compactMap { $0 as? AVCaptureDeviceInput }
                    .first { $0.device.hasMediaType(.video) }

                self.session.beginConfiguration()
                if let oldInput {
                    self.session.removeInput(oldInput)
                }

                guard self.session.canAddInput(newInput) else {
                    if let oldInput, self.session.canAddInput(oldInput) {
                        self.session.addInput(oldInput)
                    }
                    self.session.commitConfiguration()
                    throw RecorderError.cannotAddInput
                }

                self.session.addInput(newInput)
                self.session.commitConfiguration()
                self.videoDevice = newDevice
                self.applyPreferredVideoEncoding()
                self.applyStabilizationMode(self.selectedStabilizationMode)
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    private func configure(
        device: AVCaptureDevice?,
        startZoom: CGFloat,
        endZoom: CGFloat
    ) throws {
        guard let device else {
            throw RecorderError.missingVideoDevice
        }

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        guard let format = best4K60Format(for: device) else {
            throw RecorderError.unsupportedFormat
        }

        device.activeFormat = format
        device.activeVideoMinFrameDuration = Constants.frameDuration
        device.activeVideoMaxFrameDuration = Constants.frameDuration
        device.videoZoomFactor = startZoom
        configureDefaultFocus(for: device)

        guard device.activeFormat.videoMaxZoomFactor >= endZoom else {
            throw RecorderError.unsupportedDevice
        }
    }

    private func best4K60Format(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        device.formats.first { format in
            let description = format.formatDescription
            let dimensions = CMVideoFormatDescriptionGetDimensions(description)
            let frameRates = format.videoSupportedFrameRateRanges

            return dimensions.width == Int32(Constants.videoSize.width)
                && dimensions.height == Int32(Constants.videoSize.height)
                && frameRates.contains { $0.maxFrameRate >= 60 }
        }
    }

    private func applyStabilizationMode(_ requestedMode: StabilizationModeOption) {
        let availableModes = availableStabilizationModes()
        let resolvedMode = availableModes.contains(requestedMode)
            ? requestedMode
            : (availableModes.contains(.auto) ? .auto : .off)

        if let connection = videoDataOutput.connection(with: .video),
           let avMode = resolvedMode.avMode,
           connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = avMode
        }

        let activeText = activeStabilizationDescription(for: resolvedMode)

        Task { @MainActor in
            self.supportedStabilizationModes = availableModes
            self.selectedStabilizationMode = resolvedMode
            self.activeStabilizationStatusText = activeText
        }
    }

    private func applyPreferredVideoEncoding() {
        let availableEncodings = availableVideoEncodingOptions()
        let preferredEncoding = availableEncodings.contains(.hevc)
            ? .hevc
            : (availableEncodings.first ?? .h264)
        let resolvedEncoding = availableEncodings.contains(selectedVideoEncoding)
            ? selectedVideoEncoding
            : preferredEncoding

        applyVideoEncoding(resolvedEncoding, availableEncodings: availableEncodings)
    }

    private func applyVideoEncoding(
        _ requestedEncoding: VideoEncodingOption,
        availableEncodings: [VideoEncodingOption]? = nil
    ) {
        let resolvedAvailableEncodings = availableEncodings ?? availableVideoEncodingOptions()
        let resolvedEncoding = resolvedAvailableEncodings.contains(requestedEncoding)
            ? requestedEncoding
            : (resolvedAvailableEncodings.contains(.hevc) ? .hevc : (resolvedAvailableEncodings.first ?? .h264))

        Task { @MainActor in
            self.availableVideoEncodings = resolvedAvailableEncodings
            self.selectedVideoEncoding = resolvedEncoding
        }
    }

    private func availableVideoEncodingOptions() -> [VideoEncodingOption] {
        let availableEncodings = VideoEncodingOption.allCases.filter { encoding in
            let outputSettings = videoOutputSettings(for: encoding)
            return canApplyVideoOutputSettings(outputSettings)
        }

        return availableEncodings.isEmpty ? [.hevc, .h264] : availableEncodings
    }

    private func availableStabilizationModes() -> [StabilizationModeOption] {
        guard
            let videoDevice,
            let connection = videoDataOutput.connection(with: .video),
            connection.isVideoStabilizationSupported
        else {
            return [.off]
        }

        let activeFormat = videoDevice.activeFormat
        var modes: [StabilizationModeOption] = [.auto, .off]

        if activeFormat.isVideoStabilizationModeSupported(.standard) {
            modes.append(.standard)
        }
        if activeFormat.isVideoStabilizationModeSupported(.cinematic) {
            modes.append(.cinematic)
        }
        if activeFormat.isVideoStabilizationModeSupported(.cinematicExtended) {
            modes.append(.cinematicExtended)
        }
        if #available(iOS 17.0, *),
           activeFormat.isVideoStabilizationModeSupported(.previewOptimized) {
            modes.append(.previewOptimized)
        }
        if #available(iOS 18.0, *),
           activeFormat.isVideoStabilizationModeSupported(.cinematicExtendedEnhanced) {
            modes.append(.cinematicExtendedEnhanced)
        }

        return modes
    }

    private func activeStabilizationDescription(for preferredMode: StabilizationModeOption) -> String {
        guard let connection = videoDataOutput.connection(with: .video) else {
            return "Stabilization connection unavailable"
        }

        guard connection.isVideoStabilizationSupported else {
            return "Stabilization unavailable for this capture path"
        }

        let activeMode = StabilizationModeOption.from(connection.activeVideoStabilizationMode)

        if activeMode == .off && preferredMode != .off {
            return "Stabilization requested: \(preferredMode.title), active: Off"
        }

        return "Stabilization active: \(activeMode.title)"
    }

    private func videoOutputSettings(for encoding: VideoEncodingOption) -> [String: Any] {
        [
            AVVideoCodecKey: encoding.codecType,
            AVVideoWidthKey: Int(Constants.videoSize.width),
            AVVideoHeightKey: Int(Constants.videoSize.height)
        ]
    }

    private func audioOutputSettings() -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 192_000
        ]
    }

    private func canApplyVideoOutputSettings(_ outputSettings: [String: Any]) -> Bool {
        let probeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        defer { try? FileManager.default.removeItem(at: probeURL) }

        do {
            let writer = try AVAssetWriter(outputURL: probeURL, fileType: .mov)
            return writer.canApply(outputSettings: outputSettings, forMediaType: .video)
        } catch {
            return false
        }
    }

    private func beginRecording(to outputURL: URL) {
        do {
            if programmedFocusLockEnabled {
                try lockCurrentFocusConfiguration(useStoredLensPosition: true)
            }

            let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
            let videoInput = AVAssetWriterInput(
                mediaType: .video,
                outputSettings: videoOutputSettings(for: selectedVideoEncoding)
            )
            let audioInput = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: audioOutputSettings()
            )

            videoInput.expectsMediaDataInRealTime = true
            audioInput.expectsMediaDataInRealTime = true
            videoInput.transform = transform(for: currentVideoOrientation)

            guard writer.canAdd(videoInput), writer.canAdd(audioInput) else {
                throw RecorderError.cannotAddOutput
            }

            writer.add(videoInput)
            writer.add(audioInput)

            assetWriter = writer
            videoWriterInput = videoInput
            audioWriterInput = audioInput
            recordingOutputURL = outputURL
            writerIsPrepared = true
            writerHasStartedSession = false
            isFinishingRecording = false
            recordingStartTime = nil
            plannedRecordingEndTime = nil
            hasReachedPlannedEndTime = false
            shouldStopAppendingSamples = false
            programmedFinalHoldStartTime = nil
            readyVideoFrameCountBeforeStart = 0
        } catch {
            Task { @MainActor in
                self.isPreparingRecordingStart = false
                self.statusText = "Recording failed"
                self.alertMessage = error.localizedDescription
            }
        }
    }

    private func finishRecording() {
        guard !isFinishingRecording else { return }

        cancelRecordingTimer()
        cancelPendingRecordingStart()
        isFinishingRecording = true
        let writer = assetWriter
        let videoInput = videoWriterInput
        let audioInput = audioWriterInput
        let outputURL = recordingOutputURL
        let hadStartedSession = writerHasStartedSession
        let finalRecordingStopTime = recordingStopTime

        if hadStartedSession, let writer, let finalRecordingStopTime {
            writer.endSession(atSourceTime: finalRecordingStopTime)
        }

        videoInput?.markAsFinished()
        audioInput?.markAsFinished()

        assetWriter = nil
        videoWriterInput = nil
        audioWriterInput = nil
        recordingOutputURL = nil
        writerIsPrepared = false
        writerHasStartedSession = false
        recordingStartTime = nil
        plannedRecordingEndTime = nil
        hasReachedPlannedEndTime = false
        shouldStopAppendingSamples = false
        recordingStopTime = nil
        programmedFinalHoldStartTime = nil
        programmedFocusLockEnabled = false
        readyVideoFrameCountBeforeStart = 0

        Task { @MainActor in
            self.isZoomRampActive = false
            self.recordingStageTimers = RecordingStageTimers()
        }

        guard let writer, let outputURL else {
            Task { @MainActor in
                self.isRecording = false
                self.isPreparingRecordingStart = false
                self.recordingStartedAt = nil
                self.statusText = "Recording failed"
            }
            return
        }

        let finalize: () -> Void = {
            writer.finishWriting {
                Task { @MainActor in
                    self.isRecording = false
                    self.isPreparingRecordingStart = false
                    self.updateRecordingDurationText()
                    self.recordingStartedAt = nil
                    self.isFinishingRecording = false

                    if let error = writer.error {
                        self.statusText = "Recording failed"
                        self.alertMessage = error.localizedDescription
                        return
                    }

                    self.persistVideoToPhotos(from: outputURL)
                }
            }
        }

        if hadStartedSession {
            finalize()
        } else {
            writer.cancelWriting()
            Task { @MainActor in
                self.isRecording = false
                self.isPreparingRecordingStart = false
                self.recordingStartedAt = nil
                self.recordingDurationText = "00:00"
                self.statusText = "Recording start cancelled"
                self.isFinishingRecording = false
            }
        }
    }

    private func transform(for orientation: AVCaptureVideoOrientation) -> CGAffineTransform {
        switch orientation {
        case .portrait:
            return CGAffineTransform(rotationAngle: .pi / 2)
        case .portraitUpsideDown:
            return CGAffineTransform(rotationAngle: -.pi / 2)
        case .landscapeLeft:
            return CGAffineTransform(rotationAngle: .pi)
        case .landscapeRight:
            return .identity
        @unknown default:
            return .identity
        }
    }

    private func cancelPendingRecordingStart() {
        pendingRecordingStartWorkItem?.cancel()
        pendingRecordingStartWorkItem = nil
    }

    private func scheduleRecordingStartWhenZoomReady(
        to outputURL: URL,
        targetZoomFactor: CGFloat,
        deadline: Date
    ) {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.isPreparingRecordingStart, !self.isRecording else {
                self.pendingRecordingStartWorkItem = nil
                return
            }

            if self.isZoomReady(for: targetZoomFactor) {
                self.pendingRecordingStartWorkItem = nil
                self.scheduleConfirmedRecordingStart(to: outputURL, targetZoomFactor: targetZoomFactor)
                return
            }

            if Date() >= deadline {
                self.pendingRecordingStartWorkItem = nil
                self.beginRecording(to: outputURL)
                return
            }

            self.scheduleRecordingStartWhenZoomReady(
                to: outputURL,
                targetZoomFactor: targetZoomFactor,
                deadline: deadline
            )
        }

        pendingRecordingStartWorkItem = workItem
        sessionQueue.asyncAfter(deadline: .now() + Constants.zoomSettleDelay, execute: workItem)
    }

    private func scheduleConfirmedRecordingStart(
        to outputURL: URL,
        targetZoomFactor: CGFloat
    ) {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.isPreparingRecordingStart, !self.isRecording else {
                self.pendingRecordingStartWorkItem = nil
                return
            }

            self.pendingRecordingStartWorkItem = nil

            guard self.isZoomReady(for: targetZoomFactor) else {
                self.scheduleRecordingStartWhenZoomReady(
                    to: outputURL,
                    targetZoomFactor: targetZoomFactor,
                    deadline: Date().addingTimeInterval(Constants.zoomSettleTimeout)
                )
                return
            }

            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                guard self.isPreparingRecordingStart, !self.isRecording else {
                    self.pendingRecordingStartWorkItem = nil
                    return
                }

                self.pendingRecordingStartWorkItem = nil
                self.beginRecording(to: outputURL)
            }

            self.pendingRecordingStartWorkItem = workItem
            self.sessionQueue.asyncAfter(
                deadline: .now() + Constants.recordingStartDelayAfterZoomReady,
                execute: workItem
            )
        }

        pendingRecordingStartWorkItem = workItem
        sessionQueue.asyncAfter(
            deadline: .now() + Constants.zoomSettleConfirmationDelay,
            execute: workItem
        )
    }

    private func startRecordingTimer() {
        cancelRecordingTimer()

        recordingTimerTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                await MainActor.run {
                    self.updateRecordingDurationText()
                }

                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
            }
        }
    }

    private func cancelRecordingTimer() {
        recordingTimerTask?.cancel()
        recordingTimerTask = nil
    }

    private func updateRecordingDurationText() {
        guard let recordingStartedAt else {
            recordingDurationText = "00:00"
            return
        }

        let elapsed = max(0, Int(Date().timeIntervalSince(recordingStartedAt)))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        recordingDurationText = String(format: "%02d:%02d", minutes, seconds)
    }

    private func isZoomReady(for targetFactor: CGFloat) -> Bool {
        guard let videoDevice else { return true }

        let currentFactor = videoDevice.videoZoomFactor
        return !videoDevice.isRampingVideoZoom
            && abs(currentFactor - targetFactor) <= Constants.zoomTolerance
    }

    private func plannedRecordingDuration() -> CMTime {
        CMTime(
            seconds: programmedInitialHoldDuration
                + programmedRampDuration
                + programmedFinalHoldDuration,
            preferredTimescale: 600
        )
    }

    private func finalHoldDuration() -> CMTime {
        CMTime(seconds: programmedFinalHoldDuration, preferredTimescale: 600)
    }

    private func setZoom(_ factor: CGFloat, cancelExistingRamp: Bool) throws {
        guard let videoDevice else {
            throw RecorderError.configurationFailed
        }

        try videoDevice.lockForConfiguration()
        if cancelExistingRamp, videoDevice.isRampingVideoZoom {
            videoDevice.cancelVideoZoomRamp()
        }
        videoDevice.videoZoomFactor = min(max(factor, 1.0), videoDevice.activeFormat.videoMaxZoomFactor)

        if programmedFocusLockEnabled,
           videoDevice.isFocusModeSupported(.locked),
           let lockedFocusLensPosition,
           videoDevice.focusMode != .locked
            || abs(videoDevice.lensPosition - lockedFocusLensPosition) > 0.0005 {
            videoDevice.setFocusModeLocked(
                lensPosition: lockedFocusLensPosition,
                completionHandler: nil
            )
        }
        videoDevice.unlockForConfiguration()
    }

    private func applyProgramZoomState(at presentationTime: CMTime) {
        guard let recordingStartTime else { return }

        updateCameraLensValues()

        let elapsed = CMTimeGetSeconds(CMTimeSubtract(presentationTime, recordingStartTime))
        guard elapsed.isFinite else { return }

        if elapsed < programmedInitialHoldDuration {
            updateZoomRampActivity(false)
            updateRecordingStageTimers(
                initialHold: max(0, elapsed),
                zoom: 0,
                finalHold: 0,
                activeStage: .initialHold
            )
            try? setZoom(programmedStartZoomFactor, cancelExistingRamp: true)
            return
        }

        let rampElapsed = elapsed - programmedInitialHoldDuration
        if rampElapsed < programmedRampDuration {
            updateZoomRampActivity(true)
            updateRecordingStageTimers(
                initialHold: programmedInitialHoldDuration,
                zoom: max(0, rampElapsed),
                finalHold: 0,
                activeStage: .zoom
            )
            let progress = max(0, min(rampElapsed / programmedRampDuration, 1))
            let zoomProgress: CGFloat
            if usesCosineZoomRamp {
                zoomProgress = (1 - cos(.pi * progress)) / 2
            } else if usesLinearZoomRamp {
                zoomProgress = progress
            } else {
                zoomProgress = progress * progress * (3 - (2 * progress))
            }
            let interpolatedZoom = programmedStartZoomFactor
                + ((programmedEndZoomFactor - programmedStartZoomFactor) * zoomProgress)
            try? setZoom(interpolatedZoom, cancelExistingRamp: false)
            return
        }

        updateZoomRampActivity(false)
        updateRecordingStageTimers(
            initialHold: programmedInitialHoldDuration,
            zoom: programmedRampDuration,
            finalHold: min(
                max(0, rampElapsed - programmedRampDuration),
                programmedFinalHoldDuration
            ),
            activeStage: .finalHold
        )
        try? setZoom(programmedEndZoomFactor, cancelExistingRamp: true)

        if programmedFinalHoldStartTime == nil {
            programmedFinalHoldStartTime = presentationTime

            let guaranteedFinalHoldEndTime = CMTimeAdd(presentationTime, finalHoldDuration())
            if let existingPlannedEndTime = plannedRecordingEndTime {
                plannedRecordingEndTime = CMTimeMaximum(existingPlannedEndTime, guaranteedFinalHoldEndTime)
            } else {
                plannedRecordingEndTime = guaranteedFinalHoldEndTime
            }
        }
    }

    private func updateZoomRampActivity(_ isActive: Bool) {
        guard isZoomRampActive != isActive else { return }

        Task { @MainActor in
            self.isZoomRampActive = isActive
        }
    }

    private func updateRecordingStageTimers(
        initialHold: TimeInterval,
        zoom: TimeInterval,
        finalHold: TimeInterval,
        activeStage: RecordingProgramStage
    ) {
        let timers = RecordingStageTimers(
            initialHold: initialHold,
            zoom: zoom,
            finalHold: finalHold,
            activeStage: activeStage
        )

        Task { @MainActor in
            self.recordingStageTimers = timers
        }
    }

    private func updateCameraLensValues() {
        guard let videoDevice else { return }
        let lensPosition = videoDevice.lensPosition
        let lensAperture = videoDevice.lensAperture

        Task { @MainActor in
            self.focusLensPosition = lensPosition
            self.lensAperture = lensAperture
        }
    }

    private func enableContinuousAutoFocus() {
        sessionQueue.async {
            guard let videoDevice = self.videoDevice else { return }

            do {
                self.programmedFocusLockEnabled = false
                try videoDevice.lockForConfiguration()
                self.configureDefaultFocus(for: videoDevice)
                videoDevice.unlockForConfiguration()

                Task { @MainActor in
                    self.focusModeState = .auto
                    self.focusStatusText = "Continuous autofocus"
                }
            } catch {
                Task { @MainActor in
                    self.alertMessage = error.localizedDescription
                }
            }
        }
    }

    private func lockCurrentFocus() {
        sessionQueue.async {
            do {
                try self.lockCurrentFocusConfiguration()
                self.programmedFocusLockEnabled = self.isRecording || self.isPreparingRecordingStart

                Task { @MainActor in
                    self.focusModeState = .locked
                    self.focusStatusText = "Focus and exposure locked"
                }
            } catch {
                Task { @MainActor in
                    self.alertMessage = error.localizedDescription
                }
            }
        }
    }

    private func applyFocus(at devicePoint: CGPoint, keepFocusLocked: Bool) throws {
        guard let videoDevice else {
            throw RecorderError.configurationFailed
        }

        try videoDevice.lockForConfiguration()

        if videoDevice.isFocusPointOfInterestSupported {
            videoDevice.focusPointOfInterest = devicePoint
        }
        if videoDevice.isFocusModeSupported(.autoFocus) {
            videoDevice.focusMode = .autoFocus
        } else if videoDevice.isFocusModeSupported(.continuousAutoFocus) {
            videoDevice.focusMode = .continuousAutoFocus
        }

        if videoDevice.isExposurePointOfInterestSupported {
            videoDevice.exposurePointOfInterest = devicePoint
        }
        if videoDevice.isExposureModeSupported(.autoExpose) {
            videoDevice.exposureMode = .autoExpose
        } else if videoDevice.isExposureModeSupported(.continuousAutoExposure) {
            videoDevice.exposureMode = .continuousAutoExposure
        }

        videoDevice.isSubjectAreaChangeMonitoringEnabled = !keepFocusLocked
        videoDevice.unlockForConfiguration()

        guard keepFocusLocked else { return }

        sessionQueue.asyncAfter(deadline: .now() + 0.35) {
            do {
                try self.lockCurrentFocusConfiguration()
            } catch {
                Task { @MainActor in
                    self.alertMessage = error.localizedDescription
                }
            }
        }
    }

    private func configureDefaultFocus(for device: AVCaptureDevice) {
        lockedFocusLensPosition = nil

        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        } else if device.isFocusModeSupported(.autoFocus) {
            device.focusMode = .autoFocus
        }

        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        } else if device.isExposureModeSupported(.autoExpose) {
            device.exposureMode = .autoExpose
        }

        if device.isSmoothAutoFocusSupported {
            device.isSmoothAutoFocusEnabled = true
        }

        device.isSubjectAreaChangeMonitoringEnabled = true
    }

    private func lockCurrentFocusConfiguration(useStoredLensPosition: Bool = false) throws {
        guard let videoDevice else {
            throw RecorderError.configurationFailed
        }

        try videoDevice.lockForConfiguration()
        defer { videoDevice.unlockForConfiguration() }

        if videoDevice.isFocusModeSupported(.locked) {
            let lensPosition = useStoredLensPosition
                ? (lockedFocusLensPosition ?? videoDevice.lensPosition)
                : videoDevice.lensPosition
            lockedFocusLensPosition = lensPosition
            videoDevice.setFocusModeLocked(
                lensPosition: lensPosition,
                completionHandler: nil
            )
        }

        if videoDevice.isExposureModeSupported(.locked) {
            videoDevice.exposureMode = .locked
        }

        videoDevice.isSubjectAreaChangeMonitoringEnabled = false
    }

    private func persistVideoToPhotos(from url: URL) {
        refreshRecordedVideoDetails(from: url)

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard let self else { return }

            guard status == .authorized || status == .limited else {
                Task { @MainActor in
                    self.statusText = "Recorded. Photos access not granted."
                    self.recordedVideoURL = url
                }
                return
            }

            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { success, error in
                Task { @MainActor in
                    self.recordedVideoURL = url
                    if success {
                        self.statusText = "Recorded and saved to Photos"
                    } else {
                        self.statusText = "Recorded, but saving to Photos failed"
                        self.alertMessage = error?.localizedDescription
                    }
                }
            }
        }
    }

    private func refreshRecordedVideoDetails(from url: URL) {
        let details = recordedVideoDetailsText(for: url)

        Task { @MainActor in
            self.recordedVideoDetailsText = details
        }
    }

    private func recordedVideoDetailsText(for url: URL) -> String {
        let fileSize = formattedFileSize(for: url)
        let duration = formattedVideoDuration(for: url)
        let codec = detectedCodecTitle(for: url)

        return "\(fileSize) • \(duration) • \(codec)"
    }

    private func formattedFileSize(for url: URL) -> String {
        let byteCountFormatter = ByteCountFormatter()
        byteCountFormatter.allowedUnits = [.useKB, .useMB, .useGB]
        byteCountFormatter.countStyle = .file

        guard
            let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey]),
            let fileSize = resourceValues.fileSize
        else {
            return "Unknown size"
        }

        return byteCountFormatter.string(fromByteCount: Int64(fileSize))
    }

    private func formattedVideoDuration(for url: URL) -> String {
        let asset = AVURLAsset(url: url)
        let seconds = CMTimeGetSeconds(asset.duration)

        guard seconds.isFinite, seconds >= 0 else {
            return "Unknown length"
        }

        let totalSeconds = Int(seconds.rounded())
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60

        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    private func detectedCodecTitle(for url: URL) -> String {
        let asset = AVURLAsset(url: url)
        guard
            let track = asset.tracks(withMediaType: .video).first,
            let formatDescription = track.formatDescriptions.first
        else {
            return "Unknown codec"
        }

        let mediaSubType = CMFormatDescriptionGetMediaSubType(formatDescription as! CMFormatDescription)

        switch mediaSubType {
        case kCMVideoCodecType_HEVC:
            return "HEVC"
        case kCMVideoCodecType_H264:
            return "H.264"
        case kCMVideoCodecType_AppleProRes422:
            return "ProRes 422"
        case kCMVideoCodecType_AppleProRes422HQ:
            return "ProRes 422 HQ"
        case kCMVideoCodecType_AppleProRes422LT:
            return "ProRes 422 LT"
        case kCMVideoCodecType_AppleProRes422Proxy:
            return "ProRes 422 Proxy"
        case kCMVideoCodecType_AppleProRes4444:
            return "ProRes 4444"
        case kCMVideoCodecType_AppleProRes4444XQ:
            return "ProRes 4444 XQ"
        default:
            return "Codec \(fourCharCode(mediaSubType))"
        }
    }

    private func fourCharCode(_ value: FourCharCode) -> String {
        let scalar1 = UnicodeScalar((value >> 24) & 255)
        let scalar2 = UnicodeScalar((value >> 16) & 255)
        let scalar3 = UnicodeScalar((value >> 8) & 255)
        let scalar4 = UnicodeScalar(value & 255)

        guard
            let scalar1,
            let scalar2,
            let scalar3,
            let scalar4
        else {
            return String(value)
        }

        return String(String.UnicodeScalarView([scalar1, scalar2, scalar3, scalar4]))
    }
}

extension AVCaptureVideoOrientation {
    init?(_ interfaceOrientation: UIInterfaceOrientation) {
        switch interfaceOrientation {
        case .portrait:
            self = .portrait
        case .portraitUpsideDown:
            self = .portraitUpsideDown
        case .landscapeLeft:
            self = .landscapeLeft
        case .landscapeRight:
            self = .landscapeRight
        default:
            return nil
        }
    }
}

extension CameraRecorder: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        var shouldFinishAfterAppend = false

        guard self.writerIsPrepared, !self.isFinishingRecording else { return }
        guard let writer = self.assetWriter else { return }

        if !self.writerHasStartedSession, output == self.videoDataOutput {
            if !self.isZoomReady(for: self.programmedStartZoomFactor) {
                self.readyVideoFrameCountBeforeStart = 0
                return
            }

            self.readyVideoFrameCountBeforeStart += 1
            if self.readyVideoFrameCountBeforeStart < Constants.recordingStartReadyFrameCount {
                return
            }

            if writer.status == .unknown {
                if !writer.startWriting() {
                    Task { @MainActor in
                        self.isPreparingRecordingStart = false
                        self.statusText = "Recording failed"
                        self.alertMessage = writer.error?.localizedDescription
                    }
                    return
                }
            }

            writer.startSession(atSourceTime: presentationTime)
            self.writerHasStartedSession = true
            self.recordingStartTime = presentationTime
            self.plannedRecordingEndTime = CMTimeAdd(presentationTime, self.plannedRecordingDuration())
            self.hasReachedPlannedEndTime = false
            self.recordingStopTime = nil
            self.programmedFinalHoldStartTime = nil
            self.readyVideoFrameCountBeforeStart = 0

            Task { @MainActor in
                self.isPreparingRecordingStart = false
                self.isRecording = true
                self.recordingStartedAt = Date()
                self.recordingDurationText = "00:00"
                self.statusText = "Recording at \(self.programmedStartZoomTitle)"
                self.startRecordingTimer()
            }
        }

        guard self.writerHasStartedSession else { return }
        if self.shouldStopAppendingSamples {
            return
        }
        if output == self.videoDataOutput {
            self.applyProgramZoomState(at: presentationTime)
        }
        if let plannedRecordingEndTime = self.plannedRecordingEndTime {
            if output == self.audioDataOutput, presentationTime > plannedRecordingEndTime {
                return
            }

            if output == self.videoDataOutput, presentationTime > plannedRecordingEndTime {
                if !self.hasReachedPlannedEndTime {
                    self.hasReachedPlannedEndTime = true
                    self.shouldStopAppendingSamples = true
                    self.recordingStopTime = presentationTime
                    shouldFinishAfterAppend = true
                }
            }
        }

        let input: AVAssetWriterInput?
        if output == self.videoDataOutput {
            input = self.videoWriterInput
        } else if output == self.audioDataOutput {
            input = self.audioWriterInput
        } else {
            input = nil
        }

        guard let input, input.isReadyForMoreMediaData else { return }
        _ = input.append(sampleBuffer)

        guard shouldFinishAfterAppend else { return }

        Task { @MainActor in
            self.statusText = "Finishing recording"
        }
        self.sessionQueue.async {
            self.finishRecording()
        }
    }
}
