import SonoskopeCore
import XCTest
@testable import Sonoskope

final class OutputSilenceTests: XCTestCase {
  private let origin = Date(timeIntervalSince1970: 1_800_000_000)
  private func sample(_ index: Int, db: Double = -120, peak: Double? = nil,
    discontinuity: Bool = false) -> AudioMeasurement {
    .init(date: origin.addingTimeInterval(Double(index) * 0.25), rmsDB: db,
      peakDB: peak ?? db, clippingFraction: 0, sampleCount: 12000, duration: 0.25,
      suspectGap: false, discontinuity: discontinuity)
  }
  @MainActor private func feed(_ model: MonitorModel, _ range: Range<Int>, db: Double = -120) {
    for index in range {
      let value = sample(index, db: db)
      model.acceptOutputMeasurement(value, receivedAt: value.date)
    }
  }
  @MainActor private func model() -> MonitorModel {
    let model = MonitorModel(persist: false, runsCollectors: false)
    model.setOutputEnabled(true)
    return model
  }
  @MainActor func testDefaultFiveMinutesPausesAllMonitoringAndResumeStartsFresh() {
    let model = model()
    XCTAssertEqual(model.outputSilenceMinutes, 5)
    model.microphoneRunning = true
    feed(model, 0..<1199)
    XCTAssertFalse(model.paused)
    feed(model, 1199..<1200)
    XCTAssertTrue(model.paused)
    XCTAssertEqual(model.outputSilencePauseMinutes, 5)
    XCTAssertFalse(model.microphoneRunning)
    XCTAssertFalse(model.networkAudioActive)
    XCTAssertNil(model.outputMeasurement)
    XCTAssertTrue(model.outputEnabled, "Keep the opt-in for explicit resume")
    let count = model.audioHistory.points.count
    feed(model, 1200..<1210)
    XCTAssertEqual(model.audioHistory.points.count, count, "Late callbacks must be ignored")
    model.togglePause()
    XCTAssertNil(model.outputSilencePauseMinutes)
    feed(model, 1210..<2409)
    XCTAssertFalse(model.paused)
    feed(model, 2409..<2410)
    XCTAssertTrue(model.paused)
    model.shutdown()
  }
  @MainActor func testSoundResetsTimerAndZeroDBFSIsNotSilence() {
    let model = model()
    model.setOutputSilenceMinutes(1)
    feed(model, 0..<239)
    feed(model, 239..<240, db: 0)
    feed(model, 240..<479)
    XCTAssertFalse(model.paused)
    feed(model, 479..<480)
    XCTAssertTrue(model.paused)
    model.shutdown()
  }
  @MainActor func testMissingStaleAndDiscontinuousDataCannotCompleteTimer() {
    for interruption in 0..<3 {
      let model = model()
      model.setOutputSilenceMinutes(1)
      feed(model, 0..<239)
      let next = sample(239, discontinuity: interruption == 0)
      if interruption == 0 { model.acceptOutputMeasurement(next, receivedAt: next.date) }
      if interruption == 1 {
        model.acceptOutputMeasurement(next, receivedAt: next.date.addingTimeInterval(4))
      }
      let start = interruption == 2 ? 300 : 240
      feed(model, start..<(start + 239))
      XCTAssertFalse(model.paused)
      feed(model, (start + 239)..<(start + 240))
      XCTAssertTrue(model.paused)
      model.shutdown()
    }
  }
  @MainActor func testScopeSleepAndDemoResetTheTimer() {
    for transition in 0..<3 {
      let model = model()
      model.setOutputSilenceMinutes(1)
      feed(model, 0..<239)
      switch transition {
      case 0: model.selectProcess(42)
      case 1:
        model.systemWillSleep()
        feed(model, 239..<500)
        model.systemDidWake()
      default:
        model.runDemo(.normal)
        feed(model, 239..<500)
        XCTAssertFalse(model.paused)
        model.exitDemo()
      }
      feed(model, 500..<739)
      XCTAssertFalse(model.paused)
      feed(model, 739..<740)
      XCTAssertTrue(model.paused)
      model.shutdown()
    }
  }
  @MainActor func testTimeoutPreferencePersistsAndCanBeDisabled() {
    let suite = "Sonoskope.SilenceTests.\(UUID())"
    let settings = UserDefaults(suiteName: suite)!
    defer { settings.removePersistentDomain(forName: suite) }
    let first = MonitorModel(persist: false, runsCollectors: false, settings: settings)
    first.setOutputSilenceMinutes(2)
    let next = MonitorModel(persist: false, runsCollectors: false, settings: settings)
    XCTAssertEqual(next.outputSilenceMinutes, 2)
    next.setOutputEnabled(true)
    feed(next, 0..<479)
    XCTAssertFalse(next.paused)
    feed(next, 479..<480)
    XCTAssertTrue(next.paused)
    next.togglePause()
    next.setOutputSilenceMinutes(0)
    feed(next, 480..<3000)
    XCTAssertFalse(next.paused)
    next.runDemo(.normal)
    next.setOutputSilenceMinutes(9)
    XCTAssertEqual(settings.integer(forKey: "outputSilenceMinutes"), 0)
    next.shutdown()
    first.shutdown()
  }
  func testInvalidWindowsQuietSoundAndPeaksDoNotCountAsZero() {
    for db in [-99.0, -65.0, -24.0, 0.0, Double.nan] {
      var policy = OutputSilencePolicy()
      for i in 0..<300 { XCTAssertFalse(policy.observe(sample(i, db: db), timeout: 60)) }
    }
    var policy = OutputSilencePolicy()
    for i in 0..<300 {
      XCTAssertFalse(policy.observe(sample(i, db: -110, peak: -20), timeout: 60))
    }
    for i in 0..<239 { XCTAssertFalse(policy.observe(sample(i), timeout: 60)) }
    var invalid = sample(239)
    invalid.duration = .nan
    XCTAssertFalse(policy.observe(invalid, timeout: 60))
    for i in 240..<479 { XCTAssertFalse(policy.observe(sample(i), timeout: 60)) }
    XCTAssertTrue(policy.observe(sample(479), timeout: 60))
  }
}
