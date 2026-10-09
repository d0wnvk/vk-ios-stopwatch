import AVFoundation
import Combine
import Foundation

@MainActor
final class SportTrackerModel: ObservableObject {
    static let tappableCellNumbers: Set<Int> = [
        10, 11, 12,
        14, 15, 16,
        18, 19, 20,
        30, 31, 32,
        34, 35, 36,
        38, 39, 40,
    ]

    @Published private(set) var rightNumbers = Array(repeating: 0, count: 48)
    @Published private(set) var soundIntervalMinutes = 1
    @Published private(set) var timerStartDate: Date?
    @Published private(set) var independentTimerStartDate: Date?
    @Published private(set) var flashingCells: [Int: UUID] = [:]

    private var lastCellTapDates: [Int: Date] = [:]
    private var didPlayOneMinuteSound = false
    private var audioPlayer: AVAudioPlayer?

    func resetAll() {
        rightNumbers = Array(repeating: 0, count: rightNumbers.count)
        soundIntervalMinutes = 1
        timerStartDate = nil
        independentTimerStartDate = nil
        flashingCells.removeAll()
        lastCellTapDates.removeAll()
        didPlayOneMinuteSound = false
        stopAudio()
    }

    func incrementSoundInterval() {
        soundIntervalMinutes += 1
        didPlayOneMinuteSound = false
    }

    func incrementCounter(for cellNumber: Int, at now: Date = Date()) {
        if Self.tappableCellNumbers.contains(cellNumber) {
            if let lastTapDate = lastCellTapDates[cellNumber],
               now.timeIntervalSince(lastTapDate) < 1 {
                return
            }
            lastCellTapDates[cellNumber] = now
        }

        timerStartDate = now
        didPlayOneMinuteSound = false
        stopAudio()
        if independentTimerStartDate == nil {
            independentTimerStartDate = now
        }
        rightNumbers[cellNumber - 1] += 1

        if Self.tappableCellNumbers.contains(cellNumber) {
            flash(cellNumber)
        }
    }

    func decrementCounter(for cellNumber: Int) {
        guard rightNumbers[cellNumber - 1] > 0 else { return }
        rightNumbers[cellNumber - 1] -= 1
    }

    func playSoundIfNeeded(at now: Date) {
        guard let timerStartDate,
              !didPlayOneMinuteSound,
              now.timeIntervalSince(timerStartDate) >= TimeInterval(soundIntervalMinutes * 60)
        else { return }

        didPlayOneMinuteSound = true
        guard let soundURL = Bundle.main.url(
            forResource: "notification-sound",
            withExtension: "mp3"
        ) else { return }

        do {
            let player = try AVAudioPlayer(contentsOf: soundURL)
            player.prepareToPlay()
            audioPlayer = player
            player.play()
        } catch {
            audioPlayer = nil
        }
    }

    func stopAudio() {
        audioPlayer?.stop()
    }

    private func flash(_ cellNumber: Int) {
        let flashID = UUID()
        flashingCells[cellNumber] = flashID

        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard let self, flashingCells[cellNumber] == flashID else { return }
            flashingCells[cellNumber] = nil
        }
    }
}
