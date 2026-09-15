import Combine
import CoreHaptics
import Foundation
import SwiftUI
import UIKit

struct EyeBreakView: View {
    @State private var elapsedTime: TimeInterval = 0
    @State private var cycleStartDate: Date?
    @State private var restartLog: [String] = []
    @State private var hapticEngine: CHHapticEngine?
    @State private var completedIntervalCount = 0

    private let repeatingTimer = Timer.publish(every: 0.01, on: .main, in: .common).autoconnect()
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .heavy)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 28) {
                Text("Eye Break")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)

                Text(formattedTime(elapsedTime))
                    .font(.system(size: 72, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)

                HStack(spacing: 12) {
                    Button(action: startRepeatingTimer) {
                        Text(cycleStartDate == nil ? "Start Timer" : "Restart Timer")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    Button(action: stopRepeatingTimer) {
                        Text("Stop")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(cycleStartDate == nil ? Color.gray.opacity(0.35) : Color.red)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .disabled(cycleStartDate == nil)

                    Button(action: resetRepeatingTimer) {
                        Text("Reset")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                cycleStartDate == nil && elapsedTime == 0
                                    ? Color.gray.opacity(0.35)
                                    : Color.gray
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .disabled(cycleStartDate == nil && elapsedTime == 0)
                }

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(restartLog.enumerated()), id: \.offset) { index, entry in
                            HStack(spacing: 12) {
                                Text("#\(restartLog.count - index)")
                                Text(entry)
                            }
                            .font(.caption.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .accessibilityElement(children: .combine)

                            if index < restartLog.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            prepareHaptics()
        }
        .onReceive(repeatingTimer) { now in
            guard let cycleStartDate else { return }

            let cycleElapsed = now.timeIntervalSince(cycleStartDate)

            if cycleElapsed >= 30 {
                self.cycleStartDate = now
                elapsedTime = 0
                restartLog.insert("Restarted", at: 0)
                completedIntervalCount += 1
                triggerIntervalHaptics(for: completedIntervalCount)
            } else {
                elapsedTime = cycleElapsed
            }
        }
    }

    private func startRepeatingTimer() {
        cycleStartDate = Date()
        elapsedTime = 0
        completedIntervalCount = 0
        restartLog.insert("Started", at: 0)
        feedbackGenerator.prepare()
        prepareHaptics()
    }

    private func stopRepeatingTimer() {
        cycleStartDate = nil
        restartLog.insert("Stopped", at: 0)
    }

    private func resetRepeatingTimer() {
        cycleStartDate = nil
        elapsedTime = 0
        completedIntervalCount = 0
        restartLog.removeAll()
    }

    private func triggerIntervalHaptics(for interval: Int) {
        let buzzStartTimes = buzzStartTimes(for: interval)

        guard let hapticEngine else {
            triggerFallbackHaptics(at: buzzStartTimes)
            return
        }

        let events = buzzStartTimes.map { startTime in
            CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.9),
                ],
                relativeTime: startTime,
                duration: 0.10
            )
        }

        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try hapticEngine.makePlayer(with: pattern)
            try hapticEngine.start()
            try player.start(atTime: 0)
        } catch {
            triggerFallbackHaptics(at: buzzStartTimes)
        }
    }

    private func buzzStartTimes(for interval: Int) -> [TimeInterval] {
        let buzzCount = ((interval - 1) % 16) + 1

        return (0..<buzzCount).map { buzzIndex in
            let groupIndex = buzzIndex / 2
            let positionWithinGroup = buzzIndex % 2

            return TimeInterval(groupIndex) * 0.55
                + TimeInterval(positionWithinGroup) * 0.18
        }
    }

    private func prepareHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            hapticEngine = nil
            return
        }

        guard hapticEngine == nil else { return }

        do {
            let engine = try CHHapticEngine()
            try engine.start()
            hapticEngine = engine
        } catch {
            hapticEngine = nil
        }
    }

    private func triggerFallbackHaptics(at buzzStartTimes: [TimeInterval]) {
        for delay in buzzStartTimes {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                feedbackGenerator.impactOccurred(intensity: 1.0)
                feedbackGenerator.prepare()
            }
        }
    }

    private func formattedTime(_ time: TimeInterval) -> String {
        let totalCentiseconds = Int(time * 100)
        let minutes = totalCentiseconds / 6_000
        let seconds = (totalCentiseconds / 100) % 60
        let centiseconds = totalCentiseconds % 100

        return String(format: "%02d:%02d.%02d", minutes, seconds, centiseconds)
    }
}

#Preview {
    ContentView()
}
