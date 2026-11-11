import Foundation
import SonoskopeCore

/// A stalled UI retains one metric window, never an unbounded queue of tasks.
/// Coalesced windows are explicitly missing collector data, not audio defects.
final class MeasurementDelivery: @unchecked Sendable {
  private let lock = NSLock()
  private var pending: AudioMeasurement?
  private let schedule: (@escaping @Sendable () -> Void) -> Void
  private let consume: @Sendable (AudioMeasurement) -> Void

  init(
    schedule: @escaping (@escaping @Sendable () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) },
    consume: @escaping @Sendable (AudioMeasurement) -> Void
  ) {
    self.schedule = schedule
    self.consume = consume
  }
  func submit(_ measurement: AudioMeasurement) {
    lock.lock()
    let needsDelivery = pending == nil
    var next = measurement
    if !needsDelivery { next.discontinuity = true }
    pending = next
    lock.unlock()
    if needsDelivery {
      schedule { [self] in
        lock.lock()
        let value = pending
        pending = nil
        lock.unlock()
        if let value { consume(value) }
      }
    }
  }
}
