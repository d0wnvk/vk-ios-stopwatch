import AVFoundation
import Combine
import Foundation

@MainActor
final class SportTrackerModel: ObservableObject {
    private struct SavedState: Codable {
        var layoutVersion: Int?
        var rightNumbers: [Int]
        var soundIntervalMinutes: Int
        var timerStartDate: Date?
        var independentTimerStartDate: Date?
    }

    static let tappableCellNumbers: Set<Int> = [
        10, 11, 12,
        14, 15, 16,
        18, 19, 20,
        38, 39, 40,
        42, 43, 44,
        46, 47, 48,
    ]

    @Published private(set) var rightNumbers = Array(repeating: 0, count: 48)
    @Published private(set) var soundIntervalMinutes = 1
    @Published private(set) var timerStartDate: Date?
    @Published private(set) var independentTimerStartDate: Date?
    @Published private(set) var flashingCells: [Int: UUID] = [:]

    private var lastCellTapDates: [Int: Date] = [:]
    private var didPlayOneMinuteSound = false
    private var audioPlayer: AVAudioPlayer?

    init() {
        guard let saved = PersistentAppState.load(SavedState.self, forKey: "sport-tracker")
        else { return }

        let migratedNumbers: [Int]
        if saved.layoutVersion == 2, saved.rightNumbers.count == rightNumbers.count {
            migratedNumbers = saved.rightNumbers
        } else if saved.rightNumbers.count == 48 {
            migratedNumbers = Array(
                (Array(saved.rightNumbers.prefix(28))
                + Array(repeating: 0, count: 8)
                + Array(saved.rightNumbers.dropFirst(28))).prefix(48)
            )
        } else if saved.rightNumbers.count == 56 {
            migratedNumbers = Array(saved.rightNumbers.prefix(48))
        } else {
            return
        }

        rightNumbers = migratedNumbers
        soundIntervalMinutes = max(1, saved.soundIntervalMinutes)
        timerStartDate = saved.timerStartDate
        independentTimerStartDate = saved.independentTimerStartDate
    }

    func resetAll() {
        rightNumbers = Array(repeating: 0, count: rightNumbers.count)
        soundIntervalMinutes = 1
        timerStartDate = nil
        independentTimerStartDate = nil
        flashingCells.removeAll()
        lastCellTapDates.removeAll()
        didPlayOneMinuteSound = false
        stopAudio()
        saveState()
    }

    func incrementSoundInterval() {
        soundIntervalMinutes += 1
        didPlayOneMinuteSound = false
        saveState()
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
        saveState()
    }

    func decrementCounter(for cellNumber: Int) {
        guard rightNumbers[cellNumber - 1] > 0 else { return }
        rightNumbers[cellNumber - 1] -= 1
        saveState()
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

    private func saveState() {
        PersistentAppState.save(
            SavedState(
                layoutVersion: 2,
                rightNumbers: rightNumbers,
                soundIntervalMinutes: soundIntervalMinutes,
                timerStartDate: timerStartDate,
                independentTimerStartDate: independentTimerStartDate
            ),
            forKey: "sport-tracker"
        )
    }
}
