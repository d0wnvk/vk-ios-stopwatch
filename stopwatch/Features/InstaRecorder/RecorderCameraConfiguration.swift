import AVFoundation
import AudioToolbox
import Combine
import DockKit
import Photos
import Spatial
import SwiftUI
import UIKit

extension RecorderController {
    func configureCamera() throws {
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

        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
           let microphone = AVCaptureDevice.default(for: .audio) {
            let audioInput = try AVCaptureDeviceInput(device: microphone)
            if session.canAddInput(audioInput) { session.addInput(audioInput) }
        }

        guard session.canAddOutput(movieOutput) else { throw RecorderError.cannotAddOutput }
        session.addOutput(movieOutput)

        try device.lockForConfiguration()
        device.activeFormat = format
        device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 60)
        device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 60)
        if device.primaryConstituentDeviceSwitchingBehavior != .unsupported {
            device.setPrimaryConstituentDeviceSwitchingBehavior(
                .auto,
                restrictedSwitchingBehaviorConditions: []
            )
            movieOutput.setPrimaryConstituentDeviceSwitchingBehaviorForRecording(
                .auto,
                restrictedSwitchingBehaviorConditions: []
            )
        }
        device.unlockForConfiguration()

        if let connection = movieOutput.connection(with: .video), connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = .cinematicExtended
        }
        camera = device
        currentZoom = device.videoZoomFactor
        observeActiveCamera(on: device)
    }

    func requestCameraPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    func observeActiveCamera(on device: AVCaptureDevice) {
        activeCameraObservation?.invalidate()
        updateActiveCameraName(for: device)
        activeCameraObservation = device.observe(
            \.activePrimaryConstituent,
            options: [.new]
        ) { [weak self, weak device] _, _ in
            Task { @MainActor in
                guard let self, let device else { return }
                self.updateActiveCameraName(for: device)
            }
        }
    }

    private func updateActiveCameraName(for device: AVCaptureDevice) {
        let activeCamera = device.activePrimaryConstituent ?? device
        let previousCameraID = activePhysicalCameraID
        activePhysicalCameraID = activeCamera.uniqueID

        switch activeCamera.deviceType {
        case .builtInUltraWideCamera:
            activeCameraName = "Ultra Wide"
        case .builtInWideAngleCamera:
            activeCameraName = "Wide"
        case .builtInTelephotoCamera:
            activeCameraName = "Telephoto"
        default:
            activeCameraName = activeCamera.localizedName
        }

        // Only clamp after AVFoundation actually changes physical lenses. Doing
        // this for ordinary zoom input would prevent the zoom from crossing a
        // switch-over boundary and make the longer lens unreachable.
        if let previousCameraID, previousCameraID != activeCamera.uniqueID {
            enforceZoomRange(for: activeCamera, on: device)
        }
    }

    private func enforceZoomRange(
        for activeCamera: AVCaptureDevice,
        on virtualCamera: AVCaptureDevice
    ) {
        guard cameraReady, !isRecording, virtualCamera.isVirtualDevice else { return }
        guard let activeIndex = virtualCamera.constituentDevices.firstIndex(where: {
            $0.uniqueID == activeCamera.uniqueID
        }) else { return }

        let switchFactors = virtualCamera.virtualDeviceSwitchOverVideoZoomFactors.map {
            CGFloat(truncating: $0)
        }
        let lowerBound = activeIndex == 0
            ? virtualCamera.minAvailableVideoZoomFactor
            : switchFactors[activeIndex - 1]

        let displayMultiplier = virtualCamera.displayVideoZoomFactorMultiplier
        let internalStepForDisplayedTenth = 0.1 / max(displayMultiplier, 0.001)
        let upperBound = activeIndex < switchFactors.count
            ? max(lowerBound, switchFactors[activeIndex] - internalStepForDisplayedTenth)
            : virtualCamera.maxAvailableVideoZoomFactor

        let currentFactor = virtualCamera.videoZoomFactor
        let gatedFactor = min(max(currentFactor, lowerBound), upperBound)
        guard abs(gatedFactor - currentFactor) > 0.001 else { return }

        setZoom(gatedFactor)
        status = String(
            format: "%@ camera selected; zoom adjusted to %.1f×.",
            activeCameraName,
            gatedFactor * displayMultiplier
        )
    }

    func focusAndExpose(at point: CGPoint, lockAfterAdjustment: Bool) {
        guard cameraReady, !isRecording, let camera else { return }
        focusLockTask?.cancel()
        focusFeedback = .focusing

        do {
            try camera.lockForConfiguration()

            let supportsFocusPoint = camera.isFocusPointOfInterestSupported
            if supportsFocusPoint {
                camera.focusPointOfInterest = point
            }

            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            } else if camera.isFocusModeSupported(.autoFocus) {
                camera.focusMode = .autoFocus
            }

            if camera.isExposurePointOfInterestSupported {
                camera.exposurePointOfInterest = point
            }
            if camera.isExposureModeSupported(.autoExpose) {
                camera.exposureMode = .autoExpose
            }

            camera.unlockForConfiguration()
            guard supportsFocusPoint else {
                status = "This camera does not support touch focus points."
                focusFeedback = .failed
                return
            }

            status = lockAfterAdjustment
                ? "Focusing before AE/AF lock…"
                : "Continuous focus and exposure point set."
        } catch {
            status = "Focus failed: \(error.localizedDescription)"
            focusFeedback = .failed
            return
        }

        focusLockTask = Task { [weak self] in
            guard let self else { return }

            var focusSettled = false
            for _ in 0..<40 {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .milliseconds(50))
                if !camera.isAdjustingFocus {
                    focusSettled = true
                    break
                }
            }

            guard !Task.isCancelled else { return }
            guard focusSettled else {
                focusFeedback = .failed
                status = "Unable to focus. Move farther away, select another point, or change zoom."
                focusLockTask = nil
                return
            }

            guard lockAfterAdjustment else {
                focusFeedback = .focused
                status = "Focus settled."
                focusLockTask = nil
                return
            }

            do {
                try camera.lockForConfiguration()
                if camera.isFocusModeSupported(.locked) {
                    camera.focusMode = .locked
                }
                if camera.isExposureModeSupported(.locked) {
                    camera.exposureMode = .locked
                }
                camera.unlockForConfiguration()
                focusFeedback = .locked
                status = "Focus and exposure locked."
            } catch {
                focusFeedback = .failed
                status = "AE/AF lock failed: \(error.localizedDescription)"
            }
            focusLockTask = nil
        }
    }

    func restoreContinuousFocusAndExposure() {
        guard cameraReady, !isRecording, let camera else { return }
        focusLockTask?.cancel()
        focusLockTask = nil
        focusFeedback = .hidden

        do {
            try camera.lockForConfiguration()
            let center = CGPoint(x: 0.5, y: 0.5)
            if camera.isFocusPointOfInterestSupported {
                camera.focusPointOfInterest = center
            }
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            }
            if camera.isExposurePointOfInterestSupported {
                camera.exposurePointOfInterest = center
            }
            if camera.isExposureModeSupported(.continuousAutoExposure) {
                camera.exposureMode = .continuousAutoExposure
            }
            camera.unlockForConfiguration()
            status = "Continuous autofocus and exposure restored."
        } catch {
            focusFeedback = .failed
            status = "Restoring autofocus failed: \(error.localizedDescription)"
        }
    }


}
