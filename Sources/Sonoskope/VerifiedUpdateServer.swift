import Foundation
import Network

/// A short-lived, loopback-only bridge for Sparkle's HTTP downloader. Created
/// only after explicit install consent; the random path exposes one verified
/// archive. Sparkle independently checks its EdDSA and code signatures again.
@MainActor final class VerifiedUpdateServer {
  private var listener: NWListener?
  private var connections: [UUID: NWConnection] = [:]
  private var archive = Data()
  private let path = "/" + UUID().uuidString + "/update.zip"
  private var startup: CheckedContinuation<URL, Error>?

  func start(file: URL) async throws -> URL {
    archive = try Data(contentsOf: file, options: .mappedIfSafe)
    let parameters = NWParameters.tcp
    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
    let listener = try NWListener(using: parameters)
    self.listener = listener
    return try await withCheckedThrowingContinuation { continuation in
      startup = continuation
      listener.stateUpdateHandler = { [weak self] state in
        Task { @MainActor in
          guard let self else { return }
          switch state {
          case .ready:
            if let port = self.listener?.port {
              self.startup?.resume(returning: URL(string: "http://127.0.0.1:\(port.rawValue)\(self.path)")!)
              self.startup = nil
            }
          case .failed(let error): self.startup?.resume(throwing: error); self.startup = nil; self.stop()
          default: break
          }
        }
      }
      listener.newConnectionHandler = { [weak self] connection in
        Task { @MainActor in self?.accept(connection) }
      }
      listener.start(queue: .main)
    }
  }

  func stop() {
    startup?.resume(throwing: CancellationError()); startup = nil
    listener?.cancel(); listener = nil
    for connection in connections.values { connection.cancel() }
    connections.removeAll(); archive = Data()
  }

  private func accept(_ connection: NWConnection) {
    guard connections.count < 4, listener != nil else { connection.cancel(); return }
    let id = UUID()
    connections[id] = connection
    connection.start(queue: .main)
    receive(connection, id: id, bytes: Data())
    Task { [weak self] in
      try? await Task.sleep(for: .seconds(30))
      self?.close(id)
    }
  }

  private func receive(_ connection: NWConnection, id: UUID, bytes: Data) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
      Task { @MainActor in
        guard let self, self.connections[id] != nil else { return }
        let request = bytes + (data ?? Data())
        guard error == nil, request.count <= 8192 else { self.close(id); return }
        if let text = String(data: request, encoding: .utf8), text.contains("\r\n\r\n") {
          guard text.hasPrefix("GET \(self.path) HTTP/1.1\r\n") else { self.close(id); return }
          let header = Data("HTTP/1.1 200 OK\r\nContent-Type: application/zip\r\nContent-Length: \(self.archive.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n".utf8)
          connection.send(content: header, completion: .contentProcessed { error in
            Task { @MainActor in
              if error != nil { self.close(id) } else { self.send(connection, id: id, offset: 0) }
            }
          })
        } else if complete { self.close(id) }
        else { self.receive(connection, id: id, bytes: request) }
      }
    }
  }

  private func send(_ connection: NWConnection, id: UUID, offset: Int) {
    guard connections[id] != nil else { return }
    let end = min(offset + 256 * 1024, archive.count)
    let last = end == archive.count
    connection.send(content: archive.subdata(in: offset..<end), isComplete: last, completion: .contentProcessed { [weak self] error in
      Task { @MainActor in
        guard let self else { return }
        if error != nil || last { self.close(id) }
        else { self.send(connection, id: id, offset: end) }
      }
    })
  }
  private func close(_ id: UUID) { connections.removeValue(forKey: id)?.cancel() }
}
