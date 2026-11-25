import Combine
import Foundation
import SwiftUI
import UIKit

struct SportTrackerView: View {
    let provisioningTimeRemaining: String

    private static let selectedHeaderCellStateKey = "sport-tracker-selected-header-cell"

    @StateObject private var model = SportTrackerModel()
    @StateObject private var volumeController = SystemVolumeController()
    @State private var activeExercisePreview: ExercisePreview?
    @State private var areGridNumbersVisible = true
    @State private var selectedHeaderCell: Int?

    private static let fiveLDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM"
        return formatter
    }()

    private let soundTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let volumeTimer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    private let backgroundColor = Color(red: 0.27, green: 0.27, blue: 0.25)
    private let tappableCellNumbers = SportTrackerModel.tappableCellNumbers

    init(provisioningTimeRemaining: String) {
        self.provisioningTimeRemaining = provisioningTimeRemaining

        let savedSelection = PersistentAppState.load(
            Int.self,
            forKey: Self.selectedHeaderCellStateKey
        )
        _selectedHeaderCell = State(
            initialValue: savedSelection.flatMap { 2...4 ~= $0 ? $0 : nil }
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let standardRowHeight = geometry.size.height / 7.65375
            let displayedRows = SportTrackerCellCatalog.displayedRows

            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(Array(displayedRows.enumerated()), id: \.offset) { rowEntry in
                    let rowNumber = rowEntry.offset + 1
                    let row = rowEntry.element

                    GridRow {
                        ForEach(0..<4, id: \.self) { column in
                            let cellNumber = row * 4 + column + 1

                            ZStack {
                                if tappableCellNumbers.contains(cellNumber) {
                                    ExerciseCellControl(
                                        preview: exercisePreview(for: cellNumber),
                                        flashTrigger: model.flashingCells[cellNumber],
                                        onTap: { model.incrementCounter(for: cellNumber) },
                                        onHoldChanged: { preview, isHolding in
                                            activeExercisePreview = isHolding ? preview : nil
                                        }
                                    ) {
                                        cellContent(for: cellNumber)
                                    }
                                }

                                if SportTrackerCellCatalog.datedCellNumbers.contains(cellNumber) {
                                    Button {
                                        model.markDatedLabel(in: cellNumber)
                                    } label: {
                                        Color.clear
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!model.canMarkDatedLabel(in: cellNumber))
                                }

                                if !(2...4 ~= cellNumber)
                                    && !tappableCellNumbers.contains(cellNumber) {
                                    cellContent(for: cellNumber)
                                        .allowsHitTesting(false)
                                }

                                if areGridNumbersVisible {
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
                                }

                                if cellNumber == 1 {
                                    GridNumbersControl(isVisible: $areGridNumbersVisible)
                                }

                                if 2...4 ~= cellNumber {
                                    HeaderSelectionControl(
                                        cellNumber: cellNumber,
                                        label: cellLabel(for: cellNumber),
                                        selection: $selectedHeaderCell
                                    )
                                }

                                if cellNumber == 5 {
                                    SoundIntervalControl(
                                        minutes: model.soundIntervalMinutes,
                                        onIncrement: model.incrementSoundInterval,
                                        onDecrement: model.decrementSoundInterval
                                    )
                                }

                                if cellNumber == 6 {
                                    ResetTimerControl(
                                        title: "Reset",
                                        startDate: model.timerStartDate,
                                        timerColor: .yellow,
                                        onReset: model.resetAll
                                    )
                                }

                                if cellNumber == 7 {
                                    VolumeProvisioningControl(
                                        percentage: volumeController.volumePercentage,
                                        isMaximumEnabled: volumeController.isMaximumVolumeEnabled,
                                        provisioningTimeRemaining: provisioningTimeRemaining,
                                        onToggle: volumeController.toggleMaximumVolume
                                    )
                                }

                                if cellNumber == 8 {
                                    ResetTimerControl(
                                        title: "Reset dates",
                                        startDate: model.independentTimerStartDate,
                                        timerColor: Color(red: 0.45, green: 0.9, blue: 1.0),
                                        onReset: model.resetDatedLabels
                                    )
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
                                            let displayedPlusButtonWidth =
                                                cellNumber == 2 ? minusButtonWidth : plusButtonWidth

                                            HStack(spacing: spacing) {
                                                if !tappableCellNumbers.contains(cellNumber) {
                                                    SportCounterButton(title: "+") {
                                                        model.incrementCounter(for: cellNumber)
                                                    }
                                                    .frame(width: displayedPlusButtonWidth)
                                                } else {
                                                    Color.clear
                                                        .frame(width: displayedPlusButtonWidth)
                                                        .frame(height: 23.66)
                                                }

                                                SportCounterButton(title: "−") {
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

                    HStack(spacing: 12) {
                        ForEach(preview.images) { previewImage in
                            VStack(spacing: 8) {
                                Text(previewImage.fileName)
                                    .font(.headline)
                                    .foregroundStyle(.white)

                                Image(previewImage.assetName)
                                    .resizable()
                                    .scaledToFit()
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(20)
                }
                .allowsHitTesting(false)
            }
        }
        .onReceive(soundTimer) { now in
            model.playSoundIfNeeded(at: now)
        }
        .onReceive(volumeTimer) { _ in
            volumeController.refreshCurrentVolume()
        }
        .onChange(of: selectedHeaderCell) { _, newValue in
            PersistentAppState.save(
                newValue ?? 0,
                forKey: Self.selectedHeaderCellStateKey
            )
        }
        .onDisappear {
            model.stopAudio()
        }
    }

    private func exercisePreview(for cellNumber: Int) -> ExercisePreview? {
        SportTrackerCellCatalog.definition(for: cellNumber)?.exercisePreview
    }

    private func rowHeightMultiplier(for row: Int) -> CGFloat {
        let otherRowsScale: CGFloat = 0.9666
        let originalTotalHeightMultiplier: CGFloat = 7.65375
        let originalFirstRowHeight = 0.27 * otherRowsScale
        let doubledFirstRowHeight = originalFirstRowHeight * 2
        let remainingRowsScale =
            (originalTotalHeightMultiplier - doubledFirstRowHeight)
            / (originalTotalHeightMultiplier - originalFirstRowHeight)
        let originalSpecialRowsHeight = 2 * 0.27 * 1.44
        let enlargedSpecialRowHeight = 0.27 * 1.44 * remainingRowsScale * 1.2
        let otherRowsOriginalHeight =
            originalTotalHeightMultiplier
            - originalFirstRowHeight
            - originalSpecialRowsHeight
        let adjustedOtherRowsScale =
            (originalTotalHeightMultiplier
                - doubledFirstRowHeight
                - enlargedSpecialRowHeight * 2)
            / otherRowsOriginalHeight

        if row == 6 || row == 7 {
            return enlargedSpecialRowHeight
        }
        if row == 1 {
            return 0.84375 * otherRowsScale * adjustedOtherRowsScale
        }
        if row == 0 {
            return doubledFirstRowHeight
        }
        return otherRowsScale * adjustedOtherRowsScale
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
        if SportTrackerCellCatalog.datedCellNumbers.contains(number) {
            datedLabelText(for: number)
                .font(.title2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } else if let direction = SportTrackerCellCatalog.definition(for: number)?.legPalmDirection {
            VStack(spacing: 0) {
                Text("ноги,")
                    .font(.title2)
                Text("ладонь\n\(direction)")
                    .font(.system(size: 16.5))
                    .foregroundStyle(.yellow)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let definition = SportTrackerCellCatalog.definition(for: number),
                  definition.isTappable,
                  !definition.labelLines.isEmpty {
            VStack(spacing: -7) {
                ForEach(definition.labelLines, id: \.self) { line in
                    Text(line)
                        .font(
                            definition.labelFontSize.map { .system(size: $0) }
                                ?? .title2
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
        let label = SportTrackerCellCatalog.definition(for: cellNumber)?.datedLabel ?? ""
        let date = model.datedLabelDate(in: cellNumber)

        if let date {
            let text = Text(label + " " + Self.fiveLDateFormatter.string(from: date))
            return model.isCurrentDatedLabel(in: cellNumber)
                ? text.foregroundColor(.yellow)
                : text
        }

        guard model.canMarkDatedLabel(in: cellNumber) else {
            return Text(label)
        }

        let currentDate = Self.fiveLDateFormatter.string(from: Date())
        return Text(label + " " + currentDate)
            .foregroundColor(Color(red: 0.55, green: 1.0, blue: 0.55))
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
        SportTrackerCellCatalog.definition(for: number)?.label ?? ""
    }
}

private struct GridNumbersControl: View {
    @Binding var isVisible: Bool

    var body: some View {
        Button {
            isVisible.toggle()
        } label: {
            Text("show numbrs")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.65)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 2)
                .padding(.vertical, 1)
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.red, lineWidth: 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isVisible ? "Visible" : "Hidden")
        .accessibilityHint("Toggles cell and row numbers")
    }
}

private struct HeaderSelectionControl: View {
    let cellNumber: Int
    let label: String
    @Binding var selection: Int?

    var body: some View {
        GeometryReader { cellGeometry in
            let buttonInset: CGFloat = 4
            let buttonHeight = min(cellGeometry.size.width, cellGeometry.size.height) / 2
                - buttonInset

            Button(action: toggleSelection) {
                ZStack {
                    Color.clear
                    Text(label)
                        .font(.title2.monospacedDigit())
                        .foregroundStyle(.white)
                }
                .frame(
                    width: cellGeometry.size.width - buttonInset * 2,
                    height: buttonHeight
                )
                .contentShape(Rectangle())
                .overlay {
                    if selection == cellNumber {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.green, lineWidth: 2)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(selection != nil && selection != cellNumber)
            .accessibilityLabel(label)
            .accessibilityValue(selection == cellNumber ? "Selected" : "Not selected")
            .accessibilityHint(
                selection == nil || selection == cellNumber
                    ? "Toggles this option"
                    : "Turn off the selected option first"
            )
            .position(
                x: cellGeometry.size.width / 2,
                y: buttonInset + buttonHeight / 2
            )
        }
    }

    private func toggleSelection() {
        if selection == cellNumber {
            selection = nil
        } else if selection == nil {
            selection = cellNumber
        }
    }
}

private struct SoundIntervalControl: View {
    let minutes: Int
    let onIncrement: () -> Void
    let onDecrement: () -> Void

    var body: some View {
        ZStack {
            Text(String(minutes))
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            GeometryReader { buttonGeometry in
                let spacing: CGFloat = 4
                let buttonWidth = (buttonGeometry.size.width - spacing) / 2

                HStack(spacing: spacing) {
                    SportCounterButton(
                        title: "+",
                        backgroundOpacity: 0.1728,
                        action: onIncrement
                    )
                    .frame(width: buttonWidth)

                    SportCounterButton(title: "−", action: onDecrement)
                        .frame(width: buttonWidth)
                }
            }
            .frame(height: 23.66)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 3)
        }
    }
}

private struct ResetTimerControl: View {
    let title: String
    let startDate: Date?
    let timerColor: Color
    let onReset: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onReset) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.red, lineWidth: 2)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(Self.timerText(at: context.date, since: startDate))
                    .font(.system(size: 32.34, weight: .bold, design: .monospaced))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(timerColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static func timerText(at date: Date, since startDate: Date?) -> String {
        guard let startDate else { return "00:00" }
        let elapsedSeconds = max(0, Int(date.timeIntervalSince(startDate)))
        return String(format: "%02d:%02d", elapsedSeconds / 60, elapsedSeconds % 60)
    }
}

private struct VolumeProvisioningControl: View {
    let percentage: Int
    let isMaximumEnabled: Bool
    let provisioningTimeRemaining: String
    let onToggle: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                Text("Volume \(percentage)%")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isMaximumEnabled ? Color.green : Color.red, lineWidth: 2)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("iPhone sound volume")
            .accessibilityValue(
                "\(percentage) percent, maximum volume " + (isMaximumEnabled ? "on" : "off")
            )
            .accessibilityHint(
                isMaximumEnabled
                    ? "Restores the previous volume"
                    : "Sets the volume to 100 percent"
            )

            Divider()

            Text(provisioningTimeRemaining)
                .font(.system(size: 21.02, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(Color(red: 1.0, green: 0.65, blue: 0.82))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("App time remaining, \(provisioningTimeRemaining)")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ExerciseCellControl<Content: View>: View {
    let preview: ExercisePreview?
    let flashTrigger: UUID?
    let onTap: () -> Void
    let onHoldChanged: (ExercisePreview, Bool) -> Void
    let content: Content

    init(
        preview: ExercisePreview?,
        flashTrigger: UUID?,
        onTap: @escaping () -> Void,
        onHoldChanged: @escaping (ExercisePreview, Bool) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.preview = preview
        self.flashTrigger = flashTrigger
        self.onTap = onTap
        self.onHoldChanged = onHoldChanged
        self.content = content()
    }

    var body: some View {
        ZStack {
            if let preview {
                ExercisePressArea(
                    onTap: onTap,
                    onHoldChanged: { onHoldChanged(preview, $0) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Button(action: onTap) {
                    Color.clear
                        .background(
                            flashTrigger != nil
                                ? Color(red: 0.45, green: 0.9, blue: 1.0).opacity(0.3)
                                : Color.clear
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            CellColorFillEffect(trigger: flashTrigger)
                .allowsHitTesting(false)

            content
                .allowsHitTesting(false)

            if preview != nil {
                Image(systemName: "eye")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(6)
                    .allowsHitTesting(false)
            }

            CellRippleEffect(trigger: flashTrigger)
                .allowsHitTesting(false)
            CellParticleBurstEffect(trigger: flashTrigger)
                .allowsHitTesting(false)
            CellCooldownRingEffect(trigger: flashTrigger)
                .allowsHitTesting(false)
        }
    }
}

private struct SportCounterButton: View {
    let title: String
    var backgroundOpacity: Double?
    let action: () -> Void

    init(
        title: String,
        backgroundOpacity: Double? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.backgroundOpacity = backgroundOpacity
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .frame(maxWidth: .infinity)
                .frame(height: 23.66)
                .background(
                    Color.black.opacity(backgroundOpacity ?? (title == "−" ? 0.1728 : 0.3))
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }
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
