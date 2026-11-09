import Foundation

public struct AudioMeasurement: Codable, Sendable {
  public var date: Date
  public var rmsDB: Double
  public var peakDB: Double
  public var clippingFraction: Double
  public var sampleCount: Int
  public var duration: Double
  public var suspectGap: Bool
  public var discontinuity: Bool
  public init(
    date: Date, rmsDB: Double, peakDB: Double, clippingFraction: Double, sampleCount: Int,
    duration: Double, suspectGap: Bool, discontinuity: Bool
  ) {
    self.date = date
    self.rmsDB = rmsDB
    self.peakDB = peakDB
    self.clippingFraction = clippingFraction
    self.sampleCount = sampleCount
    self.duration = duration
    self.suspectGap = suspectGap
    self.discontinuity = discontinuity
  }
}

/// Inputs are mono energy windows, not downmixed signed samples (which can cancel stereo).
public struct AudioAnalyzer: Sendable {
  private var voicedSeconds = 0.0
  private var silenceSeconds = 0.0
  private var previousEnd: Double?
  private var eligibleSilence = false
  public init() {}
  public mutating func reset() { self = .init() }
  public mutating func analyze(
    samples: [Float], sampleRate: Double, date: Date = Date(), streamTime: Double? = nil
  ) -> AudioMeasurement? {
    guard sampleRate.isFinite, sampleRate > 0, !samples.isEmpty, samples.allSatisfy({ $0.isFinite })
    else { return nil }
    let energy = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
    let peak = samples.reduce(0.0) { max($0, abs(Double($1))) }
    return measure(
      sumSquares: energy, peak: peak, clipped: samples.filter { abs($0) >= 0.999 }.count,
      sampleCount: samples.count, duration: Double(samples.count) / sampleRate, date: date,
      streamTime: streamTime)
  }
  public mutating func measure(
    sumSquares: Double, peak: Double, clipped: Int, sampleCount: Int, duration: Double,
    date: Date = Date(), streamTime: Double? = nil
  ) -> AudioMeasurement? {
    guard sampleCount > 0, duration > 0, duration.isFinite, sumSquares.isFinite, peak.isFinite
    else { return nil }
    var discontinuity = false
    if let streamTime {
      if let end = previousEnd {
        discontinuity = abs(streamTime - end) > max(0.005, duration * 0.25)
      }
      previousEnd = streamTime + duration
    }
    if discontinuity {
      voicedSeconds = 0
      silenceSeconds = 0
      eligibleSilence = false
    }
    let rms = sqrt(max(0, sumSquares) / Double(sampleCount))
    let db = 20 * log10(max(rms, 0.000001))
    var gap = false
    if db < -65 {
      if silenceSeconds == 0 { eligibleSilence = voicedSeconds >= 0.2 }
      silenceSeconds += duration
      voicedSeconds = 0
    } else if db > -40 {
      gap = eligibleSilence && silenceSeconds >= 0.04 && silenceSeconds <= 0.25 && !discontinuity
      silenceSeconds = 0
      eligibleSilence = false
      voicedSeconds += duration
    } else {
      // Quiet speech/noise is ambiguous, not a hard digital gap.
      silenceSeconds = 0
      eligibleSilence = false
      voicedSeconds = 0
    }
    return .init(
      date: date, rmsDB: db, peakDB: 20 * log10(max(peak, 0.000001)),
      clippingFraction: Double(clipped) / Double(sampleCount), sampleCount: sampleCount,
      duration: duration, suspectGap: gap, discontinuity: discontinuity)
  }
}

public struct ProbeSample: Codable, Sendable {
  public var date: Date
  public var milliseconds: Double?
  public init(date: Date = Date(), milliseconds: Double?) {
    self.date = date
    self.milliseconds = milliseconds
  }
}
public struct ProbeSummary: Sendable {
  public var count: Int
  public var timeoutFraction: Double
  public var medianMilliseconds: Double?
  public var variationMilliseconds: Double?
  public var degraded: Bool
  public init(samples: [ProbeSample]) {
    count = samples.count
    let values = samples.compactMap(\.milliseconds).filter { $0.isFinite && $0 >= 0 }.sorted()
    timeoutFraction =
      samples.isEmpty ? 0 : Double(samples.count - values.count) / Double(samples.count)
    medianMilliseconds = values.isEmpty ? nil : values[values.count / 2]
    variationMilliseconds = values.count < 2 ? nil : values.last! - values.first!
    degraded =
      count >= 3
      && (timeoutFraction >= 0.5 || (medianMilliseconds ?? 0) > 500
        || (variationMilliseconds ?? 0) > 400)
  }
}

public enum BluetoothReading {
  public static func validRSSI(_ value: Int) -> Int? {
    value == 127 || value > 20 || value < -127 ? nil : value
  }
}
