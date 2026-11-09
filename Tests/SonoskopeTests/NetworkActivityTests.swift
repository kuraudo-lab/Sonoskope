import SonoskopeCore
import XCTest

@testable import Sonoskope

@MainActor private final class FakeNetwork: NetworkProbing {
  var onPath: ((String) -> Void)?
  var probes = 0
  var cancellations = 0
  var pending: CheckedContinuation<Double?, Never>?
  func start() {}
  func probe() async -> Double? {
    probes += 1
    return await withCheckedContinuation { pending = $0 }
  }
  func cancelProbe() {
    cancellations += 1
    let continuation = pending
    pending = nil
    continuation?.resume(returning: nil)
  }
  func stop() { cancelProbe() }
}

final class NetworkActivityTests: XCTestCase {
  private func sample(_ db: Double = -24, at date: Date = Date(), discontinuity: Bool = false)
    -> AudioMeasurement
  {
    .init(
      date: date, rmsDB: db, peakDB: db, clippingFraction: 0, sampleCount: 1024,
      duration: 0.02, suspectGap: false, discontinuity: discontinuity)
  }
  @MainActor private func settle() async { for _ in 0..<20 { await Task.yield() } }

  @MainActor func testIdleDoesNotProbe() async {
    let network = FakeNetwork()
    let model = MonitorModel(persist: false, runsCollectors: false, networkMonitor: network)
    model.restartNetwork()
    await settle()
    XCTAssertEqual(network.probes, 0)
    XCTAssertFalse(model.networkAudioActive)
    model.shutdown()
  }

  @MainActor func testEitherDirectionAndFreshValidSamplesAreRequired() {
    let model = MonitorModel(persist: false, runsCollectors: false)
    let now = Date()
    model.inputMeasurement = sample(at: now)
    model.updateNetworkActivity(at: now)
    XCTAssertFalse(model.networkAudioActive, "An old reading with capture disabled is not activity")
    model.microphoneRunning = true
    model.updateNetworkActivity(at: now)
    XCTAssertTrue(model.networkAudioActive)
    model.inputMeasurement = sample(-65, at: now)
    model.updateNetworkActivity(at: now)
    XCTAssertFalse(model.networkAudioActive)
    model.outputEnabled = true
    model.outputMeasurement = sample(-40, at: now)
    model.updateNetworkActivity(at: now)
    XCTAssertTrue(model.networkAudioActive, "Output alone is sufficient")
    model.updateNetworkActivity(at: now.addingTimeInterval(3.1))
    XCTAssertFalse(model.networkAudioActive)
    for invalid in [
      sample(.nan, at: now), sample(at: now, discontinuity: true),
      sample(at: now.addingTimeInterval(1)),
    ] {
      model.outputMeasurement = invalid
      model.updateNetworkActivity(at: now)
      XCTAssertFalse(model.networkAudioActive)
    }
    model.outputMeasurement = sample(at: now)
    model.networkEnabled = false
    model.updateNetworkActivity(at: now)
    XCTAssertFalse(model.networkAudioActive)
    model.shutdown()
  }

  @MainActor func testSilenceCancelsInFlightProbeWithoutTimeoutOrRecoveryAndRestartsCleanly() async
  {
    let network = FakeNetwork()
    let model = MonitorModel(persist: false, runsCollectors: false, networkMonitor: network)
    model.outputEnabled = true
    model.outputMeasurement = sample()
    model.restartNetwork()
    await settle()
    XCTAssertEqual(network.probes, 1)
    XCTAssertNotNil(network.pending)
    model.outputMeasurement = sample(-120)
    model.updateNetworkActivity()
    XCTAssertNil(network.pending)
    XCTAssertFalse(model.networkAudioActive)
    // Resume before the cancelled continuation executes: it must still be discarded.
    model.outputMeasurement = sample()
    model.updateNetworkActivity()
    await settle()
    XCTAssertTrue(model.network.samples.isEmpty)
    XCTAssertTrue(model.networkHistory.points.isEmpty)
    XCTAssertTrue(model.latestEvents.isEmpty)
    XCTAssertEqual(network.probes, 1, "Rapid activity changes must respect the cooldown")
    model.shutdown()
    XCTAssertFalse(model.networkAudioActive)
  }

  @MainActor func testPauseAndDemoCannotProbe() async {
    for demo in [false, true] {
      let network = FakeNetwork()
      let model = MonitorModel(persist: false, runsCollectors: false, networkMonitor: network)
      model.outputEnabled = true
      model.outputMeasurement = sample()
      if demo { model.runDemo(.networkOnly) } else { model.togglePause() }
      model.restartNetwork()
      await settle()
      XCTAssertEqual(network.probes, 0)
      model.shutdown()
    }
  }
}
