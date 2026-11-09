import Foundation

public struct TelemetryPoint: Identifiable, Sendable {
  public let id = UUID()
  public let date: Date
  public let value: Double?
  public let source: String
  public let segment: Int
  public var series: String { source + ":" + String(segment) }
}

/// Bounded metric history. Missing readings break lines; they are never plotted as zero.
public struct TelemetryHistory: Sendable {
  public private(set) var points: [TelemetryPoint] = []
  private var segments: [String: Int] = [:]
  private var lastDates: [String: Date] = [:]
  public init() {}
  public mutating func append(value: Double?, source: String, date: Date, maximumGap: TimeInterval)
  {
    if let last = lastDates[source], date.timeIntervalSince(last) > maximumGap {
      breakSeries(source)
    }
    let valid = value.flatMap { $0.isFinite ? $0 : nil }
    if valid == nil { breakSeries(source) }
    points.append(
      .init(date: date, value: valid, source: source, segment: segments[source, default: 0]))
    lastDates[source] = date
    points = Array(points.filter { date.timeIntervalSince($0.date) <= 300 }.suffix(3000))
  }
  public mutating func breakSeries(_ source: String) {
    segments[source, default: 0] += 1
    lastDates[source] = nil
  }
  public func recent(endingAt date: Date, seconds: TimeInterval = 60) -> [TelemetryPoint] {
    points.filter { $0.date >= date.addingTimeInterval(-seconds) && $0.date <= date }
  }
}
