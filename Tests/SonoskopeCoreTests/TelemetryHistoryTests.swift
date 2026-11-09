import XCTest

@testable import SonoskopeCore

final class TelemetryHistoryTests: XCTestCase {
  let start = Date(timeIntervalSince1970: 1000)
  func testMissingReadingIsNotZeroAndBreaksLine() {
    var history = TelemetryHistory()
    history.append(value: 10, source: "network", date: start, maximumGap: 15)
    history.append(value: nil, source: "network", date: start.addingTimeInterval(5), maximumGap: 15)
    history.append(value: 20, source: "network", date: start.addingTimeInterval(10), maximumGap: 15)
    XCTAssertNil(history.points[1].value)
    XCTAssertNotEqual(history.points[0].series, history.points[2].series)
  }
  func testLongAbsenceBreaksLineAndWindowIsBounded() {
    var history = TelemetryHistory()
    history.append(value: -20, source: "output", date: start, maximumGap: 2)
    history.append(value: -30, source: "output", date: start.addingTimeInterval(3), maximumGap: 2)
    XCTAssertNotEqual(history.points[0].series, history.points[1].series)
    history.append(value: -10, source: "output", date: start.addingTimeInterval(400), maximumGap: 2)
    XCTAssertEqual(history.points.count, 1)
  }
  func testRecentWindowAndNonFiniteReadings() {
    var history = TelemetryHistory()
    history.append(value: 15, source: "network", date: start, maximumGap: 15)
    history.append(
      value: .nan, source: "network", date: start.addingTimeInterval(70), maximumGap: 15)
    let recent = history.recent(endingAt: start.addingTimeInterval(70))
    XCTAssertEqual(recent.count, 1)
    XCTAssertNil(recent[0].value)
  }
  func testApplicationChangesPreserveHistoricalLabelsAndSplitTheLine() {
    var history = TelemetryHistory()
    history.append(value: -20, source: "input", date: start, maximumGap: 2, context: "Voice Memos")
    history.append(
      value: -22, source: "input", date: start.addingTimeInterval(0.5), maximumGap: 2,
      context: "Voice Memos")
    history.append(
      value: -23, source: "input", date: start.addingTimeInterval(1), maximumGap: 2,
      context: "Teams")
    XCTAssertEqual(history.points[0].context, "Voice Memos")
    XCTAssertEqual(history.points[0].series, history.points[1].series)
    XCTAssertNotEqual(history.points[1].series, history.points[2].series)
    XCTAssertEqual(history.points[2].context, "Teams")
  }
  func testIndependentAudioSourcesKeepIndependentSegments() {
    var history = TelemetryHistory()
    history.append(value: -20, source: "input", date: start, maximumGap: 2)
    history.append(value: -30, source: "output", date: start, maximumGap: 2)
    XCTAssertNotEqual(history.points[0].series, history.points[1].series)
  }
}
