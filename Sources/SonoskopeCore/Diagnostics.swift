import Foundation

public enum Direction: String, Codable, CaseIterable, Sendable {
  case input, output, shared
  public var label: String {
    switch self {
    case .input: "我的声音"
    case .output: "我听到的声音"
    case .shared: "输入与输出"
    }
  }
}
public enum EventKind: String, Codable, Sendable {
  case deviceDisconnected, deviceRestored, routeChanged, formatChanged
  case audioGap, clipping, networkDegraded, networkRecovered
  case captureUnavailable, captureRestored, userMarked, lifecycle
}
public struct DiagnosticEvent: Identifiable, Codable, Sendable {
  public var id: UUID
  public var date: Date
  public var kind: EventKind
  public var direction: Direction
  public var source: String
  public var message: String
  public init(
    kind: EventKind, direction: Direction = .shared, source: String, message: String,
    date: Date = Date()
  ) {
    id = UUID()
    self.kind = kind
    self.direction = direction
    self.source = source
    self.message = message
    self.date = date
  }
}
public enum Confidence: String, Codable, Sendable { case observed, suspected, unknown }
public struct Incident: Identifiable, Codable, Sendable {
  public var id = UUID()
  public var key: String
  public var started: Date
  public var lastSeen: Date
  public var recovered: Date?
  public var endReason: String?
  public var direction: Direction
  public var title: String
  public var explanation: String
  public var nextStep: String
  public var confidence: Confidence
  public var occurrences: Int = 1
  public var evidence: [DiagnosticEvent]
  public var isActive: Bool { recovered == nil }
}
public struct DiagnosticUpdate: Sendable {
  public var changedIncident: Incident?
  public var notification: Incident?
}

