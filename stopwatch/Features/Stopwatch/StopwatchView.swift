import Combine
import Foundation
import SwiftUI

struct StopwatchView: View {
    @State private var elapsedTime: TimeInterval = 0
    @State private var startDate: Date?
    @State private var laps: [TimeInterval] = []

    private let timer = Timer.publish(every: 0.01, on: .main, in: .common).autoconnect()

    private var isRunning: Bool {
        startDate != nil
    }

    var body: some View {
        VStack(spacing: 32) {
            Text(formattedTime(elapsedTime))
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
                        Text(formattedTime(lap))
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
    }

    private func stopStopwatch() {
        startDate = nil
    }

    private func addLap() {
        laps.insert(elapsedTime, at: 0)
        elapsedTime = 0

        if isRunning {
            startDate = Date()
        }
    }

    private func resetStopwatch() {
        startDate = nil
        elapsedTime = 0
        laps.removeAll()
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

    private func formattedTime(_ time: TimeInterval) -> String {
        let totalCentiseconds = Int(time * 100)
        let minutes = totalCentiseconds / 6_000
        let seconds = (totalCentiseconds / 100) % 60
        let centiseconds = totalCentiseconds % 100

        return String(format: "%02d:%02d.%02d", minutes, seconds, centiseconds)
    }
}
