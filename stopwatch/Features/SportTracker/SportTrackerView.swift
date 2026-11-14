import Combine
import Foundation
import SwiftUI
import UIKit

struct SportTrackerView: View {
    @StateObject private var model = SportTrackerModel()
    @State private var activeExercisePreview: ExercisePreview?

    private static let fiveLDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM"
        return formatter
    }()

    private let soundTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private let backgroundColor = Color(red: 0.27, green: 0.27, blue: 0.25)
    private let tappableCellNumbers = SportTrackerModel.tappableCellNumbers

    var body: some View {
        GeometryReader { geometry in
            let standardRowHeight = geometry.size.height / 7.65375
            let displayedRows = [0, 1, 2, 3, 4, 6, 7, 9, 10, 11]

            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(Array(displayedRows.enumerated()), id: \.offset) { rowEntry in
                    let rowNumber = rowEntry.offset + 1
                    let row = rowEntry.element

                    GridRow {
                        ForEach(0..<4, id: \.self) { column in
                            let cellNumber = row * 4 + column + 1

                            ZStack {
                                if tappableCellNumbers.contains(cellNumber) {
                                    if let preview = exercisePreview(for: cellNumber) {
                                        ExercisePressArea(
                                            onTap: {
                                                model.incrementCounter(for: cellNumber)
                                            },
                                            onHoldChanged: { isHolding in
                                                activeExercisePreview = isHolding ? preview : nil
                                            }
                                        )
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    } else {
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
                                    }

                                    CellColorFillEffect(trigger: model.flashingCells[cellNumber])
                                        .allowsHitTesting(false)
                                }

                                if cellNumber == 25 || cellNumber == 26
                                    || cellNumber == 27 || cellNumber == 28
                                    || cellNumber == 29 || cellNumber == 30
                                    || cellNumber == 31 || cellNumber == 32 {
                                    Button {
                                        model.markDatedLabel(in: cellNumber)
                                    } label: {
                                        Color.clear
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!model.canMarkDatedLabel(in: cellNumber))
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

                                HStack(spacing: 3) {
                                    Text(String(cellNumber))
                                    if column == 0 {
                                        Text(String(rowNumber))
                                            .foregroundStyle(Color(red: 0.45, green: 0.9, blue: 1.0))
                                    }
                                }
                                    .font(.system(size: 8, design: .monospaced))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    .padding(4)
                                    .allowsHitTesting(false)

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
                                    VStack(spacing: 0) {
                                        Button(action: model.resetAll) {
                                            Text("Reset")
                                                .font(.headline.monospacedDigit())
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.65)
                                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                                        Divider()

                                        TimelineView(.periodic(from: .now, by: 1)) { context in
                                            Text(timerText(at: context.date, since: model.timerStartDate))
                                                .font(.system(size: 32.34, weight: .bold, design: .monospaced))
                                                .minimumScaleFactor(0.5)
                                                .lineLimit(1)
                                                .foregroundStyle(.yellow)
                                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        }
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }

                                if cellNumber == 8 {
                                    VStack(spacing: 0) {
                                        Button(action: model.resetDatedLabels) {
                                            Text("Reset datas")
                                                .font(.headline)
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.65)
                                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                                        Divider()

                                        TimelineView(.periodic(from: .now, by: 1)) { context in
                                            Text(timerText(at: context.date, since: model.independentTimerStartDate))
                                                .font(.system(size: 32.34, weight: .bold, design: .monospaced))
                                                .minimumScaleFactor(0.5)
                                                .lineLimit(1)
                                                .foregroundStyle(Color(red: 0.45, green: 0.9, blue: 1.0))
                                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        }
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }

                                if row != 0 && row != 1 && row != 6 && row != 7 {
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
                                .frame(height: standardRowHeight * rowHeightMultiplier(for: row))
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
        .padding(.bottom, 24)
        .background(backgroundColor)
        .foregroundStyle(.white)
        .overlay {
            if let preview = activeExercisePreview {
                ZStack {
                    Color.black.opacity(0.65)

                    VStack(spacing: 8) {
                        Text(preview.fileName)
                            .font(.headline)
                            .foregroundStyle(.white)

                        Image(preview.assetName)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .padding(20)
                }
                .allowsHitTesting(false)
            }
        }
        .onReceive(soundTimer) { now in
            model.playSoundIfNeeded(at: now)
        }
        .onDisappear {
            model.stopAudio()
        }
    }

    private func exercisePreview(for cellNumber: Int) -> ExercisePreview? {
        switch cellNumber {
        case 10:
            ExercisePreview(
                assetName: "spina-podtyagivaniya",
                fileName: "spina-podtyagivaniya.JPG"
            )
        case 39:
            ExercisePreview(
                assetName: "grud-middle",
                fileName: "grud-middle.JPG"
            )
        case 43:
            ExercisePreview(
                assetName: "triceps-leza",
                fileName: "triceps-leza.JPG"
            )
        default:
            nil
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

    private func rowHeightMultiplier(for row: Int) -> CGFloat {
        let otherRowsScale: CGFloat = 0.9666

        if row == 6 || row == 7 {
            return 0.27 * 1.44
        }
        if row == 1 {
            return 0.84375 * otherRowsScale
        }
        if row == 0 {
            return 0.27 * otherRowsScale
        }
        return otherRowsScale
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
        if number == 25 || number == 26 || number == 27 || number == 28
            || number == 29 || number == 30 || number == 31 || number == 32 {
            datedLabelText(for: number)
                .font(.title2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } else if number == 17 || number == 45 {
            VStack(spacing: 0) {
                Text("ноги,")
                    .font(.title2)
                if number == 45 {
                    Text("ладонь\nвверх")
                        .font(.system(size: 16.5))
                        .foregroundStyle(.yellow)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                } else {
                    Text("ладонь\nвниз")
                        .font(.system(size: 16.5))
                        .foregroundStyle(.yellow)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
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
            25: "5L",
            38: "вверх",
            39: "сводящие, не толкающие",
            40: "отжим на брусьях",
            42: "вверх",
            43: "из положения лежа на спине",
            44: "вниз",
            46: "вперед",
            47: "приседы",
            48: "назад",
        ][number] {
            VStack(spacing: -7) {
                ForEach(labelLines(for: number, label: label), id: \.self) { line in
                    Text(line)
                        .font(
                            number == 39 || number == 43
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

    private func datedLabelText(for cellNumber: Int) -> Text {
        let label: String
        let date: Date?

        if cellNumber == 28 || cellNumber == 32 {
            label = "6H"
            date = cellNumber == 28 ? model.sixHDate28 : model.sixHDate32
        } else if cellNumber == 27 || cellNumber == 31 {
            label = "6L"
            date = cellNumber == 27 ? model.sixLDate27 : model.sixLDate31
        } else if cellNumber == 26 || cellNumber == 30 {
            label = "5H"
            date = cellNumber == 26 ? model.fiveHDate26 : model.fiveHDate30
        } else {
            label = "5L"
            date = cellNumber == 25 ? model.fiveLDate : model.fiveLDate29
        }

        if let date {
            return Text(label + " " + Self.fiveLDateFormatter.string(from: date))
        }

        guard model.canMarkDatedLabel(in: cellNumber) else {
            return Text(label)
        }

        let currentDate = Self.fiveLDateFormatter.string(from: Date())
        return Text(label + " ")
            + Text(currentDate)
                .foregroundColor(Color(red: 0.55, green: 1.0, blue: 0.55))
    }

    private func labelLines(for number: Int, label: String) -> [String] {
        switch number {
        case 10: return ["подтяги-", "вания"]
        case 11: return ["сверху", "под 45гр"]
        case 12: return ["сидя", "узкий", "хват"]
        case 14: return ["молотко-", "вый хват"]
        case 15: return ["сидя", "снизу-", "вверх"]
        case 18: return ["плечи", "вверх"]
        case 39: return ["сводящие,", "не тол-", "кающие"]
        case 40: return ["отжим на", "брусьях"]
        case 43: return ["из положе-", "ния лежа", "на спине"]
        default: return [label]
        }
    }

    private func columnColor(for column: Int, row: Int) -> Color {
        guard row != 0, row != 1, row != 6, row != 7 else {
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
        case 5...8, 25...36: ""
        case 9: "спина"
        case 13: "бицепс"
        case 17: "ноги, ладонь вниз"
        case 37: "грудь"
        case 41: "трицепс"
        case 45: "ноги, ладонь вверх"
        default: ""
        }
    }
}

private struct ExercisePreview {
    let assetName: String
    let fileName: String
}

private struct ExercisePressArea: UIViewRepresentable {
    let onTap: () -> Void
    let onHoldChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap, onHoldChanged: onHoldChanged)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.5

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap)
        )
        tap.require(toFail: longPress)

        view.addGestureRecognizer(longPress)
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onHoldChanged = onHoldChanged
    }

    final class Coordinator: NSObject {
        var onTap: () -> Void
        var onHoldChanged: (Bool) -> Void

        init(onTap: @escaping () -> Void, onHoldChanged: @escaping (Bool) -> Void) {
            self.onTap = onTap
            self.onHoldChanged = onHoldChanged
        }

        @objc func handleTap() {
            onTap()
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            switch recognizer.state {
            case .began:
                onHoldChanged(true)
            case .ended, .cancelled, .failed:
                onHoldChanged(false)
            default:
                break
            }
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
