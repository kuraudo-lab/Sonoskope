import Foundation

/// Serial, off-main queries: a slow HAL/Bluetooth call must not block AppKit.
actor HardwareReader {
  private let read: (Bool) -> HardwareSnapshot
  init(read: @escaping (Bool) -> HardwareSnapshot = { AudioHAL.snapshot(includeBluetooth: $0) }) {
    self.read = read
  }
  func snapshot(bluetooth: Bool) -> HardwareSnapshot {
    guard !Task.isCancelled else { return HardwareSnapshot() }
    return read(bluetooth)
  }
}
