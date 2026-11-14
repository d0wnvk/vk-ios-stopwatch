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
        var fiveLDate: Date?
        var fiveLDate29: Date?
        var fiveHDate26: Date?
        var fiveHDate30: Date?
        var sixLDate27: Date?
        var sixLDate31: Date?
        var sixHDate28: Date?
        var sixHDate32: Date?
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
    @Published private(set) var soundIntervalMinutes = 2
    @Published private(set) var timerStartDate: Date?
    @Published private(set) var independentTimerStartDate: Date?
    @Published private(set) var fiveLDate: Date?
    @Published private(set) var fiveLDate29: Date?
    @Published private(set) var fiveHDate26: Date?
    @Published private(set) var fiveHDate30: Date?
    @Published private(set) var sixLDate27: Date?
    @Published private(set) var sixLDate31: Date?
    @Published private(set) var sixHDate28: Date?
    @Published private(set) var sixHDate32: Date?
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
        fiveLDate = saved.fiveLDate
        fiveLDate29 = saved.fiveLDate29
        fiveHDate26 = saved.fiveHDate26
        fiveHDate30 = saved.fiveHDate30
        sixLDate27 = saved.sixLDate27
        sixLDate31 = saved.sixLDate31
        sixHDate28 = saved.sixHDate28
        sixHDate32 = saved.sixHDate32
    }

    func resetAll() {
        rightNumbers = Array(repeating: 0, count: rightNumbers.count)
        soundIntervalMinutes = 2
        timerStartDate = nil
        independentTimerStartDate = nil
        fiveLDate = nil
        fiveLDate29 = nil
        fiveHDate26 = nil
        fiveHDate30 = nil
        sixLDate27 = nil
        sixLDate31 = nil
        sixHDate28 = nil
        sixHDate32 = nil
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

    func markDatedLabel(in cellNumber: Int, at date: Date = Date()) {
        if cellNumber == 25 {
            fiveLDate = date
        } else if cellNumber == 26 {
            fiveHDate26 = date
        } else if cellNumber == 29 {
            fiveLDate29 = date
        } else if cellNumber == 30 {
            fiveHDate30 = date
        } else if cellNumber == 27 {
            sixLDate27 = date
        } else if cellNumber == 31 {
            sixLDate31 = date
        } else if cellNumber == 28 {
            sixHDate28 = date
        } else if cellNumber == 32 {
            sixHDate32 = date
        }
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
                independentTimerStartDate: independentTimerStartDate,
                fiveLDate: fiveLDate,
                fiveLDate29: fiveLDate29,
                fiveHDate26: fiveHDate26,
                fiveHDate30: fiveHDate30,
                sixLDate27: sixLDate27,
                sixLDate31: sixLDate31,
                sixHDate28: sixHDate28,
                sixHDate32: sixHDate32
            ),
            forKey: "sport-tracker"
        )
    }
}
