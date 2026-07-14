//
//  ContentView.swift
//  stopwatch
//
//  Created by Vladimir Korolevskii on 7. 7. 2026..
//

import SwiftUI
import Foundation
import Combine
import UIKit
import CoreHaptics

struct ContentView: View {
    var body: some View {
        TabView {
            StopwatchScreen()
                .tabItem {
                    Label("Stopwatch", systemImage: "stopwatch")
                }

            SecondScreen()
                .tabItem {
                    Label("Second", systemImage: "square.grid.2x2")
                }
        }
    }
}

struct StopwatchScreen: View {
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

struct SecondScreen: View {
    @State private var elapsedTime: TimeInterval = 0
    @State private var cycleStartDate: Date?
    @State private var restartLog: [String] = []
    @State private var hapticEngine: CHHapticEngine?

    private let repeatingTimer = Timer.publish(every: 0.01, on: .main, in: .common).autoconnect()
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .heavy)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 28) {
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

                List {
                    ForEach(Array(restartLog.enumerated()), id: \.offset) { index, entry in
                        HStack {
                            Text("Event \(restartLog.count - index)")
                            Spacer()
                            Text(entry)
                                .fontDesign(.monospaced)
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    }
                }
                .environment(\.defaultMinListRowHeight, 28)
                .scrollContentBackground(.hidden)
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
                triggerResetHaptics()
            } else {
                elapsedTime = cycleElapsed
            }
        }
    }

    private func startRepeatingTimer() {
        cycleStartDate = Date()
        elapsedTime = 0
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
        restartLog.removeAll()
    }

    private func triggerResetHaptics() {
        guard let hapticEngine else {
            triggerFallbackHaptics()
            return
        }

        let events: [CHHapticEvent] = [
            CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.95),
                ],
                relativeTime: 0,
                duration: 0.18
            ),
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0),
                ],
                relativeTime: 0.02
            ),
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0),
                ],
                relativeTime: 0.08
            ),
            CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0),
                ],
                relativeTime: 0.18,
                duration: 0.22
            ),
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0),
                ],
                relativeTime: 0.20
            ),
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0),
                ],
                relativeTime: 0.28
            ),
        ]

        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try hapticEngine.makePlayer(with: pattern)
            try hapticEngine.start()
            try player.start(atTime: 0)
        } catch {
            triggerFallbackHaptics()
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

    private func triggerFallbackHaptics() {
        let pulseDelays: [TimeInterval] = [0, 0.05, 0.10, 0.16, 0.22, 0.28]

        for delay in pulseDelays {
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
