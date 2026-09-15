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
        device.unlockForConfiguration()

        if let connection = movieOutput.connection(with: .video), connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = .cinematicExtended
        }
        camera = device
        currentZoom = device.videoZoomFactor
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


}
