import AVFoundation
import AudioToolbox
import Combine
import DockKit
import Photos
import Spatial
import SwiftUI
import UIKit

extension RecorderController {
    func performRecording(accessory: DockAccessory, camera: AVCaptureDevice) async {
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

    func performVerticalZoomOutRecording(accessory: DockAccessory,
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

    func interpolateZoom(camera: AVCaptureDevice,
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

    func moveRecordOneGimbal(accessory: DockAccessory,
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

    func exponentialEaseInOut(_ progress: Double) -> Double {
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

    func currentOrientation(of accessory: DockAccessory) async throws -> Vector3D {
        let motionStates = try accessory.motionStates
        for await motionState in motionStates {
            if let error = motionState.error { throw error }
            return motionState.angularPositions
        }
        throw RecorderError.motionStateUnavailable
    }

    func startMovieRecording(to url: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            recordingStartContinuation = continuation
            movieOutput.startRecording(to: url, recordingDelegate: self)
        }
    }

    func updateVideoOrientation() {
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


}
