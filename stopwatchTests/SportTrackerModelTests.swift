import XCTest
@testable import stopwatch

@MainActor
final class SportTrackerModelTests: XCTestCase {
    private func makeModel() -> SportTrackerModel {
        SportTrackerModel(
            persistenceEnabled: false,
            notificationSchedulingEnabled: false
        )
    }

    func testIncrementUpdatesCounterAndStartsBothTimers() {
        let model = makeModel()
        let now = Date(timeIntervalSince1970: 1_000)

        model.incrementCounter(for: 10, at: now)

        XCTAssertEqual(model.rightNumbers[9], 1)
        XCTAssertEqual(model.timerStartDate, now)
        XCTAssertEqual(model.independentTimerStartDate, now)
    }

    func testIndependentTimerStartsOnlyOnce() {
        let model = makeModel()
        let firstDate = Date(timeIntervalSince1970: 1_000)
        let secondDate = firstDate.addingTimeInterval(5)

        model.incrementCounter(for: 10, at: firstDate)
        model.incrementCounter(for: 11, at: secondDate)

        XCTAssertEqual(model.timerStartDate, secondDate)
        XCTAssertEqual(model.independentTimerStartDate, firstDate)
    }

    func testTappableCellIgnoresSecondTapDuringCooldown() {
        let model = makeModel()
        let firstDate = Date(timeIntervalSince1970: 1_000)

        model.incrementCounter(for: 10, at: firstDate)
        model.incrementCounter(for: 10, at: firstDate.addingTimeInterval(0.5))
        model.incrementCounter(for: 10, at: firstDate.addingTimeInterval(1))

        XCTAssertEqual(model.rightNumbers[9], 2)
    }

    func testDecrementStopsAtZero() {
        let model = makeModel()

        model.decrementCounter(for: 10)
        model.incrementCounter(for: 10)
        model.decrementCounter(for: 10)
        model.decrementCounter(for: 10)

        XCTAssertEqual(model.rightNumbers[9], 0)
    }

    func testInvalidCellNumbersAreIgnored() {
        let model = makeModel()

        model.incrementCounter(for: 0)
        model.incrementCounter(for: 49)
        model.decrementCounter(for: 0)
        model.decrementCounter(for: 49)

        XCTAssertEqual(model.rightNumbers, Array(repeating: 0, count: 48))
        XCTAssertNil(model.timerStartDate)
    }

    func testSoundIntervalCannotGoBelowOneMinute() {
        let model = makeModel()

        model.decrementSoundInterval()
        model.decrementSoundInterval()

        XCTAssertEqual(model.soundIntervalMinutes, 1)
    }

    func testDatedCellsMustBeMarkedInSequence() {
        let model = makeModel()
        let date = Date(timeIntervalSince1970: 2_000)

        XCTAssertTrue(model.canMarkDatedLabel(in: 25))
        XCTAssertFalse(model.canMarkDatedLabel(in: 29))

        model.markDatedLabel(in: 29, at: date)
        XCTAssertNil(model.datedState[.fiveL29])

        model.markDatedLabel(in: 25, at: date)
        XCTAssertEqual(model.datedState[.fiveL25], date)
        XCTAssertTrue(model.canMarkDatedLabel(in: 29))
        XCTAssertTrue(model.isCurrentDatedLabel(in: 25))
    }

    func testResetAllPreservesDatedCellsButClearsWorkoutState() {
        let model = makeModel()
        let date = Date(timeIntervalSince1970: 2_000)
        model.markDatedLabel(in: 25, at: date)
        model.incrementCounter(for: 10, at: date)

        model.resetAll()

        XCTAssertEqual(model.datedState[.fiveL25], date)
        XCTAssertEqual(model.rightNumbers[9], 0)
        XCTAssertNil(model.timerStartDate)
        XCTAssertNil(model.independentTimerStartDate)
        XCTAssertEqual(model.soundIntervalMinutes, 2)
    }

    func testResetDatedLabelsClearsDates() {
        let model = makeModel()
        model.markDatedLabel(in: 25, at: Date(timeIntervalSince1970: 2_000))

        model.resetDatedLabels()

        XCTAssertNil(model.datedState[.fiveL25])
        XCTAssertTrue(model.canMarkDatedLabel(in: 25))
    }

    func testDatedStateCodableRoundTrip() throws {
        var state = SportTrackerDatedState()
        let firstDate = Date(timeIntervalSince1970: 2_000)
        let secondDate = Date(timeIntervalSince1970: 3_000)
        state[.fiveL25] = firstDate
        state[.sixH32] = secondDate

        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(SportTrackerDatedState.self, from: encoded)

        XCTAssertEqual(decoded[.fiveL25], firstDate)
        XCTAssertEqual(decoded[.sixH32], secondDate)
        XCTAssertNil(decoded[.fiveH26])
    }
}
