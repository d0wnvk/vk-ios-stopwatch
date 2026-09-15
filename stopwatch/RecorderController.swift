import AVFoundation
import AudioToolbox
import Combine
import DockKit
import Photos
import Spatial
import SwiftUI
import UIKit

/// Owns the camera and Insta360 DockKit recording workflow.
@MainActor
final class RecorderController: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published private(set) var status = "Preparing camera…"
    @Published private(set) var gimbalConnected = false
    @Published private(set) var iPhoneBatteryLevel: Int?
    @Published private(set) var gimbalBatteryLevel: Int?
    @Published private(set) var gimbalIsCharging = false
    @Published private(set) var isRecording = false
    @Published private(set) var isReturningGimbal = false
    @Published private(set) var recordingElapsed: TimeInterval = 0
    @Published private(set) var currentZoom: CGFloat = 1.0
    @Published private(set) var recordOneEndZoom: CGFloat = 2.0
    @Published private(set) var recordOneEndOrientation: Vector3D?
    @Published private(set) var lastRecordingURL: URL?

    var canRecord: Bool {
        cameraReady && gimbalConnected && !isRecording && !isReturningGimbal
    }
    var canAdjustZoom: Bool { cameraReady && !isRecording && !isReturningGimbal }
    var canSetRecordOneEndpoint: Bool { canAdjustZoom && gimbalConnected }

    private let movieOutput = AVCaptureMovieFileOutput()
    private var camera: AVCaptureDevice?
    private var accessory: DockAccessory?
    private var cameraReady = false
    private var stateTask: Task<Void, Never>?
    private var iPhoneBatteryTask: Task<Void, Never>?
    private var gimbalBatteryTask: Task<Void, Never>?
    private var recordingTimerTask: Task<Void, Never>?
    private var recordingSequenceTask: Task<Void, Never>?
    private var activeStartingOrientation: Vector3D?
    private var pendingRecordingFailure: String?

    private let endZoom: CGFloat = 4.9
    private let verticalStep = 15.0
    private let verticalStepDuration: TimeInterval = 3
    private let secondVerticalStepDuration: TimeInterval = 6
    private let zoomEasingStrength = 2.0
    private var recordingStartContinuation: CheckedContinuation<Void, Error>?

    override init() {
        super.init()
        let savedRecording = Self.savedRecordingURL
        if FileManager.default.fileExists(atPath: savedRecording.path) {
            lastRecordingURL = savedRecording
        }
    }

    private static var savedRecordingURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("last-recording.mov")
    }

    func start() async {
        guard stateTask == nil else { return }
        observeIPhoneBattery()
        observeDock()

        let authorized = await requestPermissions()
        guard authorized else {
            status = "Camera, microphone, and Photos permissions are required."
            return
        }

        do {
            try configureCamera()
            session.startRunning()
            cameraReady = true
            status = gimbalConnected
                ? "Ready — tap Record."
                : "Connect and dock the Insta360 Flow 2 Pro."
        } catch {
            status = error.localizedDescription
        }
    }

    func stop() {
        stateTask?.cancel()
        stateTask = nil
        iPhoneBatteryTask?.cancel()
        iPhoneBatteryTask = nil
        gimbalBatteryTask?.cancel()
        gimbalBatteryTask = nil
        accessory = nil
        gimbalConnected = false
        gimbalBatteryLevel = nil
        gimbalIsCharging = false

        if session.isRunning {
            session.stopRunning()
        }
        cameraReady = false
        status = "Recorder closed."
    }

    func record() {
        guard canRecord, let accessory, let camera else { return }
        pendingRecordingFailure = nil
        isRecording = true
        status = "Preparing Record 1…"

        recordingSequenceTask = Task {
            await performRecording(accessory: accessory, camera: camera)
            recordingSequenceTask = nil
        }
    }

    func recordVerticalZoomOut() {
        guard canRecord, let accessory, let camera else { return }
        pendingRecordingFailure = nil
        isRecording = true
        status = "Preparing vertical shot…"

        recordingSequenceTask = Task {
            await performVerticalZoomOutRecording(accessory: accessory, camera: camera)
            recordingSequenceTask = nil
        }
    }

    func cancelRecording() {
        guard isRecording else { return }
        status = "Stopping recording…"
        recordingSequenceTask?.cancel()
        if let camera, (try? camera.lockForConfiguration()) != nil {
            camera.cancelVideoZoomRamp()
            camera.unlockForConfiguration()
        }
        if movieOutput.isRecording { movieOutput.stopRecording() }

        guard let accessory, let startingOrientation = activeStartingOrientation else { return }
        activeStartingOrientation = nil
        isReturningGimbal = true
        Task {
            do {
                _ = try await accessory.setOrientation(
                    startingOrientation,
                    duration: .seconds(3),
                    relative: false
                )
                status = "Recording stopped. Gimbal returned to its starting position."
            } catch {
                status = "Recording stopped, but returning the gimbal failed: \(error.localizedDescription)"
            }
            isReturningGimbal = false
        }
    }

    func rememberRecordOneEndpoint() async {
        guard canSetRecordOneEndpoint, let accessory else { return }
        do {
            let orientation = try await currentOrientation(of: accessory)
            recordOneEndZoom = currentZoom
            recordOneEndOrientation = orientation
            status = String(
                format: "Record 1 endpoint saved at %.1f× zoom and the current gimbal position.",
                recordOneEndZoom
            )
        } catch {
            status = "The gimbal endpoint could not be saved: \(error.localizedDescription)"
        }
    }

    func setZoom(_ requestedZoom: CGFloat) {
        guard canAdjustZoom, let camera else { return }
        let target = min(
            max(requestedZoom, camera.minAvailableVideoZoomFactor),
            camera.maxAvailableVideoZoomFactor
        )

        do {
            try camera.lockForConfiguration()
            camera.cancelVideoZoomRamp()
            camera.videoZoomFactor = target
            camera.unlockForConfiguration()
            currentZoom = target
        } catch {
            status = "Zoom failed: \(error.localizedDescription)"
        }
    }

    private func performRecording(accessory: DockAccessory, camera: AVCaptureDevice) async {
        do {
            try await DockAccessoryManager.shared.setSystemTrackingEnabled(false)
            let startingOrientation = try await currentOrientation(of: accessory)
            activeStartingOrientation = startingOrientation

            try camera.lockForConfiguration()
            camera.cancelVideoZoomRamp()
            camera.videoZoomFactor = endZoom
            camera.unlockForConfiguration()
            currentZoom = endZoom

            let url = Self.savedRecordingURL
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            updateVideoOrientation()
            try await startMovieRecording(to: url)
            status = "Recording: stationary at 4.9×"
            try await Task.sleep(for: .seconds(2))

            async let movement: Void = moveRecordOneGimbal(
                accessory: accessory,
                endpoint: recordOneEndOrientation
            )

            status = "Recording: tilting up 45°"
            try await Task.sleep(for: .seconds(2))

            status = String(format: "Recording: tilting up, 4.9× → %.1f×", recordOneEndZoom)
            try await interpolateZoom(
                camera: camera,
                from: endZoom,
                to: recordOneEndZoom,
                duration: 6
            )
            _ = try await movement

            status = String(format: "Recording: stationary at %.1f×", recordOneEndZoom)
            try await Task.sleep(for: .seconds(2))
            movieOutput.stopRecording()

            isReturningGimbal = true
            status = "Recording complete. Returning gimbal to its starting position…"
            do {
                _ = try await accessory.setOrientation(
                    startingOrientation,
                    duration: .seconds(3),
                    relative: false
                )
                status = "Saved. Gimbal returned to its starting position."
            } catch {
                status = "Recording finished, but returning the gimbal failed: \(error.localizedDescription)"
            }
            isReturningGimbal = false
            activeStartingOrientation = nil
        } catch is CancellationError {
            if movieOutput.isRecording { movieOutput.stopRecording() }
        } catch {
            isReturningGimbal = false
            pendingRecordingFailure = "Recording failed: \(error.localizedDescription)"
            if movieOutput.isRecording { movieOutput.stopRecording() }
            isRecording = false
            status = pendingRecordingFailure!
        }
    }

    private func performVerticalZoomOutRecording(accessory: DockAccessory,
                                                  camera: AVCaptureDevice) async {
        do {
            try await DockAccessoryManager.shared.setSystemTrackingEnabled(false)
            let startingOrientation = try await currentOrientation(of: accessory)
            activeStartingOrientation = startingOrientation

            try camera.lockForConfiguration()
            camera.cancelVideoZoomRamp()
            camera.videoZoomFactor = endZoom
            camera.unlockForConfiguration()
            currentZoom = endZoom

            let url = Self.savedRecordingURL
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            updateVideoOrientation()
            movieOutput.startRecording(to: url, recordingDelegate: self)
            try await Task.sleep(for: .milliseconds(150))

            status = "Recording: tilting up 15°"
            let firstTilt = Vector3D(x: verticalStep.radians, y: 0, z: 0)
            _ = try await accessory.setOrientation(
                firstTilt,
                duration: .seconds(verticalStepDuration),
                relative: true
            )

            let secondTilt = Vector3D(x: verticalStep.radians, y: 0, z: 0)
            async let secondMovement = accessory.setOrientation(
                secondTilt,
                duration: .seconds(secondVerticalStepDuration),
                relative: true
            )

            status = "Recording: tilting up another 15°, 4.9× → 2.0×"

            try await interpolateZoom(
                camera: camera,
                from: endZoom,
                to: 2.0,
                duration: secondVerticalStepDuration
            )
            _ = try await secondMovement
            movieOutput.stopRecording()

            isReturningGimbal = true
            status = "Recording complete. Returning gimbal to its starting position…"
            do {
                _ = try await accessory.setOrientation(
                    startingOrientation,
                    duration: .seconds(verticalStepDuration),
                    relative: false
                )
                status = "Saved. Gimbal returned to its starting position."
            } catch {
                status = "Recording finished, but returning the gimbal failed: \(error.localizedDescription)"
            }
            isReturningGimbal = false
            activeStartingOrientation = nil
        } catch is CancellationError {
            if movieOutput.isRecording { movieOutput.stopRecording() }
        } catch {
            isReturningGimbal = false
            pendingRecordingFailure = "Recording failed: \(error.localizedDescription)"
            if movieOutput.isRecording { movieOutput.stopRecording() }
            isRecording = false
            status = pendingRecordingFailure!
        }
    }

    private func interpolateZoom(camera: AVCaptureDevice,
                                 from startZoom: CGFloat,
                                 to targetZoom: CGFloat,
                                 duration: TimeInterval) async throws {
        let startedAt = Date()

        while true {
            let elapsed = Date().timeIntervalSince(startedAt)
            let progress = min(elapsed / duration, 1)
            let easedProgress = exponentialEaseInOut(progress)
            let zoom = startZoom + (targetZoom - startZoom) * easedProgress

            try camera.lockForConfiguration()
            camera.videoZoomFactor = zoom
            camera.unlockForConfiguration()
            currentZoom = zoom

            if progress >= 1 { return }
            try await Task.sleep(for: .milliseconds(16))
        }
    }

    private func moveRecordOneGimbal(accessory: DockAccessory,
                                     endpoint: Vector3D?) async throws {
        if let endpoint {
            _ = try await accessory.setOrientation(
                endpoint,
                duration: .seconds(8),
                relative: false
            )
        } else {
            let defaultMovement = Vector3D(x: 45.0.radians, y: 0, z: 0)
            _ = try await accessory.setOrientation(
                defaultMovement,
                duration: .seconds(8),
                relative: true
            )
        }
    }

    private func exponentialEaseInOut(_ progress: Double) -> Double {
        if progress <= 0 { return 0 }
        if progress >= 1 { return 1 }
        let normalization = pow(2, zoomEasingStrength) - 1
        let exponentialProgress: Double
        if progress < 0.5 {
            exponentialProgress = (pow(2, 2 * zoomEasingStrength * progress) - 1)
                / (2 * normalization)
        } else {
            exponentialProgress = 1
                - (pow(2, 2 * zoomEasingStrength * (1 - progress)) - 1)
                / (2 * normalization)
        }

        // Smootherstep makes velocity and acceleration reach zero at both endpoints.
        return exponentialProgress * exponentialProgress * exponentialProgress
            * (exponentialProgress * (exponentialProgress * 6 - 15) + 10)
    }

    private func currentOrientation(of accessory: DockAccessory) async throws -> Vector3D {
        let motionStates = try accessory.motionStates
        for await motionState in motionStates {
            if let error = motionState.error { throw error }
            return motionState.angularPositions
        }
        throw RecorderError.motionStateUnavailable
    }

    private func startMovieRecording(to url: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            recordingStartContinuation = continuation
            movieOutput.startRecording(to: url, recordingDelegate: self)
        }
    }

    private func updateVideoOrientation() {
        guard let orientation = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })?
            .interfaceOrientation,
              let connection = movieOutput.connection(with: .video) else { return }

        let angle = correctedVideoRotationAngle(for: orientation)
        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }

    private func observeDock() {
        stateTask = Task { [weak self] in
            do {
                for await change in try DockAccessoryManager.shared.accessoryStateChanges {
                    guard let self else { return }
                    if change.state == .docked, let dock = change.accessory {
                        let wasConnected = gimbalConnected
                        accessory = dock
                        gimbalConnected = true
                        observeGimbalBattery(dock)
                        status = "Ready — tap Record."
                        if !wasConnected {
                            AudioServicesPlaySystemSound(1057)
                        }
                    } else {
                        gimbalBatteryTask?.cancel()
                        gimbalBatteryTask = nil
                        accessory = nil
                        gimbalConnected = false
                        gimbalBatteryLevel = nil
                        gimbalIsCharging = false
                        status = "Connect and dock the Insta360 Flow 2 Pro."
                    }
                }
            } catch {
                self?.status = "DockKit failed: \(error.localizedDescription)"
            }
        }
    }

    private func observeIPhoneBattery() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        iPhoneBatteryTask?.cancel()
        iPhoneBatteryTask = Task { [weak self] in
            while !Task.isCancelled {
                let level = UIDevice.current.batteryLevel
                self?.iPhoneBatteryLevel = level >= 0 ? Int((level * 100).rounded()) : nil
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func observeGimbalBattery(_ dock: DockAccessory) {
        gimbalBatteryTask?.cancel()
        gimbalBatteryTask = Task { [weak self] in
            do {
                for await batteryState in try dock.batteryStates {
                    guard !Task.isCancelled else { return }
                    self?.gimbalBatteryLevel = Int((batteryState.batteryLevel * 100).rounded())
                    self?.gimbalIsCharging = batteryState.chargeState == .charging
                }
            } catch {
                guard !Task.isCancelled else { return }
                self?.gimbalBatteryLevel = nil
                self?.gimbalIsCharging = false
            }
        }
    }

    private func configureCamera() throws {
        guard let device = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw RecorderError.cameraUnavailable
        }

        guard let format = device.formats.first(where: { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return dimensions.width == 3840 && dimensions.height == 2160
                && format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 60 && $0.minFrameRate <= 60 }
                && format.videoMaxZoomFactor >= endZoom
        }) else {
            throw RecorderError.unsupported4K60Zoom
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .inputPriority

        let videoInput = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(videoInput) else { throw RecorderError.cannotAddInput }
        session.addInput(videoInput)

        if let microphone = AVCaptureDevice.default(for: .audio) {
            let audioInput = try AVCaptureDeviceInput(device: microphone)
            if session.canAddInput(audioInput) { session.addInput(audioInput) }
        }

        guard session.canAddOutput(movieOutput) else { throw RecorderError.cannotAddOutput }
        session.addOutput(movieOutput)

        try device.lockForConfiguration()
        device.activeFormat = format
        device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 60)
        device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 60)
        device.unlockForConfiguration()

        if let connection = movieOutput.connection(with: .video), connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = .cinematicExtended
        }
        camera = device
        currentZoom = device.videoZoomFactor
    }

    private func requestPermissions() async -> Bool {
        let cameraOK = await AVCaptureDevice.requestAccess(for: .video)
        let microphoneOK = await AVCaptureDevice.requestAccess(for: .audio)
        let photos = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        return cameraOK && microphoneOK && (photos == .authorized || photos == .limited)
    }
}

