import Foundation

/// Counts only measured, continuous near-zero PCM windows. Missing data is not silence.
public struct OutputSilencePolicy {
  private var lastDate: Date?
  private var silentSeconds: TimeInterval = 0
  public init() {}
  public mutating func reset() { self = .init() }

  public mutating func observe(_ sample: AudioMeasurement, timeout: TimeInterval) -> Bool {
    guard timeout > 0, timeout.isFinite, !sample.discontinuity,
      sample.sampleCount > 0, sample.duration.isFinite, sample.duration > 0,
      sample.duration <= 2, sample.date.timeIntervalSince1970.isFinite,
      sample.rmsDB.isFinite, sample.peakDB.isFinite,
      sample.rmsDB <= -100, sample.peakDB <= -100
    else { reset(); return false }
    var duration = sample.duration
    if let lastDate {
      let elapsed = sample.date.timeIntervalSince(lastDate)
      guard elapsed > 0 else { reset(); return false }
      if elapsed > 2 {
        silentSeconds = 0
      } else {
        duration = min(duration, elapsed)
      }
    }
    lastDate = sample.date
    silentSeconds += duration
    return silentSeconds >= timeout
  }
}
