import SonoskopeCore
import XCTest

@testable import Sonoskope

final class ExperienceStateTests: XCTestCase {
  func testClosingOrSkippingGuidePersistsPresentationOnly() {
    let name = "Sonoskope.OnboardingTests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let progress = OnboardingProgress(defaults: defaults)
    XCTAssertTrue(progress.shouldPresent)
    progress.acknowledge()
    XCTAssertFalse(OnboardingProgress(defaults: defaults).shouldPresent)
    XCTAssertEqual(defaults.integer(forKey: "onboardingVersion"), OnboardingProgress.version)
    XCTAssertNil(defaults.object(forKey: "automaticInput"))
    XCTAssertNil(defaults.object(forKey: "output"))
    XCTAssertNil(defaults.object(forKey: "notifications"))
  }

  func testExistingGuideCompletionDoesNotReplayAfterUpgrade() {
    let name = "Sonoskope.OnboardingTests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set(true, forKey: "gettingStartedSeen")
    defaults.set(true, forKey: "automaticInput")
    XCTAssertFalse(OnboardingProgress(defaults: defaults).shouldPresent)
    XCTAssertTrue(defaults.bool(forKey: "automaticInput"))
  }

  @MainActor func testReadingOldIssueIsNotReplacedByIncomingEvent() {
    let model = MonitorModel(persist: false, runsCollectors: false)
    defer { model.shutdown() }
    model.receive(
      .init(kind: .deviceDisconnected, source: "first-device", message: "First event"),
      audioActive: true)
    let oldID = model.incidents.first!.id
    let navigation = StatusNavigation()
    navigation.showIncident(oldID)
    model.receive(
      .init(kind: .deviceDisconnected, source: "second-device", message: "New event"),
      audioActive: true)
    XCTAssertNotEqual(model.selectedIncidentID, oldID)
    XCTAssertEqual(navigation.section, .issues)
    XCTAssertEqual(navigation.incidentID, oldID)
    XCTAssertNotNil(model.incidents.first { $0.id == navigation.incidentID })
    navigation.showOverview()
    XCTAssertEqual(navigation.section, .overview)
    XCTAssertNil(navigation.incidentID)
  }
}
