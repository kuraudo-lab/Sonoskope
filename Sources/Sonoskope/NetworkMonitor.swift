import CoreWLAN
import Foundation
import Network
import SonoskopeCore

struct NetworkReading {
  var path = "等待网络状态"
  var probe = "尚未探测"
  var wifi = "未读取"
  var duration: Double?
  var samples: [ProbeSample] = []
  var lastUpdated: Date?
}

@MainActor final class NetworkMonitor {
  var onPath: ((String) -> Void)?
  private var monitor: NWPathMonitor?
  private var connection: NWConnection?
  private var pending: CheckedContinuation<Double?, Never>?
  private var timeout: Task<Void, Never>?
  private var started: ContinuousClock.Instant?
  private var generation = UUID()
  func start() {
    guard monitor == nil else { return }
    let monitor = NWPathMonitor()
    self.monitor = monitor
    monitor.pathUpdateHandler = { [weak self] path in
      let status: String
      if path.status != .satisfied {
        status = "网络路径不可用"
      } else if path.usesInterfaceType(.wifi) {
        status = "Wi-Fi 路径可用"
      } else if path.usesInterfaceType(.wiredEthernet) {
        status = "有线路径可用"
      } else {
        status = "网络路径可用"
      }
      Task { @MainActor in self?.onPath?(status) }
    }
    monitor.start(queue: DispatchQueue(label: "lab.kuraudo.Sonoskope.path"))
  }
  func probe(host: String = "www.apple.com", port: UInt16 = 443) async -> Double? {
    finish(nil)
    let token = UUID()
    generation = token
    return await withCheckedContinuation { continuation in
      pending = continuation
      let connection = NWConnection(
        host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
      self.connection = connection
      started = .now
      connection.stateUpdateHandler = { [weak self] state in
        Task { @MainActor in
          guard let self, self.generation == token else { return }
          switch state {
          case .ready:
            let elapsed = self.started?.duration(to: .now)
            let ms = elapsed.map {
              Double($0.components.seconds) * 1000 + Double($0.components.attoseconds) / 1e15
            }
            self.finish(ms)
          case .failed: self.finish(nil)
          default: break
          }
        }
      }
      connection.start(queue: DispatchQueue(label: "lab.kuraudo.Sonoskope.probe"))
      timeout = Task { [weak self] in
        do { try await Task.sleep(for: .seconds(3)) } catch { return }
        guard self?.generation == token else { return }
        self?.finish(nil)
      }
    }
  }
  private func finish(_ value: Double?) {
    connection?.stateUpdateHandler = nil
    connection?.cancel()
    connection = nil
    timeout?.cancel()
    timeout = nil
    let continuation = pending
    pending = nil
    continuation?.resume(returning: value)
  }
  func stop() {
    generation = UUID()
    finish(nil)
    monitor?.cancel()
    monitor = nil
  }
  static func wifiDescription() -> String {
    guard let interface = CWWiFiClient.shared().interface(), interface.powerOn() else {
      return "Wi-Fi 未启用或不可读取"
    }
    let rssi = interface.rssiValue()
    let noise = interface.noiseMeasurement()
    let rate = interface.transmitRate()
    guard rssi != 0, rate > 0 else { return "Wi-Fi 指标不可用" }
    return "RSSI \(rssi) dBm · 噪声 \(noise) dBm · 链路速率 \(Int(rate)) Mbps（非吞吐量）"
  }
}
