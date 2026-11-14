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

    @Binding var isAppTabBarVisible: Bool
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
                                startingAt: index,
                                isAppTabBarVisible: $isAppTabBarVisible
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
            let bookmark = PersistentAppState.load(
                Data.self,
                forKey: Self.selectedFolderBookmarkKey
            ) ?? UserDefaults.standard.data(forKey: Self.selectedFolderBookmarkKey)
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
                PersistentAppState.save(
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
