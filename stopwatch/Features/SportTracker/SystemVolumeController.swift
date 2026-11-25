import AVFAudio
import Combine
import MediaPlayer
import UIKit

@MainActor
final class SystemVolumeController: ObservableObject {
    @Published private(set) var currentVolume: Float
    @Published private(set) var isMaximumVolumeEnabled = false

    private var previousVolume: Float?
    private var temporaryVolumeView: MPVolumeView?
    private var volumeObservation: NSKeyValueObservation?

    init() {
        let audioSession = AVAudioSession.sharedInstance()
        currentVolume = audioSession.outputVolume
        volumeObservation = audioSession.observe(
            \.outputVolume,
            options: [.initial, .new]
        ) { [weak self] _, change in
            guard let volume = change.newValue else { return }
            Task { @MainActor [weak self] in
                self?.currentVolume = volume
            }
        }
    }

    var volumePercentage: Int {
        Int((currentVolume * 100).rounded())
    }

    func refreshCurrentVolume() {
        let systemVolume = AVAudioSession.sharedInstance().outputVolume
        if abs(currentVolume - systemVolume) > 0.001 {
            currentVolume = systemVolume
        }
    }

    func toggleMaximumVolume() {
        if isMaximumVolumeEnabled {
            setVolume(previousVolume ?? currentVolume)
            previousVolume = nil
            isMaximumVolumeEnabled = false
        } else {
            previousVolume = currentVolume
            isMaximumVolumeEnabled = true
            setVolume(1)
        }
    }

    private func setVolume(_ volume: Float) {
        let clampedVolume = min(max(volume, 0), 1)
        currentVolume = clampedVolume

        temporaryVolumeView?.removeFromSuperview()

        let volumeView = MPVolumeView(frame: CGRect(x: -2, y: -2, width: 1, height: 1))
        volumeView.alpha = 0.01
        temporaryVolumeView = volumeView

        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: { $0.isKeyWindow })
        window?.addSubview(volumeView)
        volumeView.layoutIfNeeded()

        applyVolume(clampedVolume, through: volumeView, attempt: 0)
    }

    private func applyVolume(_ volume: Float, through volumeView: MPVolumeView, attempt: Int) {
        guard temporaryVolumeView === volumeView else { return }

        if volumeView.window != nil,
           let slider = volumeView.subviews.compactMap({ $0 as? UISlider }).first {
            slider.setValue(volume, animated: false)
            slider.sendActions(for: .valueChanged)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self, weak volumeView] in
                guard let self, let volumeView else { return }
                self.removeTemporaryVolumeView(volumeView)
            }
            return
        }

        guard attempt < 10 else {
            removeTemporaryVolumeView(volumeView)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak volumeView] in
            guard let self, let volumeView else { return }
            self.applyVolume(volume, through: volumeView, attempt: attempt + 1)
        }
    }

    private func removeTemporaryVolumeView(_ volumeView: MPVolumeView) {
        volumeView.removeFromSuperview()
        if temporaryVolumeView === volumeView {
            temporaryVolumeView = nil
        }
    }
}
