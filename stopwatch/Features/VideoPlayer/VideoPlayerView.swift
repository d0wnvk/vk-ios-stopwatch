//
//  ContentView.swift
//  videoplayer
//
//  Created by Vladimir Korolevskii on 29. 7. 2026..
//

import Combine
import MobileVLCKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct VideoPlayerView: View {
    private static let selectedFolderBookmarkKey = "selectedFolderBookmark"

    @State private var isFolderPickerPresented = false
    @State private var selectedFolder: URL?
    @State private var totalFileCount = 0
    @State private var videoFiles: [URL] = []
    @State private var isRefreshing = false
    @State private var refreshID = UUID()
    @State private var refreshTask: Task<Void, Never>?
    @State private var errorMessage: String?

    private let cache = FolderIndexCache()
    private let indexer = FolderIndexer()

    var body: some View {
        NavigationStack {
            Group {
                if let selectedFolder {
                    folderContents(for: selectedFolder)
                } else {
                    folderPrompt
                }
            }
            .navigationTitle("Video Player")
            .toolbar {
                if selectedFolder != nil {
                    Button("Choose Folder", systemImage: "folder") {
                        isFolderPickerPresented = true
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $isFolderPickerPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false,
            onCompletion: handleFolderSelection
        )
        .alert(
            "Folder Error",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
        .task {
            restorePreviouslySelectedFolder()
        }
        .onDisappear {
            refreshTask?.cancel()
            selectedFolder?.stopAccessingSecurityScopedResource()
        }
    }

    private var folderPrompt: some View {
        ContentUnavailableView {
            Label("Choose a Video Folder", systemImage: "externaldrive.badge.plus")
        } description: {
            Text("Select a folder from this iPhone, iCloud Drive, or a connected USB drive under Browse → Locations.")
        } actions: {
            Button("Choose Folder or USB Drive") {
                isFolderPickerPresented = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func folderContents(for folder: URL) -> some View {
        List {
            Section {
                HStack(spacing: 10) {
                    Label(folder.lastPathComponent, systemImage: "folder")
                        .lineLimit(1)
                        .layoutPriority(1)

                    Spacer(minLength: 4)

                    Text("\(totalFileCount.formatted()) files")
                    Text("\(videoFiles.count.formatted()) videos")

                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.vertical, 2)
            }

            Section("Videos") {
                if videoFiles.isEmpty {
                    ContentUnavailableView(
                        "No Videos Found",
                        systemImage: "video.slash",
                        description: Text("This folder does not contain a supported video file.")
                    )
                } else {
                    ForEach(videoFiles.indices, id: \.self) { index in
                        let videoURL = videoFiles[index]
                        NavigationLink {
                            VideoPlayerScreen(
                                videoFiles: videoFiles,
                                startingAt: index
                            )
                        } label: {
                            Label {
                                Text(videoURL.relativePath(from: folder))
                                    .font(.subheadline)
                                    .lineLimit(1)
                            } icon: {
                                Image(systemName: "play.rectangle")
                                    .font(.caption)
                            }
                        }
                        .listRowInsets(
                            EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 12)
                        )
                    }
                }
            }
            .environment(\.defaultMinListRowHeight, 30)
        }
    }

    private func handleFolderSelection(_ result: Result<[URL], any Error>) {
        do {
            guard let folder = try result.get().first else { return }
            try open(folder: folder, rememberSelection: true, useCache: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restorePreviouslySelectedFolder() {
        guard
            selectedFolder == nil,
            let bookmark = UserDefaults.standard.data(
                forKey: Self.selectedFolderBookmarkKey
            )
        else { return }

        do {
            var isStale = false
            let folder = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            try open(folder: folder, rememberSelection: isStale, useCache: true)
        } catch {
            // The drive may simply be disconnected. Keep the bookmark so the
            // folder can be restored the next time the app launches with it attached.
        }
    }

    private func open(folder: URL, rememberSelection: Bool, useCache: Bool) throws {
        refreshTask?.cancel()
        selectedFolder?.stopAccessingSecurityScopedResource()
        guard folder.startAccessingSecurityScopedResource() else {
            throw FolderIndexError.accessDenied
        }

        do {
            if rememberSelection {
                let bookmark = try folder.bookmarkData(
                    options: .minimalBookmark,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                UserDefaults.standard.set(
                    bookmark,
                    forKey: Self.selectedFolderBookmarkKey
                )
            }

            if !useCache {
                cache.invalidate()
                totalFileCount = 0
                videoFiles = []
            } else if let cachedIndex = cache.load() {
                apply(cachedIndex, to: folder)
            }

            selectedFolder = folder
            refresh(folder: folder)
        } catch {
            folder.stopAccessingSecurityScopedResource()
            throw error
        }
    }

    private func refresh(folder: URL) {
        let id = UUID()
        refreshID = id
        isRefreshing = true
        refreshTask = Task {
            do {
                let newIndex = try await Task.detached(priority: .userInitiated) {
                    try indexer.index(folder: folder)
                }.value
                try Task.checkCancellation()
                try cache.save(newIndex)
                guard refreshID == id, selectedFolder == folder else { return }
                apply(newIndex, to: folder)
                isRefreshing = false
            } catch is CancellationError {
                // A newer folder selection or view dismissal superseded this refresh.
            } catch {
                guard refreshID == id, selectedFolder == folder else { return }
                isRefreshing = false
                errorMessage = "The folder could not be refreshed. \(error.localizedDescription)"
            }
        }
    }

    private func apply(_ index: CachedFolderIndex, to folder: URL) {
        totalFileCount = index.totalFileCount
        videoFiles = index.videoRelativePaths.map {
            folder.appendingPathComponent($0)
        }
    }
}

private struct VideoPlayerScreen: View {
    let videoFiles: [URL]
    @State private var currentIndex: Int
    @State private var playbackErrorMessage: String?
    @State private var isRandomPlayback = true
    @State private var playbackHistory: [Int] = []
    @State private var areControlsVisible = true
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

    init(videoFiles: [URL], startingAt index: Int) {
        self.videoFiles = videoFiles
        _currentIndex = State(initialValue: index)
    }

    var body: some View {
        ZStack {
            VLCPlayerView(controller: controller)
                .background(.black)

            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleControlsVisibility()
                }

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
            }

            VStack {
                Spacer()
                if areControlsVisible {
                    playbackControls
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
            .ignoresSafeArea()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(areControlsVisible ? .visible : .hidden, for: .navigationBar)
            .animation(.easeInOut(duration: 0.2), value: areControlsVisible)
            .task(id: currentIndex) {
                playbackErrorMessage = nil
                controller.play(url: currentVideo)
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
        .contentShape(Rectangle())
        .onTapGesture {}
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
        .contentShape(Rectangle())
        .onTapGesture {}
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
        let fileName = currentVideo.lastPathComponent
        playbackErrorMessage = "Could not play “\(fileName)”. Trying the next video…"

        try? await Task.sleep(for: .seconds(3))
        guard !Task.isCancelled else { return }

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

private struct DestinationFolderPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onSelect: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.folder],
            asCopy: false
        )
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController,
        context: Context
    ) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let parent: DestinationFolderPicker

        init(parent: DestinationFolderPicker) {
            self.parent = parent
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            guard let destination = urls.first else { return }
            parent.isPresented = false
            parent.onSelect(destination)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.isPresented = false
        }
    }
}

private struct VLCPlayerView: UIViewRepresentable {
    let controller: VLCPlayerController

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        controller.attachPhoneView(view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        controller.attachPhoneView(uiView)
    }
}

enum VideoDisplayMode {
    case fit
    case fill
}

final class VLCPlayerController: NSObject, ObservableObject, VLCMediaPlayerDelegate {
    @Published private(set) var isPlaying = false
    @Published private(set) var failureCount = 0
    @Published private(set) var completionCount = 0
    @Published private(set) var position = 0.0
    @Published private(set) var elapsedTime = 0.0
    @Published private(set) var duration = 0.0
    @Published private(set) var isSeekable = false
    @Published private(set) var isMuted = false
    @Published private(set) var isExternalDisplayConnected = false
    @Published private(set) var displayMode: VideoDisplayMode = .fit
    @Published private(set) var brightnessPercent = 100
    @Published private(set) var volumePercent = 100
    @Published private(set) var videoParameters =
        "Resolution: —  •  Codec: —  •  FPS: —  •  Bitrate: —  •  Size: —"
    @Published private(set) var diagnostics = PlaybackDiagnosticsSnapshot.empty

    var canSeekNearEnd: Bool {
        isSeekable && duration > 0
    }

    private let mediaPlayer = VLCMediaPlayer()
    private weak var outputView: UIView?
    private var shouldMuteOnStart = false
    private var diagnosticsTask: Task<Void, Never>?
    private var diagnosticsSampler = PlaybackDiagnosticsSampler()

    override init() {
        super.init()
        mediaPlayer.delegate = self
    }

    deinit {
        diagnosticsTask?.cancel()
        ExternalDisplayManager.shared.unregister(controller: self)
    }

    func attachPhoneView(_ view: UIView) {
        ExternalDisplayManager.shared.register(controller: self, phoneView: view)
    }

    func setOutputView(_ view: UIView?, isExternal: Bool) {
        outputView = view
        isExternalDisplayConnected = isExternal
        mediaPlayer.drawable = view
        applyDisplayMode()
    }

    func outputViewDidLayout() {
        applyDisplayMode()
    }

    func play(url: URL) {
        mediaPlayer.stop()
        diagnosticsSampler.reset()
        diagnostics = .empty
        mediaPlayer.media = VLCMedia(url: url)
        videoParameters = Self.videoParameters(for: url, media: nil)
        shouldMuteOnStart = true
        mediaPlayer.audio?.isMuted = true
        isMuted = true
        mediaPlayer.play()
        mediaPlayer.audio?.isMuted = true
    }

    func togglePlayback() {
        if mediaPlayer.isPlaying {
            mediaPlayer.pause()
        } else {
            mediaPlayer.play()
        }
    }

    func skip(seconds: Int32) {
        guard mediaPlayer.isSeekable else { return }
        diagnosticsSampler.reset()
        if seconds < 0 {
            mediaPlayer.jumpBackward(-seconds)
        } else {
            mediaPlayer.jumpForward(seconds)
        }
    }

    func seek(to position: Double) {
        guard mediaPlayer.isSeekable else { return }
        diagnosticsSampler.reset()
        mediaPlayer.position = Float(position)
        self.position = position
    }

    func seekToThirtySecondsBeforeEnd() {
        guard canSeekNearEnd else { return }
        seek(to: max(0, duration - 30) / duration)
    }

    func restartFromBeginning() {
        guard mediaPlayer.isSeekable else { return }
        diagnosticsSampler.reset()
        mediaPlayer.position = 0
        position = 0
        mediaPlayer.play()
    }

    func toggleMute() {
        shouldMuteOnStart = false
        mediaPlayer.audio?.isMuted.toggle()
        isMuted = mediaPlayer.audio?.isMuted ?? false
    }

    func setVolumeToTenPercent() {
        shouldMuteOnStart = false
        mediaPlayer.audio?.volume = 10
        mediaPlayer.audio?.isMuted = false
        volumePercent = 10
        isMuted = false
    }

    func adjustVolume(by percentagePoints: Int) {
        shouldMuteOnStart = false
        volumePercent = min(100, max(0, volumePercent + percentagePoints))
        mediaPlayer.audio?.volume = Int32(volumePercent)
        mediaPlayer.audio?.isMuted = volumePercent == 0
        isMuted = volumePercent == 0
    }

    func adjustBrightness(by percentagePoints: Int) {
        brightnessPercent = min(200, max(0, brightnessPercent + percentagePoints))
        mediaPlayer.adjustFilter.brightness.value = NSNumber(
            value: Double(brightnessPercent) / 100
        )
    }

    func toggleDisplayMode() {
        displayMode = displayMode == .fit ? .fill : .fit
        applyDisplayMode()
    }

    func stop() {
        setDiagnosticsEnabled(false)
        mediaPlayer.stop()
        mediaPlayer.media = nil
        isPlaying = false
        position = 0
        elapsedTime = 0
        duration = 0
        isSeekable = false
    }

    func setDiagnosticsEnabled(_ enabled: Bool) {
        diagnosticsTask?.cancel()
        diagnosticsTask = nil
        guard enabled else { return }

        sampleDiagnostics()
        diagnosticsTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.sampleDiagnostics()
            }
        }
    }

    func mediaPlayerStateChanged(_ notification: Notification) {
        if shouldMuteOnStart {
            mediaPlayer.audio?.isMuted = true
            isMuted = true

            if mediaPlayer.state == .playing {
                shouldMuteOnStart = false
            }
        }

        isPlaying = mediaPlayer.isPlaying
        isSeekable = mediaPlayer.isSeekable
        volumePercent = min(100, max(0, Int(mediaPlayer.audio?.volume ?? 0)))
        if !shouldMuteOnStart {
            isMuted = mediaPlayer.audio?.isMuted ?? false
        }

        if mediaPlayer.state == .error {
            failureCount += 1
        } else if mediaPlayer.state == .ended {
            completionCount += 1
        }

        if let media = mediaPlayer.media {
            videoParameters = Self.videoParameters(for: media.url, media: media)
        }
    }

    func mediaPlayerTimeChanged(_ notification: Notification) {
        position = Double(mediaPlayer.position)
        elapsedTime = max(0, Double(mediaPlayer.time.intValue) / 1_000)
        duration = max(0, Double(mediaPlayer.media?.length.intValue ?? 0) / 1_000)
        isSeekable = mediaPlayer.isSeekable
    }

    private func applyDisplayMode() {
        guard displayMode == .fill, let outputView else {
            mediaPlayer.videoCropGeometry = nil
            return
        }

        let size = outputView.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        let geometry = "\(Int(size.width)):\(Int(size.height))"
        geometry.withCString {
            mediaPlayer.videoCropGeometry = UnsafeMutablePointer(mutating: $0)
        }
    }

    private func sampleDiagnostics() {
        let media = mediaPlayer.media
        let statistics = media?.statistics
        let sample = PlaybackDiagnosticSample(
            state: diagnosticState,
            inputBitrate: statistics.map { Double($0.inputBitrate) },
            demuxBitrate: statistics.map { Double($0.demuxBitrate) },
            decodedVideo: statistics.map { Int($0.decodedVideo) },
            displayedPictures: statistics.map { Int($0.displayedPictures) },
            lostPictures: statistics.map { Int($0.lostPictures) },
            playedAudioBuffers: statistics.map { Int($0.playedAudioBuffers) },
            lostAudioBuffers: statistics.map { Int($0.lostAudioBuffers) },
            corruptedPackets: statistics.map { Int($0.demuxCorrupted) },
            discontinuities: statistics.map { Int($0.demuxDiscontinuity) },
            playbackTime: max(0, Double(mediaPlayer.time.intValue) / 1_000),
            brightnessPercent: brightnessPercent
        )
        diagnostics = diagnosticsSampler.snapshot(for: sample)
    }

    private var diagnosticState: PlaybackDiagnosticState {
        switch mediaPlayer.state {
        case .playing: .playing
        case .paused: .paused
        case .buffering, .opening: .buffering
        case .error: .error
        default: .stopped
        }
    }

    private static func videoParameters(for url: URL?, media: VLCMedia?) -> String {
        let fileSize = url.flatMap {
            try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize
        }
        let formattedSize = fileSize.map {
            ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file)
        } ?? "—"

        guard
            let videoTrack = media?.tracksInformation.first(where: { track in
                (track as? [String: Any])?[VLCMediaTracksInformationType]
                    as? String == VLCMediaTracksInformationTypeVideo
            }) as? [String: Any]
        else {
            return "Resolution: —  •  Codec: —  •  FPS: —  •  Bitrate: —  •  Size: \(formattedSize)"
        }

        let width = (videoTrack[VLCMediaTracksInformationVideoWidth] as? NSNumber)?.intValue
        let height = (videoTrack[VLCMediaTracksInformationVideoHeight] as? NSNumber)?.intValue
        let resolution = if let width, let height, width > 0, height > 0 {
            "\(width)×\(height)"
        } else {
            "—"
        }

        let codec = (videoTrack[VLCMediaTracksInformationCodec] as? NSNumber)
            .map { fourCC($0.uint32Value) } ?? "—"

        let frameRate = (videoTrack[VLCMediaTracksInformationFrameRate] as? NSNumber)?
            .doubleValue
        let frameRateDenominator =
            (videoTrack[VLCMediaTracksInformationFrameRateDenominator] as? NSNumber)?
            .doubleValue
        let framesPerSecond = if
            let frameRate,
            let frameRateDenominator,
            frameRate > 0,
            frameRateDenominator > 0
        {
            formattedFrameRate(frameRate / frameRateDenominator)
        } else {
            "—"
        }

        let bitrate = (videoTrack[VLCMediaTracksInformationBitrate] as? NSNumber)?
            .doubleValue
        let formattedBitrate = if let bitrate, bitrate > 0 {
            String(format: "%.1f Mbps", bitrate / 1_000_000)
        } else {
            "—"
        }

        return "Resolution: \(resolution)  •  Codec: \(codec)  •  FPS: \(framesPerSecond)  •  Bitrate: \(formattedBitrate)  •  Size: \(formattedSize)"
    }

    private static func formattedFrameRate(_ framesPerSecond: Double) -> String {
        if abs(framesPerSecond.rounded() - framesPerSecond) < 0.001 {
            return String(Int(framesPerSecond.rounded()))
        }
        return String(format: "%.2f", framesPerSecond)
    }

    private static func fourCC(_ value: UInt32) -> String {
        let bytes = [
            UInt8(value & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 24) & 0xff)
        ]
        let text = String(bytes: bytes, encoding: .ascii)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? "—" : text.uppercased()
    }
}

private extension Double {
    var formattedPlaybackTime: String {
        guard isFinite, self >= 0 else { return "00:00" }
        let totalSeconds = Int(self)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
