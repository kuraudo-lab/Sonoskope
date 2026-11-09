import SonoskopeCore
import XCTest

@testable import Sonoskope

@MainActor private final class FakeMicrophone: MicrophoneCapturing {
  struct Call {
    let device: UInt32
    let duration: TimeInterval?
    let sample: @MainActor (AudioMeasurement) -> Void
    let end: @MainActor (MicrophoneCaptureEnd) -> Void
  }
  var calls: [Call] = []
  var stops = 0
  func start(
    deviceID: UInt32, duration: TimeInterval?, requestPermission: Bool,
    onMeasurement: @escaping @MainActor (AudioMeasurement) -> Void,
    onEnd: @escaping @MainActor (MicrophoneCaptureEnd) -> Void
  ) async {
    calls.append(.init(device: deviceID, duration: duration, sample: onMeasurement, end: onEnd))
  }
  func stop() { stops += 1 }
}

final class AutomaticInputLifecycleTests: XCTestCase {
  @MainActor private func snapshot(active: Bool = true, at seconds: Double = 0, id: UInt32 = 1)
    -> HardwareSnapshot
  {
    var value = HardwareSnapshot()
    value.timestamp = Date().addingTimeInterval(seconds)
    value.defaultInput = id
    value.devices = [
      .init(
        id: id, uid: "test-\(id)", name: "Test microphone", transport: "Built-in",
        isBluetooth: false, inputChannels: 1, outputChannels: 0, sampleRate: 48000,
        bufferFrames: 1024, running: active)
    ]
    value.inputProcesses = [
      .init(pid: 1_234_567, bundleID: "meeting", running: active, devices: [id])
    ]
    return value
  }
  @MainActor private func settle() async { for _ in 0..<12 { await Task.yield() } }
  @MainActor private func model(_ microphone: FakeMicrophone, active: Bool = true) -> MonitorModel {
    let initial = snapshot(active: active)
    return MonitorModel(
      persist: false, microphone: microphone,
      microphoneAuthorized: { true }, requestMicrophoneAuthorization: { true },
      readInputHardware: { initial }, runsCollectors: false)
  }
  @MainActor private func sample() -> AudioMeasurement {
    .init(
      date: Date(), rmsDB: -24, peakDB: -12, clippingFraction: 0,
      sampleCount: 1024, duration: 0.02, suspectGap: false, discontinuity: false)
  }
  @MainActor func testOptInStartsWithoutTenSecondTimeoutAndDoesNotRestartEveryPoll() async {
    let mic = FakeMicrophone()
    let model = model(mic)
    XCTAssertFalse(model.automaticInputEnabled)
    model.acceptHardwareSnapshot(snapshot())
    await settle()
    XCTAssertTrue(mic.calls.isEmpty)
    model.setAutomaticInputEnabled(true)
    await settle()
    XCTAssertEqual(mic.calls.count, 1)
    XCTAssertNil(mic.calls[0].duration)
    model.acceptHardwareSnapshot(snapshot())
    await settle()
    XCTAssertEqual(mic.calls.count, 1)
    model.shutdown()
  }
  @MainActor func testIdleOptInDoesNotOpenMicrophoneAndActivityStartsIt() async {
    let mic = FakeMicrophone()
    let model = model(mic, active: false)
    model.setAutomaticInputEnabled(true)
    await settle()
    XCTAssertTrue(mic.calls.isEmpty)
    model.acceptHardwareSnapshot(snapshot())
    await settle()
    XCTAssertEqual(mic.calls.count, 1)
    model.shutdown()
  }
  @MainActor func testExternalStopClosesCaptureAndRejectsLateSamples() async {
    let mic = FakeMicrophone()
    let model = model(mic)
    model.setAutomaticInputEnabled(true)
    await settle()
    let callback = mic.calls[0].sample
    callback(sample())
    XCTAssertNotNil(model.inputMeasurement)
    model.acceptHardwareSnapshot(snapshot(active: false, at: 1))
    model.acceptHardwareSnapshot(snapshot(active: false, at: 4))
    XCTAssertFalse(model.microphoneRunning)
    let count = model.audioHistory.points.count
    callback(sample())
    XCTAssertNil(model.inputMeasurement)
    XCTAssertEqual(model.audioHistory.points.count, count)
    model.shutdown()
  }
  @MainActor func testPauseAndResumeRequireFreshExternalActivity() async {
    let mic = FakeMicrophone()
    let model = model(mic)
    model.setAutomaticInputEnabled(true)
    await settle()
    model.togglePause()
    XCTAssertTrue(model.automaticInputEnabled)
    XCTAssertFalse(model.microphoneRunning)
    model.acceptHardwareSnapshot(snapshot())
    await settle()
    XCTAssertEqual(mic.calls.count, 1)
    model.togglePause()
    model.acceptHardwareSnapshot(snapshot(active: false))
    await settle()
    XCTAssertEqual(mic.calls.count, 1)
    model.acceptHardwareSnapshot(snapshot())
    await settle()
    XCTAssertEqual(mic.calls.count, 2)
    model.shutdown()
  }
  @MainActor func testDemoStopsCaptureAndNeverOpensMicrophone() async {
    let mic = FakeMicrophone()
    let model = model(mic)
    model.setAutomaticInputEnabled(true)
    await settle()
    model.runDemo(.normal)
    XCTAssertFalse(model.microphoneRunning)
    model.acceptHardwareSnapshot(snapshot())
    await settle()
    XCTAssertEqual(mic.calls.count, 1)
    model.exitDemo()
    model.acceptHardwareSnapshot(snapshot(active: false))
    await settle()
    XCTAssertFalse(model.microphoneRunning)
    model.shutdown()
  }
  @MainActor func testDisableWhileAuthorizationPendingCannotStartCapture() async {
    let mic = FakeMicrophone()
    let hardware = snapshot()
    var continuation: CheckedContinuation<Bool, Never>?
    let model = MonitorModel(
      persist: false, microphone: mic, microphoneAuthorized: { true },
      requestMicrophoneAuthorization: { await withCheckedContinuation { continuation = $0 } },
      readInputHardware: { hardware }, runsCollectors: false)
    model.setAutomaticInputEnabled(true)
    await settle()
    XCTAssertNotNil(continuation)
    model.setAutomaticInputEnabled(false)
    continuation?.resume(returning: true)
    await settle()
    XCTAssertFalse(model.automaticInputEnabled)
    XCTAssertFalse(model.microphoneRunning)
    XCTAssertTrue(mic.calls.isEmpty)
    model.shutdown()
  }
  @MainActor func testDeviceSwitchDropsOldCallbacksAndStartsNewDevice() async {
    let mic = FakeMicrophone()
    let model = model(mic)
    model.setAutomaticInputEnabled(true)
    await settle()
    let old = mic.calls[0]
    model.acceptHardwareSnapshot(snapshot(id: 2))
    await settle()
    XCTAssertEqual(mic.calls.last?.device, 2)
    old.sample(sample())
    old.end(.configurationChanged)
    XCTAssertTrue(model.microphoneRunning)
    XCTAssertNil(model.inputMeasurement)
    mic.calls.last?.sample(sample())
    XCTAssertNotNil(model.inputMeasurement)
    model.shutdown()
  }
  @MainActor func testBuiltInInputCapturesAndKeepsApplicationHistory() async {
    let mic = FakeMicrophone()
    let model = model(mic)
    model.setAutomaticInputEnabled(true)
    await settle()
    XCTAssertFalse(try! XCTUnwrap(model.currentInputDevice).isBluetooth)
    XCTAssertEqual(model.currentInputDevice?.transport, "Built-in")
    mic.calls[0].sample(sample())
    XCTAssertEqual(model.audioHistory.points.last?.context, "meeting")
    var next = snapshot()
    next.inputProcesses = [
      .init(pid: 1_234_568, bundleID: "com.apple.VoiceMemos", running: true, devices: [1])
    ]
    model.acceptHardwareSnapshot(next)
    mic.calls[0].sample(sample())
    XCTAssertEqual(model.audioHistory.points.first?.context, "meeting")
    XCTAssertEqual(model.audioHistory.points.last?.context, "com.apple.VoiceMemos")
    XCTAssertNotEqual(
      model.audioHistory.points.first?.series, model.audioHistory.points.last?.series)
    XCTAssertEqual(mic.calls.count, 1)
    model.shutdown()
  }
  @MainActor func testInputUsersMatchDeviceExcludeSelfAndFallBackToPID() {
    var hardware = snapshot()
    hardware.inputProcesses = [
      .init(pid: 10, bundleID: "lab.kuraudo.Sonoskope", running: true, devices: [1]),
      .init(pid: 11, bundleID: "observer", running: true, devices: [1]),
      .init(pid: 12, bundleID: "meeting", running: true, devices: [2]),
      .init(pid: 13, bundleID: "idle", running: false, devices: [1]),
      .init(pid: 14, bundleID: "app", running: true, devices: [1]),
      .init(pid: 15, bundleID: "app", running: true, devices: [1]),
      .init(pid: 16, bundleID: "", running: true, devices: [1]),
    ]
    hardware.processes = [
      .init(
        id: 100, pid: 14, bundleID: "app", name: "Voice Memos",
        inputActive: true, outputActive: false, outputDevices: [], inputDevices: [1])
    ]
    let names = hardware.inputUsers(of: 1, observerPID: 11)
    XCTAssertEqual(Set(names), Set(["Voice Memos", "app", L10n.tr("进程 \(16)")]))
  }
  @MainActor func testGapsFromDifferentMicrophonesDoNotCombineIntoAnIncident() async {
    let mic = FakeMicrophone()
    let model = model(mic)
    model.setAutomaticInputEnabled(true)
    await settle()
    let now = Date()
    func gap(_ seconds: Double) -> AudioMeasurement {
      .init(
        date: now.addingTimeInterval(seconds), rmsDB: -24, peakDB: -12,
        clippingFraction: 0, sampleCount: 1024, duration: 0.02,
        suspectGap: true, discontinuity: false)
    }
    mic.calls[0].sample(gap(0))
    mic.calls[0].sample(gap(2))
    model.acceptHardwareSnapshot(snapshot(id: 2))
    await settle()
    mic.calls[1].sample(gap(4))
    XCTAssertTrue(model.incidents.isEmpty)
    mic.calls[1].sample(gap(6))
    mic.calls[1].sample(gap(8))
    XCTAssertEqual(model.incidents.count, 1)
    model.shutdown()
  }
  @MainActor func testCaptureFailureRetriesWithBackoffInsteadOfEveryPoll() async {
    let mic = FakeMicrophone()
    let model = model(mic)
    model.setAutomaticInputEnabled(true)
    await settle()
    mic.calls[0].end(.failed("test failure"))
    model.acceptHardwareSnapshot(snapshot(at: 2))
    await settle()
    XCTAssertEqual(mic.calls.count, 1)
    model.acceptHardwareSnapshot(snapshot(at: 12))
    await settle()
    XCTAssertEqual(mic.calls.count, 2)
    model.shutdown()
  }
  @MainActor func testManualTestRemainsBoundedAndCannotOverlapAutomaticCapture() async {
    let mic = FakeMicrophone()
    let model = model(mic)
    model.startMicrophone()
    await settle()
    XCTAssertEqual(mic.calls[0].duration, 10)
    model.setAutomaticInputEnabled(true)
    await settle()
    XCTAssertNil(mic.calls.last?.duration)
    let count = mic.calls.count
    model.startMicrophone()
    await settle()
    XCTAssertEqual(mic.calls.count, count)
    model.stopMicrophone()
    XCTAssertFalse(model.automaticInputEnabled)
    XCTAssertFalse(model.microphoneRunning)
    model.shutdown()
  }
  @MainActor func testMissingPermissionIsVisibleInTheMainStatus() async {
    let mic = FakeMicrophone()
    let hardware = snapshot()
    let model = MonitorModel(
      persist: false, microphone: mic, microphoneAuthorized: { false },
      requestMicrophoneAuthorization: { false }, readInputHardware: { hardware },
      runsCollectors: false)
    model.setAutomaticInputEnabled(true)
    await settle()
    XCTAssertEqual(model.title, L10n.tr("麦克风监测需要授权"))
    XCTAssertTrue(model.automaticInputNeedsPermission)
    XCTAssertTrue(mic.calls.isEmpty)
    model.shutdown()
  }
  @MainActor func testPermissionRevocationStopsCapture() async {
    let mic = FakeMicrophone()
    let hardware = snapshot()
    var allowed = true
    let model = MonitorModel(
      persist: false, microphone: mic, microphoneAuthorized: { allowed },
      requestMicrophoneAuthorization: { allowed }, readInputHardware: { hardware },
      runsCollectors: false)
    model.setAutomaticInputEnabled(true)
    await settle()
    allowed = false
    model.acceptHardwareSnapshot(snapshot())
    XCTAssertFalse(model.microphoneRunning)
    model.shutdown()
  }
  @MainActor func testSleepStopsImmediatelyAndWakeDoesNotReuseOldActivity() async {
    let mic = FakeMicrophone()
    let model = model(mic)
    model.setAutomaticInputEnabled(true)
    await settle()
    model.systemWillSleep()
    model.acceptHardwareSnapshot(snapshot())
    await settle()
    XCTAssertFalse(model.microphoneRunning)
    XCTAssertEqual(mic.calls.count, 1)
    model.systemDidWake()
    model.acceptHardwareSnapshot(snapshot(active: false))
    await settle()
    XCTAssertFalse(model.microphoneRunning)
    model.acceptHardwareSnapshot(snapshot())
    await settle()
    XCTAssertEqual(mic.calls.count, 2)
    model.shutdown()
  }
  @MainActor func testShutdownCancelsPendingAuthorization() async {
    let mic = FakeMicrophone()
    let hardware = snapshot()
    var continuation: CheckedContinuation<Bool, Never>?
    let model = MonitorModel(
      persist: false, microphone: mic, microphoneAuthorized: { true },
      requestMicrophoneAuthorization: { await withCheckedContinuation { continuation = $0 } },
      readInputHardware: { hardware }, runsCollectors: false)
    model.setAutomaticInputEnabled(true)
    await settle()
    model.shutdown()
    continuation?.resume(returning: true)
    await settle()
    XCTAssertFalse(model.microphoneRunning)
    XCTAssertTrue(mic.calls.isEmpty)
  }
  @MainActor func testMissingCallbacksStopCaptureAndRetryAfterBackoff() async {
    let mic = FakeMicrophone()
    let model = model(mic)
    model.setAutomaticInputEnabled(true)
    await settle()
    model.acceptHardwareSnapshot(snapshot(at: 6))
    await settle()
    XCTAssertFalse(model.microphoneRunning)
    model.acceptHardwareSnapshot(snapshot(at: 7))
    await settle()
    XCTAssertEqual(mic.calls.count, 1)
    model.acceptHardwareSnapshot(snapshot(at: 17))
    await settle()
    XCTAssertEqual(mic.calls.count, 2)
    model.shutdown()
  }

}
