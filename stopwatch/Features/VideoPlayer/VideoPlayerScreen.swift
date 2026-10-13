import Combine
import MobileVLCKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct VideoPlayerScreen: View {
    let videoFiles: [URL]
    @Binding var isAppTabBarVisible: Bool
    @State private var currentIndex: Int
    @State private var playbackErrorMessage: String?
    @State private var isRandomPlayback = true
    @State private var playbackHistory: [Int] = []
    @State private var areControlsVisible = true
    @State private var isOrientationLocked = false
    @State private var controlsActivityID = UUID()
    @State private var areDiagnosticsVisible = false
    @State private var isDestinationPickerPresented = false
    @State private var sourceDirectoryForCopy: URL?
    @State private var copyTask: Task<Void, Never>?
    @State private var copyProgress: (completed: Int, total: Int)?
    @State private var copyResultMessage: String?
    @State private var currentFolderSize = "—"
    @State private var deviceStorageSummary = "iPhone: — total  •  — free"
    @StateObject private var controller = VLCPlayerController()

    init(
        videoFiles: [URL],
        startingAt index: Int,
        isAppTabBarVisible: Binding<Bool>
    ) {
        self.videoFiles = videoFiles
        _isAppTabBarVisible = isAppTabBarVisible
        _currentIndex = State(initialValue: index)
    }

    var body: some View {
        ZStack {
            VLCPlayerView(controller: controller)
                .background(.black)
                .allowsHitTesting(false)
                .zIndex(0)

            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleControlsVisibility()
                }
                .zIndex(1)

            if areControlsVisible || areDiagnosticsVisible {
                VStack {
                    VStack(spacing: 2) {
                        if areControlsVisible {
                            Text(playerTitle)
                                .font(.headline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)

                            Text(
                                "\(currentVideo.deletingLastPathComponent().lastPathComponent)"
                                    + "  •  Folder: \(currentFolderSize)"
                                    + "  •  \(deviceStorageSummary)"
                            )
                                .font(.caption.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .minimumScaleFactor(0.65)

                            Text(controller.videoParameters)
                                .font(.headline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)
                        }

                        if areDiagnosticsVisible {
                            diagnosticsPanel
                                .padding(.top, areControlsVisible ? 5 : 0)
                        }
                    }
                    .foregroundStyle(.yellow)
                    .shadow(color: .black, radius: 3)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        .black.opacity(0.72),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    Spacer()
                }
                .allowsHitTesting(false)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let playbackErrorMessage {
                Text(playbackErrorMessage)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding()
                    .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
                    .padding()
                    .transition(.opacity)
            }

            if let copyProgress {
                VStack(spacing: 8) {
                    ProgressView(
                        value: Double(copyProgress.completed),
                        total: Double(max(1, copyProgress.total))
                    )
                    Text("Copying \(copyProgress.completed) of \(copyProgress.total) files")
                        .font(.caption.monospacedDigit())
                }
                .foregroundStyle(.white)
                .frame(width: 220)
                .padding()
                .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 12))
            }

            if areControlsVisible {
                HStack {
                    leftSideControls
                        .padding(.leading, 12)
                    Spacer()
                    rightSideControls
                        .padding(.trailing, 12)
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
                .zIndex(3)
            }

            VStack {
                Spacer()
                if areControlsVisible {
                    playbackControls
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .zIndex(3)
        }
            .ignoresSafeArea()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(areControlsVisible ? .visible : .hidden, for: .navigationBar)
            .animation(.easeInOut(duration: 0.2), value: areControlsVisible)
            .onAppear {
                isAppTabBarVisible = false
            }
            .task(id: currentIndex) {
                playbackErrorMessage = nil
                await controller.play(url: currentVideo)
                guard !Task.isCancelled else { return }
                currentFolderSize = "Calculating…"
                do {
                    let storage = try FolderMetadata.deviceStorage()
                    deviceStorageSummary = "iPhone: "
                        + ByteCountFormatter.string(
                            fromByteCount: storage.total,
                            countStyle: .file
                        )
                        + " total  •  "
                        + ByteCountFormatter.string(
                            fromByteCount: storage.available,
                            countStyle: .file
                        )
                        + " free"
                } catch {
                    deviceStorageSummary = "iPhone: — total  •  — free"
                }

                do {
                    let byteCount = try await FolderMetadata.recursiveSize(
                        of: currentVideo.deletingLastPathComponent()
                    )
                    try Task.checkCancellation()
                    currentFolderSize = ByteCountFormatter.string(
                        fromByteCount: byteCount,
                        countStyle: .file
                    )
                } catch is CancellationError {
                    // A video change superseded this folder-size calculation.
                } catch {
                    currentFolderSize = "—"
                }
            }
            .task(id: controller.failureCount) {
                guard controller.failureCount > 0 else { return }
                await handlePlaybackFailure()
            }
            .task(id: controller.completionCount) {
                guard controller.completionCount > 0, canPlayNext else { return }
                playNext()
            }
            .task(id: controlsActivityID) {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                areControlsVisible = false
            }
            .onChange(of: isRandomPlayback) {
                registerControlsInteraction()
            }
            .onChange(of: areDiagnosticsVisible) {
                controller.setDiagnosticsEnabled(areDiagnosticsVisible)
            }
            .sheet(isPresented: $isDestinationPickerPresented) {
                DestinationFolderPicker(
                    isPresented: $isDestinationPickerPresented,
                    onSelect: copyCurrentFolder(to:)
                )
                .ignoresSafeArea()
            }
            .alert(
                "Folder Copy",
                isPresented: Binding(
                    get: { copyResultMessage != nil },
                    set: { if !$0 { copyResultMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(copyResultMessage ?? "")
            }
            .onDisappear {
                AppOrientationLock.unlock(in: playerWindowScene)
                isOrientationLocked = false
                isAppTabBarVisible = true
                copyTask?.cancel()
                controller.setDiagnosticsEnabled(false)
                controller.stop()
            }
    }

    private var playbackControls: some View {
        VStack(spacing: 12) {
            centerControls

            HStack {
                Text(controller.elapsedTime.formattedPlaybackTime)
                GeometryReader { geometry in
                    Slider(
                        value: Binding(
                            get: { controller.position },
                            set: {
                                registerControlsInteraction()
                                controller.seek(to: $0)
                            }
                        ),
                        in: 0...1
                    )
                    .scaleEffect(x: 1, y: 1.5)
                    .disabled(!controller.isSeekable)
                    .simultaneousGesture(
                        SpatialTapGesture().onEnded { tap in
                            guard controller.isSeekable, geometry.size.width > 0 else {
                                return
                            }
                            registerControlsInteraction()
                            let position = min(
                                1,
                                max(0, tap.location.x / geometry.size.width)
                            )
                            controller.seek(to: position)
                        }
                    )
                }
                .frame(height: 22)
                Text(controller.duration.formattedPlaybackTime)
            }
            .font(.caption.monospacedDigit())
        }
        .foregroundStyle(.white)
        .padding(.horizontal)
        .padding(.top)
        .padding(.bottom, 16)
    }

    private var centerControls: some View {
        HStack(spacing: 18) {
            largeSideButton(
                title: "Start Over",
                systemImage: "arrow.counterclockwise",
                accessibilityLabel: "Start video from the beginning",
                disabled: !controller.isSeekable,
                action: controller.restartFromBeginning
            )

            largeSideButton(
                title: "4 Copy Folder",
                systemImage: "folder.badge.plus",
                accessibilityLabel: "Copy files from the current folder",
                disabled: copyTask != nil
            ) {
                sourceDirectoryForCopy = currentVideo.deletingLastPathComponent()
                isDestinationPickerPresented = true
            }

            largeSideButton(
                title: controller.isPlaying ? "5 Pause" : "5 Play",
                systemImage: controller.isPlaying ? "pause.fill" : "play.fill",
                accessibilityLabel: controller.isPlaying ? "Pause" : "Play",
                action: controller.togglePlayback
            )

            largeSideButton(
                title: isAppTabBarVisible ? "6 Hide Menu" : "6 Show Menu",
                systemImage: isAppTabBarVisible ? "rectangle.bottomthird.inset.filled" : "rectangle.bottomthird.inset",
                accessibilityLabel: isAppTabBarVisible
                    ? "Hide stopwatch app menu buttons"
                    : "Show stopwatch app menu buttons",
                backgroundColor: isAppTabBarVisible ? .yellow : .white
            ) {
                isAppTabBarVisible.toggle()
            }

            largeSideButton(
                title: isRandomPlayback ? "7 Random On" : "7 Random Off",
                systemImage: "shuffle",
                accessibilityLabel: "Toggle random playback",
                backgroundColor: isRandomPlayback ? .yellow : .white
            ) {
                isRandomPlayback.toggle()
            }

            largeSideButton(
                title: "8 Diagnostics",
                systemImage: "waveform.path.ecg",
                accessibilityLabel: "Toggle playback diagnostics",
                backgroundColor: areDiagnosticsVisible ? .yellow : .white
            ) {
                areDiagnosticsVisible.toggle()
            }

            largeSideButton(
                title: isOrientationLocked ? "15 Unlock" : "15 Lock Rotation",
                systemImage: isOrientationLocked
                    ? "lock.rotation"
                    : "lock.rotation.open",
                accessibilityLabel: isOrientationLocked
                    ? "Unlock automatic screen rotation"
                    : "Lock the current screen orientation",
                backgroundColor: isOrientationLocked ? .yellow : .white
            ) {
                toggleOrientationLock()
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var diagnosticsPanel: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(controller.diagnostics.lines.enumerated()), id: \.offset) { index, line in
                Text(line)
                    .foregroundStyle(index == 0 ? diagnosticsStatusColor : .white)
            }
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Playback diagnostics: \(controller.diagnostics.lines.joined(separator: ", "))")
    }

    private var diagnosticsStatusColor: Color {
        switch controller.diagnostics.status {
        case .healthy: .green
        case .buffering: .yellow
        case .videoStalled, .playbackError: .red
        }
    }

    private var leftSideControls: some View {
        VStack(spacing: 14) {
            largeSideButton(
                title: "1 −10%",
                systemImage: "speaker.minus.fill",
                accessibilityLabel: "Decrease volume by 10 percent"
            ) {
                controller.adjustVolume(by: -10)
            }
            .scaleEffect(0.7)

            largeSideButton(
                title: "2 −10%",
                systemImage: "sun.min.fill",
                accessibilityLabel: "Decrease video brightness by 10 percent",
                disabled: controller.brightnessPercent == 0
            ) {
                controller.adjustBrightness(by: -10)
            }

            largeSideButton(
                title: "11 End−30s",
                systemImage: "gobackward.30",
                accessibilityLabel: "Go to 30 seconds before the end",
                disabled: !controller.canSeekNearEnd,
                action: controller.seekToThirtySecondsBeforeEnd
            )

            largeSideButton(
                title: "14 Previous",
                systemImage: "backward.end.fill",
                accessibilityLabel: "Previous video",
                action: playPrevious
            )
            .scaleEffect(0.7)
        }
        .padding(10)
        .scaleEffect(1.2, anchor: .leading)
    }

    private var rightSideControls: some View {
        VStack(spacing: 14) {
            largeSideButton(
                title: "9 +10%",
                systemImage: "speaker.plus.fill",
                accessibilityLabel: "Increase volume by 10 percent",
                disabled: controller.volumePercent == 100
            ) {
                controller.adjustVolume(by: 10)
            }
            .scaleEffect(0.7)

            largeSideButton(
                title: "10 +10%",
                systemImage: "sun.max.fill",
                accessibilityLabel: "Increase video brightness by 10 percent",
                disabled: controller.brightnessPercent == 200
            ) {
                controller.adjustBrightness(by: 10)
            }
            .scaleEffect(0.7)

            HStack(spacing: 14) {
                largeSideButton(
                    title: "3 −10s",
                    systemImage: "gobackward.10",
                    accessibilityLabel: "Rewind 10 seconds",
                    disabled: !controller.isSeekable
                ) {
                    controller.skip(seconds: -10)
                }

                largeSideButton(
                    title: "12 +10s",
                    systemImage: "goforward.10",
                    accessibilityLabel: "Forward 10 seconds",
                    disabled: !controller.isSeekable
                ) {
                    controller.skip(seconds: 10)
                }
                .scaleEffect(1.2)
            }

            largeSideButton(
                title: "13 Next",
                systemImage: "forward.end.fill",
                accessibilityLabel: "Next video",
                disabled: !canPlayNext,
                action: playNext
            )
            .scaleEffect(0.84)

        }
        .padding(10)
        .scaleEffect(1.2, anchor: .trailing)
    }

    private func largeSideButton(
        title: String,
        systemImage: String,
        accessibilityLabel: String,
        disabled: Bool = false,
        backgroundColor: Color = .white,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            registerControlsInteraction()
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.title2)
                Text(title)
                    .font(.caption.bold())
            }
            .foregroundStyle(.black.opacity(0.82))
            .frame(width: 64, height: 56)
            .background(
                backgroundColor.opacity(0.195),
                in: RoundedRectangle(cornerRadius: 12)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(1.2)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .accessibilityLabel(accessibilityLabel)
    }

    private func registerControlsInteraction() {
        areControlsVisible = true
        controlsActivityID = UUID()
    }

    private func toggleControlsVisibility() {
        if areControlsVisible {
            areControlsVisible = false
        } else {
            registerControlsInteraction()
        }
    }

    private var playerWindowScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }

    private func toggleOrientationLock() {
        if isOrientationLocked {
            AppOrientationLock.unlock(in: playerWindowScene)
            isOrientationLocked = false
        } else if let playerWindowScene {
            AppOrientationLock.lockCurrentOrientation(in: playerWindowScene)
            isOrientationLocked = true
        }
    }

    private var currentVideo: URL {
        videoFiles[currentIndex]
    }

    private var playerTitle: String {
        "[\(currentIndex + 1)/\(videoFiles.count)] - \(currentVideo.lastPathComponent)"
    }

    private var canPlayPrevious: Bool {
        isRandomPlayback
            ? !playbackHistory.isEmpty
            : currentIndex > videoFiles.startIndex
    }

    private var canPlayNext: Bool {
        isRandomPlayback
            ? videoFiles.count > 1
            : videoFiles.indices.contains(currentIndex + 1)
    }

    private func playPrevious() {
        if isRandomPlayback {
            guard let previousIndex = playbackHistory.popLast() else { return }
            currentIndex = previousIndex
        } else {
            guard currentIndex > videoFiles.startIndex else { return }
            currentIndex -= 1
        }
    }

    private func playNext() {
        if isRandomPlayback {
            let candidates = videoFiles.indices.filter { $0 != currentIndex }
            guard let nextIndex = candidates.randomElement() else { return }
            playbackHistory.append(currentIndex)
            currentIndex = nextIndex
        } else {
            guard videoFiles.indices.contains(currentIndex + 1) else { return }
            currentIndex += 1
        }
    }

    private func handlePlaybackFailure() async {
        let failedIndex = currentIndex
        let fileName = currentVideo.lastPathComponent
        playbackErrorMessage = "Could not play “\(fileName)”. Trying the next video…"

        try? await Task.sleep(for: .seconds(3))
        guard !Task.isCancelled, currentIndex == failedIndex else {
            playbackErrorMessage = nil
            return
        }

        if canPlayNext {
            playNext()
        } else {
            playbackErrorMessage = "Could not play “\(fileName)”. There are no more videos."
        }
    }

    private func copyCurrentFolder(to destinationDirectory: URL) {
        guard let sourceDirectoryForCopy, copyTask == nil else { return }

        copyTask = Task {
            do {
                let result = try await FolderCopyService.copyFiles(
                    from: sourceDirectoryForCopy,
                    to: destinationDirectory
                ) { completed, total in
                    await MainActor.run {
                        copyProgress = (completed, total)
                    }
                }
                guard !Task.isCancelled else { return }
                copyResultMessage = result.message
            } catch is CancellationError {
                // Leaving the player cancels the remaining copies.
            } catch {
                copyResultMessage = "The folder could not be copied. \(error.localizedDescription)"
            }

            copyProgress = nil
            copyTask = nil
        }
    }
}

