import Foundation
import Network
import Photos
import CryptoKit
import Combine
import UIKit

@MainActor
final class PhotoExportServer: ObservableObject {
    @Published var connectionURL = ""
    @Published var status = "Tap Start, then run the Mac script with the address shown here."
    @Published var running = false
    @Published var starting = false
    @Published var served = 0
    private var listener: NWListener?
    private var peers: [UUID: PhotoExportHTTP] = [:]
    private var resources: [String: PHAssetResource] = [:]
    private var token = ""
    private var serving = false
    private var oldIdle = false
    private var startTask: Task<Void, Never>?
    private var generation = UUID()

    func start() {
        guard !running, !starting else { return }
        starting = true
        startTask = Task { [self] in
            let authorization = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            guard !Task.isCancelled else { return }
            guard authorization == .authorized else {
                starting = false
                status = "Enable Full Access for Stopwatch in Settings → Privacy & Security → Photos, then retry."
                return
            }
            guard let ip = Self.wifiAddress() else {
                starting = false
                status = "Connect the iPhone to Wi-Fi first. A Wi-Fi IPv4 address is required."
                return
            }
            do {
                generation = UUID()
                let current = generation
                token = UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")
                let parameters = NWParameters.tcp
                parameters.requiredInterfaceType = .wifi
                let server = try NWListener(using: parameters, on: .any)
                listener = server
                server.newConnectionHandler = { [weak self] connection in
                    Task { @MainActor [weak self] in
                        guard let self, self.running, self.generation == current, self.peers.count < 8 else { connection.cancel(); return }
                        let peer = PhotoExportHTTP(connection)
                        self.peers[peer.id] = peer
                        peer.onClose = { [weak self, weak peer] in
                            if let peer { self?.peers.removeValue(forKey: peer.id) }
                        }
                        peer.onRequest = { [weak self] request, peer in
                            await self?.handle(request, peer: peer, generation: current)
                        }
                        peer.start()
                    }
                }
                server.stateUpdateHandler = { [weak self, weak server] state in
                    Task { @MainActor [weak self, weak server] in
                        guard let self, self.generation == current else { return }
                        switch state {
                        case .ready:
                            guard let port = server?.port else { return }
                            self.running = true
                            self.starting = false
                            self.oldIdle = UIApplication.shared.isIdleTimerDisabled
                            UIApplication.shared.isIdleTimerDisabled = true
                            self.connectionURL = "http://\(ip):\(port.rawValue)/#\(self.token)"
                            self.status = "Ready. The Mac initiates all connections. Keep this screen open."
                        case .failed(let error): self.stop(); self.status = error.localizedDescription
                        case .waiting(let error): self.status = "Waiting for Wi-Fi / Local Network permission: \(error.localizedDescription)"
                        default: break
                        }
                    }
                }
                server.start(queue: .main)
                status = "Starting Wi-Fi server…"
            } catch { starting = false; status = error.localizedDescription }
        }
    }

    func stop() {
        startTask?.cancel()
        generation = UUID()
        listener?.cancel()
        listener = nil
        for peer in Array(peers.values) { peer.close() }
        peers.removeAll()
        resources.removeAll()
        token = ""
        connectionURL = ""
        if running { UIApplication.shared.isIdleTimerDisabled = oldIdle }
        running = false
        starting = false
        serving = false
        served = 0
        status = "Stopped. Files already downloaded remain on the Mac."
    }

