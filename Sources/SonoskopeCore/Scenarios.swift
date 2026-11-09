import Foundation

public enum DemoScenario: String, CaseIterable, Identifiable {
  case normal, bluetooth, networkOnly, correlated, recovered, unavailable, markedInput
  public var id: String { rawValue }
  public var label: String {
    switch self {
    case .normal: "正常／静音"
    case .bluetooth: "设备断连"
    case .networkOnly: "仅网络探测异常"
    case .correlated: "音频与网络同时异常"
    case .recovered: "断连后恢复"
    case .unavailable: "采集不可用"
    case .markedInput: "别人听不清我"
    }
  }
  public func events(at date: Date = Date()) -> [DiagnosticEvent] {
    func event(
      _ kind: EventKind, _ source: String, _ message: String, _ offset: Double = 0,
      _ direction: Direction = .shared
    ) -> DiagnosticEvent {
      .init(
        kind: kind, direction: direction, source: source, message: message,
        date: date.addingTimeInterval(offset))
    }
    switch self {
    case .normal: return []
    case .bluetooth: return [event(.deviceDisconnected, "demo-headset", "模拟：耳机从音频设备列表消失")]
    case .networkOnly: return [event(.networkDegraded, "demo-probe", "模拟：测试连接耗时增加；不是会议丢包率")]
    case .correlated:
      return [event(.networkDegraded, "demo-probe", "模拟：探测连接耗时 650 ms", -3)]
        + (-2...0).map { event(.audioGap, "demo-output", "模拟：应用输出出现短缺口", Double($0), .output) }
    case .recovered:
      return [
        event(.deviceDisconnected, "demo-headset", "模拟：耳机断开", -5),
        event(.deviceRestored, "demo-headset", "模拟：耳机重新连接"),
      ]
    case .unavailable: return [event(.captureUnavailable, "demo-output", "模拟：采集权限不可用", 0, .output)]
    case .markedInput: return [event(.userMarked, "user", "模拟：别人反馈听不清我", 0, .input)]
    }
  }
}