extension RecorderController: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput,
                                didStartRecordingTo fileURL: URL,
                                from connections: [AVCaptureConnection]) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            recordingStartContinuation?.resume()
            recordingStartContinuation = nil
            startRecordingTimer()
        }
    }

    nonisolated func fileOutput(_ output: AVCaptureFileOutput,
                                didFinishRecordingTo outputFileURL: URL,
                                from connections: [AVCaptureConnection],
                                error: Error?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let recordingStartContinuation {
                self.recordingStartContinuation = nil
                recordingStartContinuation.resume(
                    throwing: error ?? RecorderError.recordingDidNotStart
                )
            }
            recordingTimerTask?.cancel()
            recordingTimerTask = nil
            let workflowFailure = pendingRecordingFailure
            pendingRecordingFailure = nil
            if let error {
                status = workflowFailure ?? "Recording failed: \(error.localizedDescription)"
                isRecording = false
                return
            }

            do {
                lastRecordingURL = outputFileURL
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputFileURL)
                }
                if let workflowFailure {
                    status = "\(workflowFailure) Partial video saved to Photos."
                } else {
                    status = "Saved to Photos. Tap Library to watch it."
                }
            } catch {
                lastRecordingURL = outputFileURL
                if let workflowFailure {
                    status = "\(workflowFailure) Saving the partial video to Photos also failed: \(error.localizedDescription)"
                } else {
                    status = "Ready in Library, but saving to Photos failed: \(error.localizedDescription)"
                }
            }
            isRecording = false
        }
    }
}

private extension RecorderController {
    func startRecordingTimer() {
        recordingTimerTask?.cancel()
        recordingElapsed = 0
        let startedAt = Date()

        recordingTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.recordingElapsed = Date().timeIntervalSince(startedAt)
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }
}

private extension Double {
    var radians: Double { self * .pi / 180 }
}

private enum RecorderError: LocalizedError {
    case cameraUnavailable, unsupported4K60Zoom, cannotAddInput, cannotAddOutput
    case recordingDidNotStart
    case motionStateUnavailable

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable: return "The rear camera is unavailable."
        case .unsupported4K60Zoom: return "This camera cannot provide 4K/60 fps through the full 2.1×–4.9× zoom range."
        case .cannotAddInput: return "The camera input could not be added."
        case .cannotAddOutput: return "The movie output could not be added."
        case .recordingDidNotStart: return "Recording did not start."
        case .motionStateUnavailable: return "The gimbal position could not be measured."
        }
    }
}
