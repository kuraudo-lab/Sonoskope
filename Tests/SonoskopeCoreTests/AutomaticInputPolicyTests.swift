import XCTest

@testable import SonoskopeCore

final class AutomaticInputPolicyTests: XCTestCase {
  let first = InputDevice(id: 1, uid: "mic-one", sampleRate: 48000)
  let second = InputDevice(id: 2, uid: "mic-two", sampleRate: 48000)
  let start = Date(timeIntervalSince1970: 1000)
  func user(
    _ devices: [UInt32]?, running: Bool? = true, pid: Int32 = 20,
    bundle: String = "meeting"
  ) -> InputProcessActivity {
    .init(pid: pid, bundleID: bundle, running: running, devices: devices)
  }
  @discardableResult
  func update(
    _ policy: inout AutomaticInputPolicy, _ processes: [InputProcessActivity]?,
    at seconds: Double = 0, enabled: Bool = true, suspended: Bool = false,
    authorized: Bool = true, defaultInput: UInt32 = 1,
    devices: [InputDevice]? = nil
  ) -> InputDevice? {
    policy.update(
      enabled: enabled, suspended: suspended, authorized: authorized,
      processes: processes, devices: devices ?? [first, second], defaultInput: defaultInput,
      observerPID: 10, observerBundleID: "observer", at: start.addingTimeInterval(seconds))
  }
  func testStartsOnlyForExternalActiveInputAndUsesItsDevice() {
    var policy = AutomaticInputPolicy()
    XCTAssertNil(update(&policy, [user([1], running: false)]))
    XCTAssertEqual(update(&policy, [user([2])]), second)
    XCTAssertEqual(policy.state, .active)
  }
  func testOwnProcessAndOtherObserverInstancesCannotTriggerCapture() {
    var policy = AutomaticInputPolicy()
    XCTAssertNil(update(&policy, [user([1], pid: 10), user([1], pid: 30, bundle: "observer")]))
    XCTAssertEqual(policy.state, .waiting)
  }
  func testSelfCaptureCannotKeepMonitoringAliveAfterExternalAppStops() {
    var policy = AutomaticInputPolicy()
    update(&policy, [user([1])])
    let own = user([1], pid: 10)
    XCTAssertEqual(update(&policy, [own], at: 1), first)
    XCTAssertEqual(policy.state, .stopping)
    XCTAssertNil(update(&policy, [own], at: 3))
    XCTAssertEqual(policy.state, .waiting)
  }
  func testBriefExternalRestartCancelsStopGrace() {
    var policy = AutomaticInputPolicy()
    update(&policy, [user([1])])
    update(&policy, [], at: 1)
    XCTAssertEqual(update(&policy, [user([1])], at: 2), first)
    XCTAssertEqual(policy.state, .active)
    XCTAssertEqual(update(&policy, [], at: 3), first)
    XCTAssertNil(update(&policy, [], at: 5))
  }
  func testDisabledPausedDemoOrMissingPermissionStopsImmediately() {
    for condition in 0..<3 {
      var policy = AutomaticInputPolicy()
      update(&policy, [user([1])])
      XCTAssertNil(
        update(
          &policy, [user([1])], enabled: condition != 0,
          suspended: condition == 1, authorized: condition != 2))
    }
  }
  func testResumeNeedsFreshExternalEvidence() {
    var policy = AutomaticInputPolicy()
    update(&policy, [user([1])])
    policy.suspend()
    XCTAssertNil(policy.target)
    XCTAssertNil(update(&policy, []))
    XCTAssertEqual(update(&policy, [user([2])]), second)
  }
  func testUnknownReadsStopAndDoNotFallBackToDefaultDevice() {
    let cases: [[InputProcessActivity]?] = [
      nil, [user(nil)], [user([])],
      [user([1], running: nil)], [user([99])],
    ]
    for processes in cases {
      var policy = AutomaticInputPolicy()
      update(&policy, [user([1])])
      XCTAssertNil(update(&policy, processes, at: 1))
      XCTAssertEqual(policy.state, .unknown)
    }
  }
  func testMultipleDevicesPreferCurrentThenActiveDefaultOtherwiseWait() {
    var policy = AutomaticInputPolicy()
    let both = [user([1]), user([2])]
    XCTAssertNil(update(&policy, both, defaultInput: 99))
    XCTAssertEqual(policy.state, .ambiguous)
    XCTAssertEqual(update(&policy, both, defaultInput: 2), second)
    XCTAssertEqual(update(&policy, both, defaultInput: 1), second)
    XCTAssertEqual(update(&policy, [user([1])]), first)
  }
  func testUnplugHasNoGraceAndFormatChangeIsVisible() {
    var policy = AutomaticInputPolicy()
    update(&policy, [user([1])])
    XCTAssertNil(update(&policy, [], devices: [second]))
    let changed = InputDevice(id: 1, uid: "mic-one", sampleRate: 16000)
    XCTAssertEqual(update(&policy, [user([1])], devices: [changed]), changed)
    XCTAssertNotEqual(policy.target, first)
  }
  func testKnownActiveDeviceStillWorksAlongsideUnknownUnrelatedProcess() {
    var policy = AutomaticInputPolicy()
    XCTAssertEqual(update(&policy, [user([2]), user(nil, running: nil)]), second)
  }
}
