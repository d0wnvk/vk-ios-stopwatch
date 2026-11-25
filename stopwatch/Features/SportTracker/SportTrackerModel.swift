import AVFoundation
import Combine
import Foundation
import UserNotifications

@MainActor
final class SportTrackerModel: ObservableObject {
    static let timerNotificationIdentifier = "sport-tracker-timer-threshold"

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

    static let tappableCellNumbers = SportTrackerCellCatalog.tappableCellNumbers

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
    private var notificationSchedulingTask: Task<Void, Never>?
    private var isNotificationSoundScheduled = false
    private let persistenceEnabled: Bool
    private let notificationSchedulingEnabled: Bool

    init(
        persistenceEnabled: Bool = true,
        notificationSchedulingEnabled: Bool = true
    ) {
        self.persistenceEnabled = persistenceEnabled
        self.notificationSchedulingEnabled = notificationSchedulingEnabled

        guard persistenceEnabled else { return }
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

        if timerStartDate != nil {
            scheduleTimerNotification()
        }
    }

    func resetAll() {
        let datedCellValues = Array(rightNumbers[24..<32])
        rightNumbers = Array(repeating: 0, count: rightNumbers.count)
        rightNumbers.replaceSubrange(24..<32, with: datedCellValues)
        soundIntervalMinutes = 2
        timerStartDate = nil
        independentTimerStartDate = nil
        flashingCells.removeAll()
        lastCellTapDates.removeAll()
        didPlayOneMinuteSound = false
        stopAudio()
        cancelTimerNotification()
        saveState()
    }

    func resetDatedLabels() {
        rightNumbers.replaceSubrange(24..<32, with: repeatElement(0, count: 8))
        fiveLDate = nil
        fiveLDate29 = nil
        fiveHDate26 = nil
        fiveHDate30 = nil
        sixLDate27 = nil
        sixLDate31 = nil
        sixHDate28 = nil
        sixHDate32 = nil
        saveState()
    }

    func incrementSoundInterval() {
        soundIntervalMinutes += 1
        didPlayOneMinuteSound = false
        scheduleTimerNotification()
        saveState()
    }

    func decrementSoundInterval() {
        guard soundIntervalMinutes > 1 else { return }
        soundIntervalMinutes -= 1
        didPlayOneMinuteSound = false
        scheduleTimerNotification()
        saveState()
    }

    func incrementCounter(for cellNumber: Int, at now: Date = Date()) {
        guard rightNumbers.indices.contains(cellNumber - 1) else { return }

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
        scheduleTimerNotification(at: now)
        saveState()
    }

    func decrementCounter(for cellNumber: Int) {
        guard rightNumbers.indices.contains(cellNumber - 1) else { return }
        guard rightNumbers[cellNumber - 1] > 0 else { return }
        rightNumbers[cellNumber - 1] -= 1
        saveState()
    }

    func markDatedLabel(in cellNumber: Int, at date: Date = Date()) {
        guard canMarkDatedLabel(in: cellNumber) else { return }

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

    func canMarkDatedLabel(in cellNumber: Int) -> Bool {
        SportTrackerCellCatalog.datedCellSequence.first(where: {
            datedLabelDate(in: $0) == nil
        }) == cellNumber
    }

    func isCurrentDatedLabel(in cellNumber: Int) -> Bool {
        let sequence = SportTrackerCellCatalog.datedCellSequence
        let firstUnmarkedIndex = sequence.firstIndex(where: {
            datedLabelDate(in: $0) == nil
        }) ?? sequence.endIndex

        guard firstUnmarkedIndex > sequence.startIndex else { return false }
        return sequence[firstUnmarkedIndex - 1] == cellNumber
    }

    func playSoundIfNeeded(at now: Date) {
        guard let timerStartDate,
              !didPlayOneMinuteSound,
              !isNotificationSoundScheduled,
              now.timeIntervalSince(timerStartDate) >= TimeInterval(soundIntervalMinutes * 60)
        else { return }

        didPlayOneMinuteSound = true
        guard let soundURL = Bundle.main.url(
            forResource: "notification-sound",
            withExtension: "mp3"
        ) else { return }

        do {
            try SportTrackerSoundPlayer.shared.play(soundURL)
        } catch {
            SportTrackerSoundPlayer.shared.stop()
        }
    }

    func stopAudio() {
        SportTrackerSoundPlayer.shared.stop()
    }

    private func scheduleTimerNotification(at now: Date = .now) {
        guard notificationSchedulingEnabled else { return }
        guard let timerStartDate else {
            cancelTimerNotification()
            return
        }

        notificationSchedulingTask?.cancel()
        isNotificationSoundScheduled = false

        let intervalMinutes = soundIntervalMinutes
        let fireDate = timerStartDate.addingTimeInterval(TimeInterval(intervalMinutes * 60))
        let delay = max(1, fireDate.timeIntervalSince(now))

        notificationSchedulingTask = Task { [weak self] in
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(
                withIdentifiers: [Self.timerNotificationIdentifier]
            )

            let settings = await center.notificationSettings()
            let isAuthorized: Bool
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                isAuthorized = true
            case .notDetermined:
                isAuthorized = (try? await center.requestAuthorization(
                    options: [.alert, .sound]
                )) == true
            case .denied:
                isAuthorized = false
            @unknown default:
                isAuthorized = false
            }

            guard !Task.isCancelled, isAuthorized else { return }

            let content = UNMutableNotificationContent()
            content.title = "Sport plan 1"
            content.body = "The cell 6 timer reached \(intervalMinutes) minutes."
            content.sound = UNNotificationSound(
                named: UNNotificationSoundName("notification-sound.caf")
            )

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: delay,
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: Self.timerNotificationIdentifier,
                content: content,
                trigger: trigger
            )

            do {
                try await center.add(request)
                guard !Task.isCancelled else {
                    center.removePendingNotificationRequests(
                        withIdentifiers: [Self.timerNotificationIdentifier]
                    )
                    return
                }
                self?.isNotificationSoundScheduled = true
            } catch {
                self?.isNotificationSoundScheduled = false
            }
        }
    }

    private func cancelTimerNotification() {
        guard notificationSchedulingEnabled else { return }
        notificationSchedulingTask?.cancel()
        notificationSchedulingTask = nil
        isNotificationSoundScheduled = false

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(
            withIdentifiers: [Self.timerNotificationIdentifier]
        )
        center.removeDeliveredNotifications(
            withIdentifiers: [Self.timerNotificationIdentifier]
        )
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
        guard persistenceEnabled else { return }
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

    private func datedLabelDate(in cellNumber: Int) -> Date? {
        switch cellNumber {
        case 25: fiveLDate
        case 26: fiveHDate26
        case 27: sixLDate27
        case 28: sixHDate28
        case 29: fiveLDate29
        case 30: fiveHDate30
        case 31: sixLDate31
        case 32: sixHDate32
        default: nil
        }
    }
}

@MainActor
final class SportTrackerSoundPlayer {
    static let shared = SportTrackerSoundPlayer()

    private var audioPlayer: AVAudioPlayer?

    private init() {}

    func play(_ soundURL: URL) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)

        let player = try AVAudioPlayer(contentsOf: soundURL)
        player.volume = 1
        player.prepareToPlay()
        audioPlayer = player
        player.play()
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
    }
}
