import SonoskopeCore

import XCTest
@testable import Sonoskope

final class MonitoringRegressionTests: XCTestCase {
  @MainActor func testOutputOptInSurvivesRestartWithoutStartingCollectorsInTests() {
    let suite = "Sonoskope.Regression.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let first = MonitorModel(persist: false, runsCollectors: false, settings: defaults)
    first.setOutputEnabled(true)
    first.shutdown()
    let second = MonitorModel(persist: false, runsCollectors: false, settings: defaults)
    XCTAssertTrue(second.outputEnabled)
    second.selectProcess(42)
    let scopedRestart = MonitorModel(persist: false, runsCollectors: false, settings: defaults)
    XCTAssertFalse(scopedRestart.outputEnabled, "A process-specific opt-in must not become global")
    second.setOutputEnabled(false)
    let third = MonitorModel(persist: false, runsCollectors: false, settings: defaults)
    XCTAssertFalse(third.outputEnabled)
  }
}

extension MonitoringRegressionTests {
  func testBlockedUIDeliveryRetainsOnlyOnePendingWindowAndMarksMissingData() {
    var jobs: [@Sendable () -> Void] = []
    let sink = MeasurementSink()
    let delivery = MeasurementDelivery(schedule: { jobs.append($0) }, consume: { sink.values.append($0) })
    let start = Date()
    for index in 0..<10000 {
      delivery.submit(.init(date: start.addingTimeInterval(Double(index)), rmsDB: -20,
        peakDB: -10, clippingFraction: 0, sampleCount: 100, duration: 0.25,
        suspectGap: false, discontinuity: false))
    }
    XCTAssertEqual(jobs.count, 1)
    jobs.removeFirst()()
    XCTAssertEqual(sink.values.count, 1)
    XCTAssertEqual(sink.values[0].date, start.addingTimeInterval(9999))
    XCTAssertTrue(sink.values[0].discontinuity)
    delivery.submit(.init(date: start, rmsDB: -20, peakDB: -10,
      clippingFraction: 0, sampleCount: 100, duration: 0.25,
      suspectGap: false, discontinuity: false))
    jobs.removeFirst()()
    XCTAssertFalse(sink.values[1].discontinuity)
  }

  @MainActor func testHardwareQueriesRunOffMainThread() async {
    let reader = HardwareReader { _ in
      XCTAssertFalse(Thread.isMainThread, "Hardware queries must not freeze the UI thread")
      return HardwareSnapshot()
    }
    _ = await reader.snapshot(bluetooth: true)
  }
}

// This fixture's injected scheduler is drained synchronously by the test.
private final class MeasurementSink: @unchecked Sendable {
  var values: [AudioMeasurement] = []
}
