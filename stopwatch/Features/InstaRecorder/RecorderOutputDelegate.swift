import AVFoundation
import AudioToolbox
import Combine
import DockKit
import Photos
import Spatial
import SwiftUI
import UIKit

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

extension RecorderController {
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

extension Double {
    var radians: Double { self * .pi / 180 }
}

enum RecorderError: LocalizedError {
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
