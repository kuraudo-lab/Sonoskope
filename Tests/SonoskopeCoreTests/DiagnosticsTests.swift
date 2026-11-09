import XCTest

@testable import SonoskopeCore

final class DiagnosticsTests: XCTestCase {
  let start = Date(timeIntervalSince1970: 1_000)
  func event(
    _ kind: EventKind, _ seconds: Double = 0, source: String = "headset",
    direction: Direction = .shared
  ) -> DiagnosticEvent {
    .init(
      kind: kind, direction: direction, source: source, message: "test observation",
      date: start.addingTimeInterval(seconds))
  }
  func testIdleDisconnectDoesNotAlert() {
    var engine = DiagnosticEngine()
    let update = engine.ingest(event(.deviceDisconnected), audioActive: false)
    XCTAssertNil(update.notification)
    XCTAssertTrue(engine.incidents.isEmpty)
  }
  func testDisconnectDeduplicatesAndRecoveryUpdatesSameIncident() {
    var engine = DiagnosticEngine()
    let first = engine.ingest(event(.deviceDisconnected), audioActive: true)
    XCTAssertNotNil(first.notification)
    XCTAssertNil(engine.ingest(event(.deviceDisconnected, 1), audioActive: true).notification)
    let recovered = engine.ingest(event(.deviceRestored, 4), audioActive: true)
    XCTAssertEqual(engine.incidents.count, 1)
    XCTAssertEqual(recovered.changedIncident?.id, first.changedIncident?.id)
    XCTAssertEqual(recovered.changedIncident?.recovered, start.addingTimeInterval(4))
    XCTAssertNil(recovered.notification)
  }
  func testRepeatedReconnectWithinCooldownDoesNotSpam() {
    var engine = DiagnosticEngine()
    _ = engine.ingest(event(.deviceDisconnected), audioActive: true)
    _ = engine.ingest(event(.deviceRestored, 2), audioActive: true)
    XCTAssertNil(engine.ingest(event(.deviceDisconnected, 5), audioActive: true).notification)
    XCTAssertEqual(engine.incidents.count, 2)
  }
  func testNetworkOnlyNeverClaimsAudioFailureOrAlerts() {
    var engine = DiagnosticEngine()
    let update = engine.ingest(event(.networkDegraded), audioActive: true)
    XCTAssertNil(update.notification)
    XCTAssertEqual(update.changedIncident?.title, "网络探测出现波动")
    XCTAssertTrue(update.changedIncident!.explanation.contains("不能证明"))
  }
  func testSingleGapIsInsufficientRepeatedGapsAreSuspectedNotConfirmed() {
    var engine = DiagnosticEngine()
    XCTAssertNil(
      engine.ingest(event(.audioGap, source: "output", direction: .output), audioActive: true)
        .notification)
    XCTAssertNil(
      engine.ingest(event(.audioGap, 2, source: "output", direction: .output), audioActive: true)
        .notification)
    let result = engine.ingest(
      event(.audioGap, 4, source: "output", direction: .output), audioActive: true)
    XCTAssertEqual(result.notification?.confidence, .suspected)
  }
  func testInputAndOutputEvidenceAreNotCombined() {
    var engine = DiagnosticEngine()
    _ = engine.ingest(event(.audioGap, 0, direction: .input), audioActive: true)
    _ = engine.ingest(event(.audioGap, 1, direction: .input), audioActive: true)
    XCTAssertNil(
      engine.ingest(event(.audioGap, 2, direction: .output), audioActive: true).notification)
  }
  func testOldGapsExpire() {
    var engine = DiagnosticEngine()
    _ = engine.ingest(event(.audioGap), audioActive: true)
    _ = engine.ingest(event(.audioGap, 1), audioActive: true)
    XCTAssertNil(engine.ingest(event(.audioGap, 40), audioActive: true).notification)
  }
  func testCorrelationIsExplicitlyNotCausation() {
    var engine = DiagnosticEngine()
    for e in DemoScenario.correlated.events(at: start) { _ = engine.ingest(e, audioActive: true) }
    let incident = engine.incidents.last!
    XCTAssertEqual(incident.confidence, .suspected)
    XCTAssertTrue(incident.explanation.contains("尚不能确认因果"))
    XCTAssertTrue(incident.evidence.contains { $0.kind == .networkDegraded })
  }
  func testCollectorFailureIsNotAudioFailure() {
    var engine = DiagnosticEngine()
    let result = engine.ingest(event(.captureUnavailable, direction: .output), audioActive: true)
    XCTAssertNil(result.notification)
    XCTAssertEqual(result.changedIncident?.title, "音频监测不完整")
  }
  func testRouteChangesAreEvidenceNotFailures() {
    var engine = DiagnosticEngine()
    _ = engine.ingest(event(.routeChanged), audioActive: true)
    _ = engine.ingest(event(.formatChanged), audioActive: true)
    XCTAssertEqual(engine.events.count, 2)
    XCTAssertTrue(engine.incidents.isEmpty)
  }
  func testRestoredHistoryDoesNotAssertStillActive() {
    var engine = DiagnosticEngine()
    _ = engine.ingest(event(.deviceDisconnected), audioActive: true)
    let loaded = DiagnosticEngine(incidents: engine.incidents)
    XCTAssertFalse(loaded.incidents[0].isActive)
  }
  func testPruningRemovesExpiredHistory() {
    var engine = DiagnosticEngine()
    _ = engine.ingest(event(.userMarked), audioActive: false)
    engine.prune(before: start.addingTimeInterval(1))
    XCTAssertTrue(engine.incidents.isEmpty)
  }
  func testAllScenariosRunAndNormalRemainsEmpty() {
    for scenario in DemoScenario.allCases {
      var engine = DiagnosticEngine()
      for e in scenario.events(at: start) { _ = engine.ingest(e, audioActive: true) }
      XCTAssertEqual(engine.incidents.isEmpty, scenario == .normal)
    }
  }
  func testRecoveredNetworkDoesNotCauseStaleCorrelation() {
    var engine = DiagnosticEngine()
    _ = engine.ingest(event(.networkDegraded, 0), audioActive: true)
    _ = engine.ingest(event(.networkRecovered, 1), audioActive: true)
    for second in 2...4 { _ = engine.ingest(event(.audioGap, Double(second)), audioActive: true) }
    XCTAssertFalse(engine.incidents.last!.explanation.contains("网络"))
  }
  func testResetObservationWindowDoesNotMixSessions() {
    var engine = DiagnosticEngine()
    _ = engine.ingest(event(.audioGap, 0), audioActive: true)
    _ = engine.ingest(event(.audioGap, 1), audioActive: true)
    engine.resetObservationWindow()
    XCTAssertNil(engine.ingest(event(.audioGap, 2), audioActive: true).notification)
  }

}
