import Foundation

public struct InputDevice: Equatable, Sendable {
  public let id: UInt32
  public let uid: String
  public let sampleRate: Double
  public init(id: UInt32, uid: String, sampleRate: Double) {
    self.id = id
    self.uid = uid
    self.sampleRate = sampleRate
  }
}
public struct InputProcessActivity: Sendable {
  public let pid: Int32
  public let bundleID: String
  public let running: Bool?
  public let devices: [UInt32]?
  public init(pid: Int32, bundleID: String = "", running: Bool?, devices: [UInt32]?) {
    self.pid = pid
    self.bundleID = bundleID
    self.running = running
    self.devices = devices
  }
}

/// Decisions use external input IO, never signal energy or our own device activity.
/// A nil process list/read is unknown, not evidence that nobody is capturing.
public struct AutomaticInputPolicy: Sendable {
  public enum State: Equatable, Sendable {
    case disabled, suspended, permissionRequired, waiting, unknown, ambiguous, active, stopping
  }
  public private(set) var state: State = .disabled
  public private(set) var target: InputDevice?
  private var idleSince: Date?
  public let idleGrace: TimeInterval
  public init(idleGrace: TimeInterval = 2) { self.idleGrace = idleGrace }

  @discardableResult
  public mutating func update(
    enabled: Bool, suspended: Bool, authorized: Bool,
    processes: [InputProcessActivity]?, devices: [InputDevice], defaultInput: UInt32,
    observerPID: Int32, observerBundleID: String, at date: Date
  ) -> InputDevice? {
    guard enabled else { return clear(.disabled) }
    guard !suspended else { return clear(.suspended) }
    guard authorized else { return clear(.permissionRequired) }
    guard let processes else { return clear(.unknown) }
    let external = processes.filter {
      $0.pid != observerPID && (observerBundleID.isEmpty || $0.bundleID != observerBundleID)
    }
    var unknown = false
    var active = Set<UInt32>()
    let available = Set(devices.map(\.id))
    for process in external {
      guard let running = process.running else {
        unknown = true
        continue
      }
      guard running else { continue }
      guard let ids = process.devices, !ids.isEmpty else {
        unknown = true
        continue
      }
      if !Set(ids).isSubset(of: available) { unknown = true }
      active.formUnion(ids.filter { available.contains($0) })
    }
    // Keep an already observed device stable; do not jump between concurrent apps.
    let selected: UInt32?
    if let target, active.contains(target.id) {
      selected = target.id
    } else if active.count == 1 {
      selected = active.first
    } else if active.contains(defaultInput) {
      selected = defaultInput
    } else {
      selected = nil
    }
    if let selected, let device = devices.first(where: { $0.id == selected }) {
      target = device  // A UID/rate change produces a new capture request in the caller.
      idleSince = nil
      state = .active
      return target
    }
    if !active.isEmpty { return clear(.ambiguous) }
    if unknown { return clear(.unknown) }
    if let target, devices.contains(target) {
      if idleSince == nil { idleSince = date }
      if date.timeIntervalSince(idleSince!) < idleGrace {
        state = .stopping
        return target
      }
    }
    return clear(.waiting)
  }
  public mutating func suspend() { _ = clear(.suspended) }
  private mutating func clear(_ state: State) -> InputDevice? {
    self.state = state
    target = nil
    idleSince = nil
    return nil
  }
}