/// Rules operate on observations, never on injected fault labels. Unknown stays unknown.
public struct DiagnosticEngine: Sendable {
  public private(set) var events: [DiagnosticEvent] = []
  public private(set) var incidents: [Incident] = []
  private var lastAlert: [String: Date] = [:]
  public init(incidents: [Incident] = []) {
    // Persisted active observations are historical; a new process cannot assert they remain active.
    self.incidents = incidents.map { item in
      var item = item
      if item.recovered == nil {
        item.recovered = item.lastSeen
        item.endReason = "上次运行已结束；当前状态未知"
      }
      return item
    }
  }
  public mutating func ingest(_ event: DiagnosticEvent, audioActive: Bool) -> DiagnosticUpdate {
    events.append(event)
    events = Array(events.filter { event.date.timeIntervalSince($0.date) < 300 }.suffix(300))
    var changed: Incident?
    var notification: Incident?
    let key = "\(event.kind.rawValue):\(event.source):\(event.direction.rawValue)"
    switch event.kind {
    case .deviceRestored:
      changed = recover(prefix: "deviceDisconnected:" + event.source + ":", at: event)
    case .captureRestored:
      changed = recover(prefix: "captureUnavailable:" + event.source + ":", at: event)
    case .networkRecovered:
      changed = recover(prefix: "networkDegraded:" + event.source + ":", at: event)
    case .routeChanged, .formatChanged, .lifecycle:
      break
    case .deviceDisconnected:
      guard audioActive else { return .init() }
      changed = upsert(
        event, key: key, title: "音频设备连接中断", confidence: .observed,
        explanation: "确认本地设备不可用；尚不能确定断开原因或远端实际听感。",
        next: "重新连接设备，并在会议应用中确认输入和输出。")
      notification = eligible(changed!, at: event.date)
    case .captureUnavailable:
      changed = upsert(
        event, key: key, title: "音频监测不完整", confidence: .observed,
        explanation: "采集不可用不等于通话音频损坏。", next: "检查音频权限、选中的应用与采集状态。")
    case .networkDegraded:
      changed = upsert(
        event, key: key, title: "网络探测出现波动", confidence: .observed,
        explanation: "仅反映测试连接，不能证明会议媒体受影响。", next: "如果同时听到异常，可换用有线网络做对照。")
    case .audioGap, .clipping:
      guard audioActive else { return .init() }
      let recent = events.filter {
        $0.kind == event.kind && $0.source == event.source && $0.direction == event.direction
          && event.date.timeIntervalSince($0.date) <= 30
      }
      guard recent.count >= 3 else { return .init() }
      let latestNetwork = events.last {
        $0.kind == .networkDegraded || $0.kind == .networkRecovered
      }
      let network = latestNetwork.flatMap {
        $0.kind == .networkDegraded && event.date.timeIntervalSince($0.date) <= 10 ? $0 : nil
      }
      changed = upsert(
        event, key: key, title: event.kind == .clipping ? "检测到持续近满幅音频" : "检测到重复的可疑音频缺口",
        confidence: .suspected,
        explanation: network == nil
          ? "音频特征存在异常嫌疑；静音、降噪和原始内容也可能产生相似结果。" : "与网络探测异常同时发生，可能相关；尚不能确认因果。",
        next: event.direction == .input ? "用内置麦克风做短测试，比较本地输入。" : "尝试切换播放设备；如果仍异常，再对照网络或远端。")
      if let network, let index = incidents.firstIndex(where: { $0.id == changed?.id }) {
        if !incidents[index].evidence.contains(where: { $0.id == network.id }) {
          incidents[index].evidence.append(network)
        }
        changed = incidents[index]
      }
      notification = eligible(changed!, at: event.date)
    case .userMarked:
      changed = upsert(
        event, key: "mark:" + event.id.uuidString, title: "你标记了声音异常", confidence: .unknown,
        explanation: "已保存时间点与近期指标，原因尚未确定。",
        next: event.direction == .input ? "先测试本地麦克风，确认声音到达 Mac 时是否正常。" : "查看同一时间的应用输出、设备和网络证据。")
      if let index = incidents.firstIndex(where: { $0.id == changed?.id }) {
        incidents[index].evidence = Array(events.suffix(30))
        changed = incidents[index]
      }
    }
    incidents = Array(incidents.suffix(100))
    return .init(changedIncident: changed, notification: notification)
  }
  public mutating func settle(at date: Date) {
    // Signal suspicion expires; this says observations stopped, not that end-to-end sound is fixed.
    for i in incidents.indices where incidents[i].isActive && incidents[i].confidence == .suspected
    {
      if date.timeIntervalSince(incidents[i].lastSeen) > 30 {
        incidents[i].recovered = date
        incidents[i].endReason = "30 秒未再发现相同疑似特征；结束本次观察"
      }
    }
  }
  public mutating func prune(before date: Date) { incidents.removeAll { $0.lastSeen < date } }
  public mutating func resetObservationWindow() { events.removeAll() }
  public mutating func clear() {
    events.removeAll()
    incidents.removeAll()
    lastAlert.removeAll()
  }
  private mutating func upsert(
    _ e: DiagnosticEvent, key: String, title: String, confidence: Confidence, explanation: String,
    next: String
  ) -> Incident {
    if let i = incidents.lastIndex(where: { $0.key == key && $0.isActive }) {
      incidents[i].lastSeen = e.date
      incidents[i].occurrences += 1
      incidents[i].explanation = explanation
      incidents[i].evidence = Array((incidents[i].evidence + [e]).suffix(30))
      return incidents[i]
    }
    let incident = Incident(
      key: key, started: e.date, lastSeen: e.date, direction: e.direction,
      title: title, explanation: explanation, nextStep: next, confidence: confidence, evidence: [e])
    incidents.append(incident)
    return incident
  }
  private mutating func recover(prefix: String, at event: DiagnosticEvent) -> Incident? {
    var result: Incident?
    for i in incidents.indices where incidents[i].key.hasPrefix(prefix) && incidents[i].isActive {
      incidents[i].recovered = event.date
      incidents[i].endReason = event.message
      incidents[i].evidence.append(event)
      result = incidents[i]
    }
    return result
  }
  private mutating func eligible(_ incident: Incident, at date: Date) -> Incident? {
    guard incident.occurrences == 1 else { return nil }
    if let last = lastAlert[incident.key], date.timeIntervalSince(last) < 120 { return nil }
    lastAlert[incident.key] = date
    return incident
  }
}
