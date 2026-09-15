import Foundation

struct FolderCopyResult: Sendable {
    var copied = 0
    var skipped = 0
    var failed = 0

    nonisolated init(copied: Int = 0, skipped: Int = 0, failed: Int = 0) {
        self.copied = copied
        self.skipped = skipped
        self.failed = failed
    }

    var message: String {
        "Copied: \(copied)  •  Skipped: \(skipped)  •  Failed: \(failed)"
    }
}

enum FolderCopyService {
    enum CopyError: LocalizedError {
        case destinationInsideSource

        nonisolated var errorDescription: String? {
            switch self {
            case .destinationInsideSource:
                "Choose a destination outside the folder being copied."
            }
        }
    }

    nonisolated static func copyFiles(
        from sourceDirectory: URL,
        to destinationDirectory: URL,
        progress: @escaping @Sendable (_ completed: Int, _ total: Int) async -> Void
    ) async throws -> FolderCopyResult {
        let sourcePath = sourceDirectory.standardizedFileURL.path
        let destinationPath = destinationDirectory.standardizedFileURL.path
        guard
            destinationPath != sourcePath,
            !destinationPath.hasPrefix(sourcePath + "/")
        else {
            throw CopyError.destinationInsideSource
        }

        let destinationAccessGranted = destinationDirectory.startAccessingSecurityScopedResource()
        defer {
            if destinationAccessGranted {
                destinationDirectory.stopAccessingSecurityScopedResource()
            }
        }

        let fileManager = FileManager.default
        let relativePaths = try fileManager.subpathsOfDirectory(atPath: sourcePath)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        var files: [String] = []
        for relativePath in relativePaths {
            try Task.checkCancellation()
            let sourceItem = sourceDirectory.appendingPathComponent(relativePath)
            let values = try sourceItem.resourceValues(
                forKeys: [.isRegularFileKey]
            )
            if values.isRegularFile == true {
                files.append(relativePath)
            }
        }

        var result = FolderCopyResult()
        await progress(0, files.count)

        for (index, relativePath) in files.enumerated() {
            try Task.checkCancellation()
            let sourceFile = sourceDirectory.appendingPathComponent(relativePath)
            let destinationFile = destinationDirectory
                .appendingPathComponent(sourceFile.lastPathComponent)

            if fileManager.fileExists(atPath: destinationFile.path) {
                result.skipped += 1
            } else {
                do {
                    try fileManager.copyItem(at: sourceFile, to: destinationFile)
                    result.copied += 1
                } catch {
                    result.failed += 1
                }
            }

            await progress(index + 1, files.count)
        }

        return result
    }
}
