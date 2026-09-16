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


}
