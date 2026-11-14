import Combine
import Foundation
import SwiftUI

struct StopwatchView: View {
    private struct SavedState: Codable {
        var elapsedTime: TimeInterval
        var startDate: Date?
        var laps: [TimeInterval]
    }

    @State private var elapsedTime: TimeInterval
    @State private var startDate: Date?
    @State private var laps: [TimeInterval]

    private let timer = Timer.publish(every: 0.01, on: .main, in: .common).autoconnect()

    private var isRunning: Bool {
        startDate != nil
    }

    init() {
        let saved = PersistentAppState.load(SavedState.self, forKey: "stopwatch")
        _elapsedTime = State(initialValue: saved?.elapsedTime ?? 0)
        _startDate = State(initialValue: saved?.startDate)
        _laps = State(initialValue: saved?.laps ?? [])
    }

    var body: some View {
        VStack(spacing: 32) {
            Text(ElapsedTimeFormatter.centiseconds(elapsedTime))
                .font(.system(size: 84, weight: .semibold, design: .monospaced))
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                stopwatchButton(title: "Start", color: .green, isDisabled: isRunning) {
                    startStopwatch()
                }

                stopwatchButton(title: "Stop", color: .red, isDisabled: !isRunning) {
                    stopStopwatch()
                }

                stopwatchButton(title: "Lap", color: .blue, isDisabled: elapsedTime == 0) {
                    addLap()
                }

                stopwatchButton(title: "Reset", color: .gray, isDisabled: elapsedTime == 0 && laps.isEmpty) {
                    resetStopwatch()
                }
            }

            List {
                ForEach(Array(laps.enumerated()), id: \.offset) { index, lap in
                    HStack {
                        Text("Lap \(laps.count - index)")
                        Spacer()
                        Text(ElapsedTimeFormatter.centiseconds(lap))
                            .fontDesign(.monospaced)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .foregroundStyle(.white)
        .onReceive(timer) { now in
            guard let startDate else { return }
            elapsedTime = now.timeIntervalSince(startDate)
        }
    }

    private func startStopwatch() {
        startDate = Date().addingTimeInterval(-elapsedTime)
        saveState()
    }

    private func stopStopwatch() {
        if let startDate {
            elapsedTime = Date().timeIntervalSince(startDate)
        }
        startDate = nil
        saveState()
    }

    private func addLap() {
        laps.insert(elapsedTime, at: 0)
        elapsedTime = 0

        if isRunning {
            startDate = Date()
        }
        saveState()
    }

    private func resetStopwatch() {
        startDate = nil
        elapsedTime = 0
        laps.removeAll()
        saveState()
    }

    private func saveState() {
        PersistentAppState.save(
            SavedState(elapsedTime: elapsedTime, startDate: startDate, laps: laps),
            forKey: "stopwatch"
        )
    }

    private func stopwatchButton(
        title: String,
        color: Color,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 92, height: 92)
                .background(isDisabled ? Color.gray.opacity(0.35) : color)
                .clipShape(Circle())
        }
        .disabled(isDisabled)
    }

}
