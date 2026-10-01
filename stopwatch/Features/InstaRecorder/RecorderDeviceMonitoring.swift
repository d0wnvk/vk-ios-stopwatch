import AVFoundation
import AudioToolbox
import Combine
import DockKit
import Photos
import Spatial
import SwiftUI
import UIKit

extension RecorderController {
    func observeDock() {
        stateTask = Task { [weak self] in
            do {
                for await change in try DockAccessoryManager.shared.accessoryStateChanges {
                    guard let self else { return }
                    if change.state == .docked, let dock = change.accessory {
                        let wasConnected = gimbalConnected
                        accessory = dock
                        gimbalConnected = true
                        observeGimbalBattery(dock)
                        observeAccessoryEvents(dock)
                        status = "Ready — tap Record."
                        if !wasConnected {
                            AudioServicesPlaySystemSound(1057)
                        }
                    } else {
                        gimbalBatteryTask?.cancel()
                        gimbalBatteryTask = nil
                        accessoryEventTask?.cancel()
                        accessoryEventTask = nil
                        accessory = nil
                        gimbalConnected = false
                        gimbalBatteryLevel = nil
                        gimbalIsCharging = false
                        isSelectingTrackedObject = false
                        isObjectTracking = false
                        trackedObjectRect = nil
                        trackedObjectLost = false
                        status = "Connect and dock the Insta360 Flow 2 Pro."
                    }
                }
            } catch {
                self?.status = "DockKit failed: \(error.localizedDescription)"
            }
        }
    }

    func observeIPhoneBattery() {
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

    func observeGimbalBattery(_ dock: DockAccessory) {
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

    func observeAccessoryEvents(_ dock: DockAccessory) {
        accessoryEventTask?.cancel()
        accessoryEventTask = Task { [weak self] in
            do {
                for await event in try dock.accessoryEvents {
                    guard !Task.isCancelled else { return }
                    guard case let .cameraZoom(factor) = event else { continue }
                    self?.adjustZoom(fromAccessoryFactor: factor)
                }
            } catch {
                guard !Task.isCancelled else { return }
                self?.status = "Gimbal controls unavailable: \(error.localizedDescription)"
            }
        }
    }

    func enableTrackedObjectSelection() {
        guard gimbalConnected, accessory != nil else {
            status = "Connect and dock the Insta360 Flow 2 Pro before selecting an object."
            return
        }
        updateVideoOrientation()
        isSelectingTrackedObject = true
        status = "Draw a rectangle around an object to track it."
    }

    func selectTrackedObject(in metadataRect: CGRect) async {
        guard isSelectingTrackedObject, accessory != nil else { return }
        do {
            try await DockAccessoryManager.shared.setSystemTrackingEnabled(false)
            let visionRect = CGRect(
                x: metadataRect.minX,
                y: 1 - metadataRect.maxY,
                width: metadataRect.width,
                height: metadataRect.height
            )
            objectTracker.select(visionRect: visionRect)
            isSelectingTrackedObject = false
            isObjectTracking = true
            trackedObjectLost = false
            trackedObjectRect = metadataRect
            status = "Tracking selected object."
        } catch {
            isSelectingTrackedObject = false
            isObjectTracking = false
            trackedObjectRect = nil
            status = "Object selection failed: \(error.localizedDescription)"
        }
    }

    func handleTrackedObjectUpdate(_ visionRect: CGRect?, pixelBuffer: CVPixelBuffer?) {
        guard isObjectTracking, let accessory, let camera else { return }
        guard let visionRect else {
            trackedObjectLost = true
            status = "Tracked object lost. Press Reselect Object and draw a new rectangle."
            return
        }

        trackedObjectRect = CGRect(
            x: visionRect.minX,
            y: 1 - visionRect.maxY,
            width: visionRect.width,
            height: visionRect.height
        )
        trackedObjectLost = false

        guard dockTrackingTask == nil else { return }
        let dimensions = pixelBuffer.map {
            CGSize(width: CVPixelBufferGetWidth($0), height: CVPixelBufferGetHeight($0))
        }
        let cameraInformation = DockAccessory.CameraInformation(
            captureDevice: camera.deviceType,
            cameraPosition: camera.position,
            orientation: currentDockCameraOrientation,
            cameraIntrinsics: nil,
            referenceDimensions: dimensions
        )
        let observation = DockAccessory.Observation(
            identifier: 0,
            type: .object,
            rect: visionRect
        )

        dockTrackingTask = Task {
            defer { dockTrackingTask = nil }
            do {
                if let pixelBuffer {
                    try await accessory.track(
                        [observation],
                        cameraInformation: cameraInformation,
                        image: pixelBuffer
                    )
                } else {
                    try await accessory.track(
                        [observation],
                        cameraInformation: cameraInformation
                    )
                }
            } catch {
                trackedObjectLost = true
                status = "Gimbal tracking failed: \(error.localizedDescription)"
            }
        }
    }

    private var currentDockCameraOrientation: DockAccessory.CameraOrientation {
        let interfaceOrientation = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .interfaceOrientation

        switch interfaceOrientation {
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        default:
            return .corrected
        }
    }


}