    private func handle(_ request: PhotoExportHTTP.Request, peer: PhotoExportHTTP, generation current: UUID) async {
        guard request.authorization == "Bearer \(token)", !token.isEmpty else {
            try? await peer.json(["error": "Invalid session key. Copy the current address from the iPhone."], status: 401)
            return
        }
        guard !serving else {
            try? await peer.json(["error": "Another request is preparing or downloading a file; retry shortly."], status: 409)
            return
        }
        serving = true
        defer { if generation == current { serving = false } }
        do {
            guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else {
                throw failure("Full Photos access is no longer available.")
            }
            guard let url = URLComponents(string: "http://iphone" + request.target) else { throw failure("Invalid request") }
            if url.path == "/manifest" {
                let date = url.queryItems?.first(where: { $0.name == "date" })?.value ?? ""
                let zoneName = url.queryItems?.first(where: { $0.name == "timezone" })?.value ?? ""
                guard let zone = TimeZone(identifier: zoneName) else { throw failure("Invalid timezone") }
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.calendar = Calendar(identifier: .gregorian)
                formatter.timeZone = zone
                formatter.dateFormat = "yyyy-MM-dd"
                formatter.isLenient = false
                guard let start = formatter.date(from: date), formatter.string(from: start) == date else { throw failure("Use YYYY-MM-DD") }
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = zone
                let end = calendar.date(byAdding: .day, value: 1, to: start)!
                status = "Finding photos and videos for \(date) (\(zoneName))…"
                let options = PHFetchOptions()
                options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@ AND (mediaType == %d OR mediaType == %d)", start as NSDate, end as NSDate, PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
                options.includeAllBurstAssets = true
                options.includeHiddenAssets = true
                options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
                let assets = PHAsset.fetchAssets(with: options)
                resources.removeAll()
                served = 0
                var files: [[String: Any]] = []
                var unavailable = 0
                for index in 0..<assets.count {
                    let asset = assets.object(at: index)
                    let originals = PHAssetResource.assetResources(for: asset).filter {
                        [.photo, .video, .pairedVideo, .alternatePhoto].contains($0.type)
                    }
                    if originals.isEmpty { unavailable += 1 }
                    let assetID = SHA256.hash(data: Data(asset.localIdentifier.utf8)).map { String(format: "%02x", $0) }.joined()
                    for (resourceIndex, resource) in originals.enumerated() {
                        let id = "\(assetID)-\(resourceIndex)"
                        resources[id] = resource
                        files.append(["id": id, "name": resource.originalFilename, "resourceType": resource.type.rawValue,
                                      "captured": ISO8601DateFormatter().string(from: asset.creationDate ?? start)])
                    }
                }
                status = "\(date): \(assets.count) photos/videos, \(files.count) original files ready."
                try await peer.json(["date": date, "timezone": zoneName, "assets": assets.count,
                                     "unavailableAssets": unavailable, "files": files])
            } else if url.path.hasPrefix("/file/") {
                let id = String(url.path.dropFirst(6))
                guard let resource = resources[id] else {
                    try await peer.json(["error": "Unknown file. Request the manifest again."], status: 404)
                    return
                }
                let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("photo-export-" + UUID().uuidString)
                defer { try? FileManager.default.removeItem(at: temporary) }
                status = "Preparing \(resource.originalFilename)…"
                let options = PHAssetResourceRequestOptions()
                options.isNetworkAccessAllowed = true
                try await PHAssetResourceManager.default().writeData(for: resource, toFile: temporary, options: options)
                try Task.checkCancellation()
                let (size, checksum) = try await Task.detached {
                    let file = try FileHandle(forReadingFrom: temporary)
                    defer { try? file.close() }
                    var hash = SHA256()
                    var size: UInt64 = 0
                    while let data = try file.read(upToCount: 1024 * 1024), !data.isEmpty {
                        size += UInt64(data.count)
                        hash.update(data: data)
                    }
                    return (size, hash.finalize().map { String(format: "%02x", $0) }.joined())
                }.value
                try Task.checkCancellation()
                try await peer.file(temporary, size: size, checksum: checksum) { bytes in
                    self.status = "Sending \(resource.originalFilename)\n\(bytes / 1_048_576) / \(size / 1_048_576) MB"
                }
                served += 1
                status = "Served \(served) file requests. The Mac verifies each download."
            } else { try await peer.json(["error": "Not found"], status: 404) }
        } catch {
            if generation == current { status = "Transfer interrupted: \(error.localizedDescription). Retry from the Mac." }
            if !peer.headersSent { try? await peer.json(["error": error.localizedDescription], status: 500) }
        }
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "PhotoExport", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func wifiAddress() -> String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0 else { return nil }
        defer { freeifaddrs(interfaces) }
        var pointer = interfaces
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            guard String(cString: current.pointee.ifa_name) == "en0",
                  let address = current.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                return String(cString: host)
            }
        }
        return nil
    }
}
