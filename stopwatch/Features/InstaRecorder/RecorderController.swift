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

    @Published var status = "Preparing camera…"
    @Published var gimbalConnected = false
    @Published var iPhoneBatteryLevel: Int?
    @Published var gimbalBatteryLevel: Int?
    @Published var gimbalIsCharging = false
    @Published var isRecording = false
    @Published var isReturningGimbal = false
    @Published var recordingElapsed: TimeInterval = 0
    @Published var currentZoom: CGFloat = 1.0
    @Published var activeCameraName = "Camera"
    @Published var recordOneEndZoom: CGFloat = 2.0
    @Published var recordOneEndOrientation: Vector3D?
    @Published var lastRecordingURL: URL?

    var canAttemptRecording: Bool { !isRecording && !isReturningGimbal }
    var canAdjustZoom: Bool { cameraReady && !isRecording && !isReturningGimbal }
    var canSetRecordOneEndpoint: Bool { canAdjustZoom && gimbalConnected }
    var displayedZoom: CGFloat {
        currentZoom * (camera?.displayVideoZoomFactorMultiplier ?? 1)
    }

    let movieOutput = AVCaptureMovieFileOutput()
    var camera: AVCaptureDevice?
    var accessory: DockAccessory?
    var cameraReady = false
    var stateTask: Task<Void, Never>?
    var iPhoneBatteryTask: Task<Void, Never>?
    var gimbalBatteryTask: Task<Void, Never>?
    var accessoryEventTask: Task<Void, Never>?
    var focusLockTask: Task<Void, Never>?
    var activeCameraObservation: NSKeyValueObservation?
    var activePhysicalCameraID: String?
    var recordingTimerTask: Task<Void, Never>?
    var recordingSequenceTask: Task<Void, Never>?
    var activeStartingOrientation: Vector3D?
    var pendingRecordingFailure: String?

    let endZoom: CGFloat = 4.9
    let verticalStep = 15.0
    let verticalStepDuration: TimeInterval = 3
    let secondVerticalStepDuration: TimeInterval = 6
    let zoomEasingStrength = 2.0
    var recordingStartContinuation: CheckedContinuation<Void, Error>?

    override init() {
        super.init()
        let savedRecording = Self.savedRecordingURL
        if FileManager.default.fileExists(atPath: savedRecording.path) {
            lastRecordingURL = savedRecording
        }
    }

    static var savedRecordingURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("last-recording.mov")
    }

    func start() async {
        guard stateTask == nil else { return }
        observeIPhoneBattery()
        observeDock()

        let cameraAuthorized = await requestCameraPermission()
        guard cameraAuthorized else {
            status = "Camera access is required. Enable it in Settings > Privacy & Security > Camera."
            return
        }

        // Audio and Photos are optional. A denied microphone permission produces a
        // silent movie, while a denied Photos permission still leaves the movie in
        // the app's Library.
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        _ = await PHPhotoLibrary.requestAuthorization(for: .addOnly)

        do {
            if camera == nil {
                try configureCamera()
            }
            if !session.isRunning {
                session.startRunning()
            }
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
        accessoryEventTask?.cancel()
        accessoryEventTask = nil
        focusLockTask?.cancel()
        focusLockTask = nil
        activeCameraObservation?.invalidate()
        activeCameraObservation = nil
        activePhysicalCameraID = nil
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
        guard canBeginRecording(), let accessory, let camera else { return }
        pendingRecordingFailure = nil
        isRecording = true
        status = "Preparing Record 1…"

        recordingSequenceTask = Task {
            await performRecording(accessory: accessory, camera: camera)
            recordingSequenceTask = nil
        }
    }

    func recordVerticalZoomOut() {
        guard canBeginRecording(), let accessory, let camera else { return }
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

    func adjustZoom(fromAccessoryFactor factor: Double) {
        let zoomStep: CGFloat = 0.2
        setZoom(currentZoom + (factor > 0 ? zoomStep : -zoomStep))
    }


    func canBeginRecording() -> Bool {
        guard !isRecording, !isReturningGimbal else { return false }
        guard cameraReady else {
            status = "The camera is not ready. Check Camera access in Settings."
            return false
        }
        guard gimbalConnected else {
            status = "Connect and dock the Insta360 Flow 2 Pro before recording."
            return false
        }
        return true
    }
}
