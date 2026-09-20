import Foundation
import Network

/// One bounded HTTP GET request per TCP connection; responses stream with backpressure.
@MainActor
final class PhotoExportHTTP {
    struct Request {
        let target: String
        let authorization: String
    }
    let id = UUID()
    private let connection: NWConnection
    private var buffer = Data()
    private var work: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var closed = false
    private(set) var headersSent = false
    var onRequest: ((Request, PhotoExportHTTP) async -> Void)?
    var onClose: (() -> Void)?

    init(_ connection: NWConnection) { self.connection = connection }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .ready: self.readHeaders()
                case .failed, .cancelled: self.close()
                default: break
                }
            }
        }
        connection.start(queue: .main)
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            if !Task.isCancelled { self?.close() }
        }
    }

    func close() {
        guard !closed else { return }
        closed = true
        timeout?.cancel()
        work?.cancel()
        connection.cancel()
        onClose?()
        onRequest = nil
        onClose = nil
    }

    private func readHeaders() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, ended, error in
            Task { @MainActor [weak self] in
                guard let self, !self.closed else { return }
                if let data { self.buffer.append(data) }
                if self.buffer.count > 16_384 { self.close(); return }
                if let boundary = self.buffer.range(of: Data("\r\n\r\n".utf8)) {
                    self.timeout?.cancel()
                    guard let text = String(data: self.buffer[..<boundary.lowerBound], encoding: .utf8) else { self.close(); return }
                    let lines = text.components(separatedBy: "\r\n")
                    let first = (lines.first ?? "").split(separator: " ")
                    guard first.count == 3, first[0] == "GET", first[1].hasPrefix("/"),
                          ["HTTP/1.0", "HTTP/1.1"].contains(String(first[2])) else { self.close(); return }
                    var fields: [String: String] = [:]
                    for line in lines.dropFirst() {
                        let pair = line.split(separator: ":", maxSplits: 1)
                        guard pair.count == 2 else { self.close(); return }
                        let key = pair[0].lowercased()
                        guard fields[key] == nil else { self.close(); return }
                        fields[key] = pair[1].trimmingCharacters(in: .whitespaces)
                    }
                    guard fields["transfer-encoding"] == nil,
                          fields["content-length"] == nil || fields["content-length"] == "0" else { self.close(); return }
                    let request = Request(target: String(first[1]), authorization: fields["authorization"] ?? "")
                    self.work = Task { [weak self] in
                        guard let self else { return }
                        await self.onRequest?(request, self)
                        self.close()
                    }
                } else if error != nil || ended { self.close() }
                else { self.readHeaders() }
            }
        }
    }

    private func send(_ data: Data, final: Bool = false) async throws {
        try Task.checkCancellation()
        guard !closed else { throw URLError(.networkConnectionLost) }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, isComplete: final, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            })
        }
    }

    private func headers(status: Int, type: String, size: UInt64, checksum: String? = nil) async throws {
        var text = "HTTP/1.1 \(status) \(status == 200 ? "OK" : "Error")\r\nContent-Type: \(type)\r\nContent-Length: \(size)\r\nConnection: close\r\nCache-Control: no-store\r\n"
        if let checksum { text += "X-SHA256: \(checksum)\r\n" }
        text += "\r\n"
        headersSent = true
        try await send(Data(text.utf8))
    }

    func json(_ value: [String: Any], status: Int = 200) async throws {
        let data = try JSONSerialization.data(withJSONObject: value)
        try await headers(status: status, type: "application/json", size: UInt64(data.count))
        try await send(data, final: true)
    }

    func file(_ url: URL, size: UInt64, checksum: String, progress: (UInt64) -> Void) async throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try await headers(status: 200, type: "application/octet-stream", size: size, checksum: checksum)
        var sent: UInt64 = 0
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            try await send(chunk)
            sent += UInt64(chunk.count)
            progress(sent)
        }
        guard sent == size else { throw URLError(.cannotDecodeContentData) }
        try await send(Data(), final: true)
    }
}
