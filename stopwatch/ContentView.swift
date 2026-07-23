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
    @State private var selectedTab = 2

    var body: some View {
        TabView(selection: $selectedTab) {
            StopwatchScreen()
                .tag(0)
                .tabItem {
                    Label("Stopwatch", systemImage: "stopwatch")
                }

            SecondScreen()
                .tag(1)
                .tabItem {
                    Label("Second", systemImage: "square.grid.2x2")
                }

            ThirdScreen()
                .tag(2)
                .tabItem {
                    Label("Third", systemImage: "terminal")
                }
        }
    }
}

struct ThirdScreen: View {
    @State private var rightNumbers = Array(repeating: 0, count: 44)
    @State private var timerStartDate: Date?
    @State private var independentTimerStartDate: Date?
    @State private var flashingCells: [Int: UUID] = [:]
    @State private var lastCellTapDates: [Int: Date] = [:]

    private let backgroundColor = Color(red: 0.27, green: 0.27, blue: 0.25)
    private let tappableCellNumbers: Set<Int> = [
        10, 11, 12,
        14, 15, 16,
        18, 19, 20,
        22, 23, 24,
        30, 31, 32,
        34, 35, 36,
        38, 39, 40,
        42, 43, 44,
    ]

    var body: some View {
        GeometryReader { geometry in
            let standardRowHeight = geometry.size.height / 8.75

            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(0..<11, id: \.self) { row in
                    GridRow {
                        ForEach(0..<4, id: \.self) { column in
                            let cellNumber = row * 4 + column + 1

                            ZStack {
                                if tappableCellNumbers.contains(cellNumber) {
                                    Button {
                                        incrementCounter(for: cellNumber)
                                    } label: {
                                        Color.clear
                                            .background(
                                                flashingCells[cellNumber] != nil
                                                    ? Color(red: 0.45, green: 0.9, blue: 1.0).opacity(0.3)
                                                    : Color.clear
                                            )
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }

                                cellContent(for: cellNumber)
                                    .allowsHitTesting(false)

                                if row != 0 && row != 1 && row != 6 {
                                    Text(String(cellNumber))
                                        .font(.system(size: 8, design: .monospaced))
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                        .padding(4)
                                        .allowsHitTesting(false)
                                }

                                if cellNumber == 1 {
                                    Button("Reset", action: resetAll)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.red)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .buttonStyle(.plain)
                                }

                                if cellNumber == 6 {
                                    TimelineView(.periodic(from: .now, by: 1)) { context in
                                        Text(timerText(at: context.date, since: timerStartDate))
                                            .font(.system(size: 22.68, weight: .bold, design: .monospaced))
                                            .foregroundStyle(.yellow)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    }
                                }

                                if cellNumber == 8 {
                                    TimelineView(.periodic(from: .now, by: 1)) { context in
                                        Text(timerText(
                                            at: context.date,
                                            since: independentTimerStartDate,
                                            includesHours: true
                                        ))
                                            .font(.system(size: 19.6, weight: .bold, design: .monospaced))
                                            .foregroundStyle(Color(red: 0.45, green: 0.9, blue: 1.0))
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    }
                                }

                                if row != 0 && row != 1 && row != 6 {
                                    if column != 0 {
                                        Text(String(rightNumbers[cellNumber - 1]))
                                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                                            .foregroundStyle(
                                                rightNumbers[cellNumber - 1] > 0
                                                    ? Color(red: 0.45, green: 0.9, blue: 1.0)
                                                    : Color.white
                                            )
                                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                                            .padding(4)
                                            .allowsHitTesting(false)
                                    }

                                    if column != 0 {
                                        HStack(spacing: 4) {
                                            if !tappableCellNumbers.contains(cellNumber) {
                                                counterButton("+") {
                                                    incrementCounter(for: cellNumber)
                                                }
                                            } else {
                                                Color.clear
                                                    .frame(maxWidth: .infinity)
                                                    .frame(height: 23.66)
                                            }

                                            counterButton("−") {
                                                guard rightNumbers[cellNumber - 1] > 0 else { return }
                                                rightNumbers[cellNumber - 1] -= 1
                                            }
                                        }
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                                        .padding(.bottom, 3)
                                    }
                                }
                            }
                                .frame(maxWidth: .infinity)
                                .frame(width: column == 0 ? firstColumnWidth : nil)
                                .frame(height: row == 0 || row == 1 || row == 6 ? standardRowHeight / 4 : standardRowHeight)
                                .scaleEffect(
                                    tappableCellNumbers.contains(cellNumber) && flashingCells[cellNumber] != nil
                                        ? 0.96
                                        : 1
                                )
                                .animation(
                                    .spring(response: 0.18, dampingFraction: 0.6),
                                    value: flashingCells[cellNumber]
                                )
                                .background(columnColor(for: column, row: row))
                                .overlay {
                                    Rectangle()
                                        .stroke(Color.white, lineWidth: 1)
                                }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundColor)
        .foregroundStyle(.white)
    }

    private func counterButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .frame(maxWidth: .infinity)
                .frame(height: 23.66)
                .background(Color.black.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    private func timerText(
        at date: Date,
        since startDate: Date?,
        includesHours: Bool = false
    ) -> String {
        guard let startDate else {
            return includesHours ? "00:00:00" : "00:00"
        }

        let elapsedSeconds = max(0, Int(date.timeIntervalSince(startDate)))
        if includesHours {
            let hours = elapsedSeconds / 3_600
            let minutes = (elapsedSeconds / 60) % 60
            let seconds = elapsedSeconds % 60
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%02d:%02d", elapsedSeconds / 60, elapsedSeconds % 60)
    }

    private func resetAll() {
        rightNumbers = Array(repeating: 0, count: rightNumbers.count)
        timerStartDate = nil
        independentTimerStartDate = nil
        flashingCells.removeAll()
        lastCellTapDates.removeAll()
    }

    private func incrementCounter(for cellNumber: Int) {
        let now = Date()

        if tappableCellNumbers.contains(cellNumber) {
            if let lastTapDate = lastCellTapDates[cellNumber],
               now.timeIntervalSince(lastTapDate) < 1 {
                return
            }

            lastCellTapDates[cellNumber] = now
        }

        timerStartDate = now
        if independentTimerStartDate == nil {
            independentTimerStartDate = now
        }
        rightNumbers[cellNumber - 1] += 1

        if tappableCellNumbers.contains(cellNumber) {
            let flashID = UUID()
            flashingCells[cellNumber] = flashID

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                guard flashingCells[cellNumber] == flashID else { return }
                flashingCells[cellNumber] = nil
            }
        }
    }

    private var firstColumnWidth: CGFloat {
        let labels = ["Reset", "спина", "бицепс", "ноги", "грудь", "трицепс"]
        let labelFont = UIFont.preferredFont(forTextStyle: .title2)

        return ceil(labels.map {
            ($0 as NSString).size(withAttributes: [.font: labelFont]).width
        }.max() ?? 0)
    }

    @ViewBuilder
    private func cellContent(for number: Int) -> some View {
        if let label = [
            10: "подтягивания",
            11: "сверху под 45гр",
            12: "сидя узкий хват",
            14: "молотковый хват",
            15: "сидя снизу-вверх",
            16: "z-гриф",
            18: "развод",
            19: "свод",
            20: "плечи вверх",
            22: "пресс",
            23: "пресс",
            24: "пресс",
            30: "вверх",
            31: "сводящие, не толкающие",
            32: "отжим на брусьях",
            34: "вверх",
            35: "из положения лежа на спине",
            36: "вниз",
            38: "вперед",
            39: "приседы",
            40: "назад",
            42: "пресс",
            43: "пресс",
            44: "пресс",
        ][number] {
            VStack(spacing: -7) {
                ForEach(labelLines(for: number, label: label), id: \.self) { line in
                    Text(line)
                        .font(
                            number == 31 || number == 35
                                ? .system(size: 15.4)
                                : number == 12 || number == 15
                                    ? .system(size: 21.28896)
                                    : .title2
                        )
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Text(cellLabel(for: number))
                .font(.title2.monospacedDigit())
        }
    }

    private func labelLines(for number: Int, label: String) -> [String] {
        switch number {
        case 10: return ["подтяги-", "вания"]
        case 11: return ["сверху", "под 45гр"]
        case 12: return ["сидя", "узкий", "хват"]
        case 14: return ["молотко-", "вый хват"]
        case 15: return ["сидя", "снизу-", "вверх"]
        case 20: return ["плечи", "вверх"]
        case 31: return ["сводящие,", "не", "толкающие"]
        case 32: return ["отжим на", "брусьях"]
        case 35: return ["из положения", "лежа на", "спине"]
        default: return [label]
        }
    }

    private func columnColor(for column: Int, row: Int) -> Color {
        guard row != 0, row != 1, row != 6 else {
            return backgroundColor
        }

        switch column {
        case 1: return Color(red: 0.48, green: 0.29, blue: 0.00)
        case 2: return Color(red: 0.48, green: 0.00, blue: 0.29)
        case 3: return Color(red: 0.08, green: 0.27, blue: 0.08)
        default: return backgroundColor
        }
    }

    private func cellLabel(for number: Int) -> String {
        switch number {
        case 1: ""
        case 2: "Up"
        case 3: "Middle"
        case 4: "Down"
        case 5...8, 25...28: ""
        case 9: "спина"
        case 13: "бицепс"
        case 17: "ноги"
        case 29: "грудь"
        case 33: "трицепс"
        case 37: "ноги"
        default: ""
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
