import AVFoundation
import Combine
import Foundation
import SwiftUI
import UIKit

struct SportTrackerView: View {
    @State private var rightNumbers = Array(repeating: 0, count: 48)
    @State private var timerStartDate: Date?
    @State private var independentTimerStartDate: Date?
    @State private var flashingCells: [Int: UUID] = [:]
    @State private var lastCellTapDates: [Int: Date] = [:]
    @State private var didPlayOneMinuteSound = false
    @State private var sportTrackerAudioPlayer: AVAudioPlayer?

    private let oneMinuteSoundTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

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
            let standardRowHeight = geometry.size.height / 9.65375

            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(0..<12, id: \.self) { row in
                    GridRow {
                        ForEach(0..<4, id: \.self) { column in
                            let cellNumber = row * 4 + column + 1

                            ZStack {
                                if tappableCellNumbers.contains(cellNumber) {
                                    Button {
                                        incrementCounter(for: cellNumber)
                                    } label: {
                                        Color.clear
                                            // Brief Color Flash: temporarily adds a light-cyan tint
                                            // after an accepted tap.
                                            .background(
                                                flashingCells[cellNumber] != nil
                                                    ? Color(red: 0.45, green: 0.9, blue: 1.0).opacity(0.3)
                                                    : Color.clear
                                            )
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)

                                    CellColorFillEffect(trigger: flashingCells[cellNumber])
                                        .allowsHitTesting(false)
                                }

                                cellContent(for: cellNumber)
                                    .allowsHitTesting(false)

                                if tappableCellNumbers.contains(cellNumber) {
                                    CellRippleEffect(trigger: flashingCells[cellNumber])
                                        .allowsHitTesting(false)

                                    CellParticleBurstEffect(trigger: flashingCells[cellNumber])
                                        .allowsHitTesting(false)

                                    CellCooldownRingEffect(trigger: flashingCells[cellNumber])
                                        .allowsHitTesting(false)
                                }

                                if row != 0 && row != 1 && row != 6 && row != 11 {
                                    Text(String(cellNumber))
                                        .font(.system(size: 8, design: .monospaced))
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                        .padding(4)
                                        .allowsHitTesting(false)
                                }

                                if cellNumber == 1 {
                                    Button("Reset", action: resetAll)
                                        .font(.title2.monospacedDigit())
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .buttonStyle(.plain)
                                }

                                if cellNumber == 6 {
                                    TimelineView(.periodic(from: .now, by: 1)) { context in
                                        Text(timerText(at: context.date, since: timerStartDate))
                                            .font(.system(size: 32.34, weight: .bold, design: .monospaced))
                                            .foregroundStyle(.yellow)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    }
                                }

                                if cellNumber == 8 {
                                    TimelineView(.periodic(from: .now, by: 1)) { context in
                                        Text(timerText(at: context.date, since: independentTimerStartDate))
                                            .font(.system(size: 32.34, weight: .bold, design: .monospaced))
                                            .foregroundStyle(Color(red: 0.45, green: 0.9, blue: 1.0))
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    }
                                }

                                if row != 0 && row != 1 && row != 6 && row != 11 {
                                    if column != 0 {
                                        Text(String(rightNumbers[cellNumber - 1]))
                                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                                            .foregroundStyle(
                                                rightNumbers[cellNumber - 1] > 0
                                                    ? Color(red: 1.0, green: 0.95, blue: 0.05)
                                                    : Color.blue
                                            )
                                            .opacity(rightNumbers[cellNumber - 1] > 0 ? 1 : 0)
                                            .shadow(
                                                color: rightNumbers[cellNumber - 1] > 0
                                                    ? Color.yellow.opacity(0.9)
                                                    : Color.clear,
                                                radius: 4
                                            )
                                            // Counter Bounce: enlarges the counter briefly,
                                            // then returns it with a spring animation.
                                            .scaleEffect(flashingCells[cellNumber] != nil ? 1.4 : 1)
                                            .animation(
                                                .spring(response: 0.2, dampingFraction: 0.5),
                                                value: flashingCells[cellNumber]
                                            )
                                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                                            .padding(4)
                                            .allowsHitTesting(false)
                                    }

                                    if column != 0 {
                                        GeometryReader { buttonGeometry in
                                            let spacing: CGFloat = 4
                                            let originalButtonWidth = (buttonGeometry.size.width - spacing) / 2
                                            let minusButtonWidth = originalButtonWidth * 0.7
                                            let plusButtonWidth =
                                                buttonGeometry.size.width - spacing - minusButtonWidth

                                            HStack(spacing: spacing) {
                                                if !tappableCellNumbers.contains(cellNumber) {
                                                    counterButton("+") {
                                                        incrementCounter(for: cellNumber)
                                                    }
                                                    .frame(width: plusButtonWidth)
                                                } else {
                                                    Color.clear
                                                        .frame(width: plusButtonWidth)
                                                        .frame(height: 23.66)
                                                }

                                                counterButton("−") {
                                                    guard rightNumbers[cellNumber - 1] > 0 else { return }
                                                    rightNumbers[cellNumber - 1] -= 1
                                                }
                                                .frame(width: minusButtonWidth)
                                            }
                                        }
                                        .frame(height: 23.66)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                                        .padding(.bottom, 3)
                                    }
                                }
                            }
                                .frame(maxWidth: .infinity)
                                .frame(width: column == 0 ? firstColumnWidth : nil)
                                .frame(
                                    height: row == 1
                                            ? standardRowHeight * 27 / 32
                                        : row == 0 || row == 6 || row == 11
                                            ? standardRowHeight * 27 / 100
                                            : standardRowHeight
                                )
                                // Scale Animation: slightly shrinks an accepted cell,
                                // then springs it back to its normal size.
                                .scaleEffect(
                                    tappableCellNumbers.contains(cellNumber) && flashingCells[cellNumber] != nil
                                        ? 0.96
                                        : 1
                                )
                                // Glow: briefly adds a light-cyan shadow around
                                // an accepted cell.
                                .shadow(
                                    color: flashingCells[cellNumber] != nil
                                        ? Color(red: 0.45, green: 0.9, blue: 1.0).opacity(0.9)
                                        : Color.clear,
                                    radius: 12
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
        .onReceive(oneMinuteSoundTimer) { now in
            playOneMinuteSoundIfNeeded(at: now)
        }
        .onDisappear {
            sportTrackerAudioPlayer?.stop()
        }
    }

    private func counterButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .frame(maxWidth: .infinity)
                .frame(height: 23.66)
                .background(Color.black.opacity(title == "−" ? 0.1728 : 0.3))
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
        didPlayOneMinuteSound = false
        sportTrackerAudioPlayer?.stop()
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
        didPlayOneMinuteSound = false
        sportTrackerAudioPlayer?.stop()
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

    private func playOneMinuteSoundIfNeeded(at now: Date) {
        guard let timerStartDate,
              !didPlayOneMinuteSound,
              now.timeIntervalSince(timerStartDate) > 60 else { return }

        didPlayOneMinuteSound = true
        guard let soundURL = Bundle.main.url(
            forResource: "sport-tracker-audio",
            withExtension: "m4a"
        ) else { return }

        do {
            let player = try AVAudioPlayer(contentsOf: soundURL)
            player.prepareToPlay()
            sportTrackerAudioPlayer = player
            player.play()
        } catch {
            sportTrackerAudioPlayer = nil
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
            18: "плечи вверх",
            19: "развод",
            20: "свод",
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
                                ? .system(size: 18.634)
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
        case 18: return ["плечи", "вверх"]
        case 31: return ["сводящие,", "не тол-", "кающие"]
        case 32: return ["отжим на", "брусьях"]
        case 35: return ["из положе-", "ния лежа", "на спине"]
        default: return [label]
        }
    }

    private func columnColor(for column: Int, row: Int) -> Color {
        guard row != 0, row != 1, row != 6, row != 11 else {
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

// MARK: - Tappable Cell Effects
//
// Implemented effect names:
// - Brief Color Flash: temporarily tints an accepted cell light cyan.
// - Scale Animation: shrinks an accepted cell and springs it back.
// - Counter Bounce: enlarges the changed counter and springs it back.
// - Glow: adds a temporary light-cyan shadow around an accepted cell.
// - Ripple Effect: expands and fades a cyan ring from the cell center.
// - Color Fill: fills the cell upward with cyan, then fades it out.
// - Particle Burst: emits ten cyan particles from the cell center.
// - Progress Ring: visualizes the one-second cooldown with an emptying ring.

/// Ripple Effect: expands a cyan ring from the center of a cell after
/// an accepted tap, then fades the ring out.
private struct CellRippleEffect: View {
    let trigger: UUID?

    @State private var progress: CGFloat = 1

    var body: some View {
        Circle()
            .stroke(Color(red: 0.45, green: 0.9, blue: 1.0), lineWidth: 2)
            .scaleEffect(0.15 + progress * 1.35)
            .opacity(1 - progress)
            .onChange(of: trigger) { newTrigger in
                guard newTrigger != nil else { return }

                progress = 0
                withAnimation(.easeOut(duration: 0.45)) {
                    progress = 1
                }
            }
    }
}

/// Color Fill: fills a cell from bottom to top with light cyan after
/// an accepted tap, then fades the fill out.
private struct CellColorFillEffect: View {
    let trigger: UUID?

    @State private var progress: CGFloat = 0
    @State private var fillOpacity = 0.0

    var body: some View {
        Rectangle()
            .fill(Color(red: 0.45, green: 0.9, blue: 1.0).opacity(0.35))
            .scaleEffect(x: 1, y: progress, anchor: .bottom)
            .opacity(fillOpacity)
            .onChange(of: trigger) { newTrigger in
                guard newTrigger != nil else { return }

                progress = 0
                fillOpacity = 1
                withAnimation(.easeOut(duration: 0.22)) {
                    progress = 1
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        fillOpacity = 0
                    }
                }
            }
    }
}

/// Particle Burst: emits ten cyan particles outward from the center
/// of a cell after an accepted tap.
private struct CellParticleBurstEffect: View {
    let trigger: UUID?

    @State private var progress: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            let distance = min(geometry.size.width, geometry.size.height) * 0.42

            ZStack {
                ForEach(0..<10, id: \.self) { particle in
                    let angle = Double(particle) / 10 * Double.pi * 2

                    Circle()
                        .fill(Color(red: 0.45, green: 0.9, blue: 1.0))
                        .frame(width: 5, height: 5)
                        .scaleEffect(1 - progress * 0.6)
                        .offset(
                            x: CGFloat(cos(angle)) * distance * progress,
                            y: CGFloat(sin(angle)) * distance * progress
                        )
                        .opacity(1 - progress)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: trigger) { newTrigger in
            guard newTrigger != nil else { return }

            progress = 0
            withAnimation(.easeOut(duration: 0.5)) {
                progress = 1
            }
        }
    }
}

/// Progress Ring: displays a cyan ring that empties over one second
/// to show when the cell's tap cooldown will finish.
private struct CellCooldownRingEffect: View {
    let trigger: UUID?

    @State private var progress: CGFloat = 1

    var body: some View {
        Circle()
            .trim(from: progress, to: 1)
            .stroke(
                Color(red: 0.45, green: 0.9, blue: 1.0).opacity(0.9),
                style: StrokeStyle(lineWidth: 3, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
            .padding(6)
            .onChange(of: trigger) { newTrigger in
                guard newTrigger != nil else { return }

                progress = 0
                withAnimation(.linear(duration: 1)) {
                    progress = 1
                }
            }
    }
}
