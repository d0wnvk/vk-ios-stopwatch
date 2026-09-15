import Foundation

enum FolderMetadata {
    struct DeviceStorage: Sendable {
        let total: Int64
        let available: Int64

        nonisolated init(total: Int64, available: Int64) {
            self.total = total
            self.available = available
        }
    }

    nonisolated static func recursiveSize(of directory: URL) async throws -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            try Task.checkCancellation()
            guard let values = try? fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey]
            ), values.isRegularFile == true else {
                continue
            }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    nonisolated static func deviceStorage() throws -> DeviceStorage {
        let homeDirectory = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let values = try homeDirectory.resourceValues(
            forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey
            ]
        )
        return DeviceStorage(
            total: Int64(values.volumeTotalCapacity ?? 0),
            available: values.volumeAvailableCapacityForImportantUsage ?? 0
        )
    }
}
