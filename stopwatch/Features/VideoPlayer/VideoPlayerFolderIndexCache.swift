import Foundation
import UniformTypeIdentifiers

struct CachedFolderIndex: Codable, Sendable {
    nonisolated static let currentVersion = 1

    let version: Int
    let totalFileCount: Int
    let videoRelativePaths: [String]
    let creationDate: Date

    nonisolated init(
        totalFileCount: Int,
        videoRelativePaths: [String],
        creationDate: Date = .now
    ) {
        version = Self.currentVersion
        self.totalFileCount = totalFileCount
        self.videoRelativePaths = videoRelativePaths
        self.creationDate = creationDate
    }
}

struct FolderIndexCache: Sendable {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func load() -> CachedFolderIndex? {
        guard
            let data = try? Data(contentsOf: cacheURL(createDirectory: false)),
            let index = try? JSONDecoder().decode(CachedFolderIndex.self, from: data),
            index.version == CachedFolderIndex.currentVersion,
            index.totalFileCount >= index.videoRelativePaths.count,
            index.videoRelativePaths.allSatisfy(Self.isSafeRelativePath)
        else {
            return nil
        }
        return index
    }

    func save(_ index: CachedFolderIndex) throws {
        let data = try JSONEncoder().encode(index)
        try data.write(to: cacheURL(createDirectory: true), options: .atomic)
    }

    func invalidate() {
        guard let url = try? cacheURL(createDirectory: false) else { return }
        try? fileManager.removeItem(at: url)
    }

    private func cacheURL(createDirectory: Bool) throws -> URL {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: createDirectory
        )
        let directory = applicationSupport.appendingPathComponent(
            Bundle.main.bundleIdentifier ?? "videoplayer",
            isDirectory: true
        )
        if createDirectory {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        return directory.appendingPathComponent("folder-index-v1.json")
    }

    nonisolated private static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/") else { return false }
        return !path.split(separator: "/", omittingEmptySubsequences: false)
            .contains { $0 == ".." || $0.isEmpty }
    }
}

struct FolderIndexer: Sendable {
    nonisolated private static let additionalVideoExtensions: Set<String> = [
        "3gp", "asf", "avi", "divx", "flv", "m2ts", "mkv",
        "mpeg", "mpg", "mts", "ogm", "ogv", "ts", "vob", "webm", "wmv"
    ]

    nonisolated func index(folder: URL) throws -> CachedFolderIndex {
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .contentTypeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw FolderIndexError.cannotReadContents
        }

        var totalFileCount = 0
        var videoRelativePaths: [String] = []

        for case let url as URL in enumerator {
            try Task.checkCancellation()
            guard
                let values = try? url.resourceValues(forKeys: resourceKeys),
                values.isRegularFile == true
            else { continue }

            totalFileCount += 1
            if values.contentType?.conforms(to: .movie) == true
                || Self.additionalVideoExtensions.contains(url.pathExtension.lowercased()) {
                videoRelativePaths.append(url.relativePath(from: folder))
            }
        }

        videoRelativePaths.sort {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        return CachedFolderIndex(
            totalFileCount: totalFileCount,
            videoRelativePaths: videoRelativePaths
        )
    }
}

enum FolderIndexError: LocalizedError {
    case accessDenied
    case cannotReadContents

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            "The app was not granted permission to access this folder."
        case .cannotReadContents:
            "The contents of this folder could not be read."
        }
    }
}

extension URL {
    nonisolated func relativePath(from folder: URL) -> String {
        let folderPath = folder.standardizedFileURL.path
        let filePath = standardizedFileURL.path
        let prefix = folderPath.hasSuffix("/") ? folderPath : folderPath + "/"

        guard filePath.hasPrefix(prefix) else {
            return lastPathComponent
        }
        return String(filePath.dropFirst(prefix.count))
    }
}
