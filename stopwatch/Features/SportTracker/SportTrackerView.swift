import Combine
import Foundation
import SwiftUI
import UIKit

struct SportTrackerView: View {
    @StateObject private var model = SportTrackerModel()

    private let soundTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private let backgroundColor = Color(red: 0.27, green: 0.27, blue: 0.25)
    private let tappableCellNumbers = SportTrackerModel.tappableCellNumbers

    var body: some View {
        GeometryReader { geometry in
            let standardRowHeight = geometry.size.height / 7.65375

            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach([0, 1, 2, 3, 4, 6, 7, 8, 9, 11], id: \.self) { row in
                    GridRow {
                        ForEach(0..<4, id: \.self) { column in
                            let cellNumber = row * 4 + column + 1

                            ZStack {
                                if tappableCellNumbers.contains(cellNumber) {
                                    Button {
                                        model.incrementCounter(for: cellNumber)
                                    } label: {
                                        Color.clear
                                            // Brief Color Flash: temporarily adds a light-cyan tint
                                            // after an accepted tap.
                                            .background(
                                                model.flashingCells[cellNumber] != nil
                                                    ? Color(red: 0.45, green: 0.9, blue: 1.0).opacity(0.3)
                                                    : Color.clear
                                            )
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)

                                    CellColorFillEffect(trigger: model.flashingCells[cellNumber])
                                        .allowsHitTesting(false)
                                }

                                cellContent(for: cellNumber)
                                    .allowsHitTesting(false)

                                if tappableCellNumbers.contains(cellNumber) {
                                    CellRippleEffect(trigger: model.flashingCells[cellNumber])
                                        .allowsHitTesting(false)

                                    CellParticleBurstEffect(trigger: model.flashingCells[cellNumber])
                                        .allowsHitTesting(false)

                                    CellCooldownRingEffect(trigger: model.flashingCells[cellNumber])
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
                                    Button("Reset", action: model.resetAll)
                                        .font(.title2.monospacedDigit())
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .buttonStyle(.plain)
                                }

                                if cellNumber == 5 {
                                    Button(action: model.incrementSoundInterval) {
                                        Text(String(model.soundIntervalMinutes))
                                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Sound interval in minutes")
                                    .accessibilityValue("\(model.soundIntervalMinutes)")
                                    .accessibilityHint("Increases the sound interval by one minute")
                                }

                                if cellNumber == 6 {
                                    TimelineView(.periodic(from: .now, by: 1)) { context in
                                        Text(timerText(at: context.date, since: model.timerStartDate))
                                            .font(.system(size: 32.34, weight: .bold, design: .monospaced))
                                            .foregroundStyle(.yellow)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    }
                                }

                                if cellNumber == 8 {
                                    TimelineView(.periodic(from: .now, by: 1)) { context in
                                        Text(timerText(at: context.date, since: model.independentTimerStartDate))
                                            .font(.system(size: 32.34, weight: .bold, design: .monospaced))
                                            .foregroundStyle(Color(red: 0.45, green: 0.9, blue: 1.0))
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    }
                                }

                                if row != 0 && row != 1 && row != 6 && row != 11 {
                                    if column != 0 {
                                        Text(String(model.rightNumbers[cellNumber - 1]))
                                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                                            .foregroundStyle(
                                                model.rightNumbers[cellNumber - 1] > 0
                                                    ? Color(red: 1.0, green: 0.95, blue: 0.05)
                                                    : Color.blue
                                            )
                                            .opacity(model.rightNumbers[cellNumber - 1] > 0 ? 1 : 0)
                                            .shadow(
                                                color: model.rightNumbers[cellNumber - 1] > 0
                                                    ? Color.yellow.opacity(0.9)
                                                    : Color.clear,
                                                radius: 4
                                            )
                                            // Counter Bounce: enlarges the counter briefly,
                                            // then returns it with a spring animation.
                                            .scaleEffect(model.flashingCells[cellNumber] != nil ? 1.4 : 1)
                                            .animation(
                                                .spring(response: 0.2, dampingFraction: 0.5),
                                                value: model.flashingCells[cellNumber]
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
                                                        model.incrementCounter(for: cellNumber)
                                                    }
                                                    .frame(width: plusButtonWidth)
                                                } else {
                                                    Color.clear
                                                        .frame(width: plusButtonWidth)
                                                        .frame(height: 23.66)
                                                }

                                                counterButton("−") {
                                                    model.decrementCounter(for: cellNumber)
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
                                    tappableCellNumbers.contains(cellNumber)
                                        && model.flashingCells[cellNumber] != nil
                                        ? 0.96
                                        : 1
                                )
                                // Glow: briefly adds a light-cyan shadow around
                                // an accepted cell.
                                .shadow(
                                    color: model.flashingCells[cellNumber] != nil
                                        ? Color(red: 0.45, green: 0.9, blue: 1.0).opacity(0.9)
                                        : Color.clear,
                                    radius: 12
                                )
                                .animation(
                                    .spring(response: 0.18, dampingFraction: 0.6),
                                    value: model.flashingCells[cellNumber]
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
        .onReceive(soundTimer) { now in
            model.playSoundIfNeeded(at: now)
        }
        .onDisappear {
            model.stopAudio()
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

    private var firstColumnWidth: CGFloat {
        let labels = ["Reset", "спина", "бицепс", "ноги", "грудь", "трицепс"]
        let labelFont = UIFont.preferredFont(forTextStyle: .title2)

        return ceil(labels.map {
            ($0 as NSString).size(withAttributes: [.font: labelFont]).width
        }.max() ?? 0)
    }

    @ViewBuilder
    private func cellContent(for number: Int) -> some View {
        if number == 17 || number == 37 {
            VStack(spacing: 0) {
                Text("ноги,")
                    .font(.title2)
                Text(number == 37 ? "предплечье ладонь вверх" : "предплечье ладонь вниз")
                    .font(.system(size: 11))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let label = [
            10: "подтягивания",
            11: "сверху под 45гр",
            12: "сидя узкий хват",
            14: "молотковый хват",
            15: "сидя снизу-вверх",
            16: "z-гриф",
            18: "плечи вверх",
            19: "развод",
            20: "свод",
            30: "вверх",
            31: "сводящие, не толкающие",
            32: "отжим на брусьях",
            34: "вверх",
            35: "из положения лежа на спине",
            36: "вниз",
            38: "вперед",
            39: "приседы",
            40: "назад",
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
        case 17: "ноги, предплечье ладонь вниз"
        case 29: "грудь"
        case 33: "трицепс"
        case 37: "ноги, предплечье ладонь вверх"
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
