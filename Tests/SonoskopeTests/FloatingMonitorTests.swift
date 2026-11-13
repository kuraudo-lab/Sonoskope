import AppKit
import SonoskopeCore
import XCTest
@testable import Sonoskope

final class FloatingMonitorTests: XCTestCase {
  private let origin = Date(timeIntervalSince1970: 1800000000)
  private func sample(_ seconds: Double, db: Double = -20, discontinuity: Bool = false) -> AudioMeasurement {
    .init(date: origin.addingTimeInterval(seconds), rmsDB: db, peakDB: db,
      clippingFraction: 0, sampleCount: 12000, duration: 0.25,
      suspectGap: false, discontinuity: discontinuity)
  }
  func testOptInActivityAndFiveMinuteSilence() {
    var policy = FloatingVisibilityPolicy()
    func update(_ seconds: Double, db: Double = -120, enabled: Bool = true) -> Bool {
      policy.update(enabled: enabled, suspended: false,
        samples: [sample(seconds, db: db)], at: origin.addingTimeInterval(seconds))
    }
    XCTAssertFalse(update(0, db: -20, enabled: false))
    XCTAssertFalse(update(1))
    XCTAssertTrue(update(2, db: -20))
    XCTAssertTrue(update(301))
    XCTAssertFalse(update(302))
    XCTAssertTrue(update(303, db: -20))
    XCTAssertTrue(update(500, db: -20))
    XCTAssertTrue(update(799))
    XCTAssertFalse(update(800))
  }
  func testMissingInvalidAndSuspendedDataHideAndResetPanel() {
    for mode in 0..<4 {
      var policy = FloatingVisibilityPolicy()
      XCTAssertTrue(policy.update(enabled: true, suspended: false,
        samples: [sample(0)], at: origin))
      let samples = mode == 0 ? [] : [sample(mode == 1 ? 0 : 5, discontinuity: mode == 2)]
      XCTAssertFalse(policy.update(enabled: true, suspended: mode == 3,
        samples: samples, at: origin.addingTimeInterval(5)))
      XCTAssertFalse(policy.update(enabled: true, suspended: false,
        samples: [sample(6, db: -120)], at: origin.addingTimeInterval(6)))
    }
  }
  func testEitherAudioDirectionCanKeepPanelVisible() {
    var policy = FloatingVisibilityPolicy()
    XCTAssertTrue(policy.update(enabled: true, suspended: false,
      samples: [sample(0, db: -120), sample(0)], at: origin))
    XCTAssertTrue(policy.update(enabled: true, suspended: false,
      samples: [sample(300), sample(300, db: -120)], at: origin.addingTimeInterval(300)))
  }
  @MainActor func testPreferenceDefaultsOffPersistsAndDoesNotEnableCollectors() {
    let suite = "Sonoskope.FloatingTests.\(UUID())"
    let settings = UserDefaults(suiteName: suite)!
    defer { settings.removePersistentDomain(forName: suite) }
    let model = MonitorModel(persist: false, runsCollectors: false, settings: settings)
    XCTAssertFalse(model.floatingMonitorEnabled)
    model.setFloatingMonitorEnabled(true)
    XCTAssertFalse(model.outputEnabled)
    XCTAssertFalse(model.automaticInputEnabled)
    XCTAssertFalse(model.microphoneRunning)
    let second = MonitorModel(persist: false, runsCollectors: false, settings: settings)
    XCTAssertTrue(second.floatingMonitorEnabled)
    model.runDemo(.normal)
    model.setFloatingMonitorEnabled(false)
    XCTAssertTrue(settings.bool(forKey: "floatingMonitor"))
    model.exitDemo()
    model.setFloatingMonitorEnabled(false)
    XCTAssertFalse(settings.bool(forKey: "floatingMonitor"))
    model.shutdown()
    second.shutdown()
  }
  @MainActor func testCloseHidesWindowAndKeepsAppResident() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 200, height: 100),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.delegate = delegate
    window.orderFront(nil)
    window.performClose(nil)
    XCTAssertFalse(window.isVisible)
    XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(app))
    window.orderFront(nil)
    XCTAssertTrue(window.isVisible, "The same retained window can reopen")
    window.orderOut(nil)
  }
  @MainActor func testControllerShowsWithoutActivationAndCloseOnlyDismissesIt() {
    _ = NSApplication.shared
    let model = MonitorModel(persist: false, runsCollectors: false)
    let controller = FloatingMonitorController(model: model)
    model.outputEnabled = true
    model.outputMeasurement = sample(0)
    controller.refresh(at: origin)
    XCTAssertNil(controller.panel)
    model.setFloatingMonitorEnabled(true)
    let keyWindow = NSApp.keyWindow
    controller.refresh(at: origin)
    XCTAssertEqual(controller.panel?.isVisible, true)
    XCTAssertEqual(controller.panel?.styleMask.contains(.titled), false)
    XCTAssertEqual(controller.panel?.isOpaque, false)
    XCTAssertEqual(controller.panel?.frame.size, FloatingPlacement.size)
    XCTAssertTrue(NSApp.keyWindow === keyWindow, "Automatic presentation must not steal focus")
    controller.closePanel()
    XCTAssertTrue(model.floatingMonitorEnabled)
    XCTAssertTrue(model.floatingMonitorDismissed)
    XCTAssertEqual(controller.panel?.isVisible, false)
    XCTAssertFalse(model.paused)
    controller.refresh(at: origin)
    XCTAssertEqual(controller.panel?.isVisible, false)
    model.setFloatingMonitorEnabled(true)
    XCTAssertFalse(model.floatingMonitorDismissed)
    controller.refresh(at: origin)
    XCTAssertEqual(controller.panel?.isVisible, true)
    model.togglePause()
    controller.refresh(at: origin)
    XCTAssertEqual(controller.panel?.isVisible, false)
    controller.stop()
    model.shutdown()
  }
  @MainActor func testPanelCloseDismissesWithoutChangingPreferenceOrMonitoring() {
    _ = NSApplication.shared
    let model = MonitorModel(persist: false, runsCollectors: false)
    model.setFloatingMonitorEnabled(true)
    let delegate = ResidentWindowDelegate()
    delegate.onClose = { model.dismissFloatingMonitor() }
    let panel = NSPanel(contentRect: .zero, styleMask: [.titled, .closable, .nonactivatingPanel],
      backing: .buffered, defer: false)
    panel.isReleasedWhenClosed = false
    XCTAssertFalse(delegate.windowShouldClose(panel))
    XCTAssertTrue(model.floatingMonitorEnabled)
    XCTAssertTrue(model.floatingMonitorDismissed)
    XCTAssertFalse(model.paused)
    model.shutdown()
  }
}

extension FloatingMonitorTests {
  func testTopRightPlacementAndScreenCoordinateConversion() {
    let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let left = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
    let above = CGRect(x: 0, y: 900, width: 1440, height: 900)
    XCTAssertEqual(FloatingPlacement.origin(in: CGRect(x: 0, y: 50, width: 1440, height: 825)),
      CGPoint(x: 1002, y: 507))
    XCTAssertEqual(FloatingPlacement.origin(in: left), CGPoint(x: -438, y: 712))
    let window = FloatingPlacement.appKitRect(CGRect(x: 100, y: -850, width: 900, height: 700), primaryTop: 900)
    XCTAssertEqual(window.minY, 1050)
    XCTAssertEqual(FloatingPlacement.screenIndex(window: window, screens: [primary, left, above], pointer: .zero), 2)
    XCTAssertEqual(FloatingPlacement.screenIndex(window: nil, screens: [primary, left], pointer: CGPoint(x: -500, y: 400)), 1)
    XCTAssertEqual(FloatingPlacement.screenIndex(window: CGRect(x: -300, y: 100, width: 1000, height: 600), screens: [primary, left], pointer: .zero), 0)
    XCTAssertEqual(FloatingPlacement.origin(in: CGRect(x: 10, y: 20, width: 300, height: 200)), CGPoint(x: 10, y: 20))
    XCTAssertNil(FloatingPlacement.screenIndex(window: nil, screens: [], pointer: .zero))
  }
  @MainActor func testOpacityPersistsAndPanelActionsHaveDistinctEffects() {
    let suite = "Sonoskope.PanelStyleTests.\(UUID())"
    let settings = UserDefaults(suiteName: suite)!
    defer { settings.removePersistentDomain(forName: suite) }
    let model = MonitorModel(persist: false, runsCollectors: false, settings: settings)
    XCTAssertEqual(model.floatingMonitorOpacity, 0.9)
    model.setFloatingMonitorOpacity(0.55)
    let restored = MonitorModel(persist: false, runsCollectors: false, settings: settings)
    XCTAssertEqual(restored.floatingMonitorOpacity, 0.55)
    model.setFloatingMonitorOpacity(.nan)
    XCTAssertEqual(model.floatingMonitorOpacity, 0.55)
    model.setFloatingMonitorOpacity(0)
    XCTAssertEqual(model.floatingMonitorOpacity, 0.4)
    model.setFloatingMonitorOpacity(2)
    XCTAssertEqual(model.floatingMonitorOpacity, 1)
    let controller = FloatingMonitorController(model: model)
    model.setFloatingMonitorEnabled(true)
    controller.closePanel()
    XCTAssertTrue(model.floatingMonitorEnabled)
    XCTAssertTrue(model.floatingMonitorDismissed)
    XCTAssertFalse(model.paused)
    model.setFloatingMonitorEnabled(true)
    controller.pauseMonitoring()
    XCTAssertTrue(model.paused)
    XCTAssertTrue(model.floatingMonitorEnabled)
    controller.pauseMonitoring()
    XCTAssertTrue(model.paused, "Repeated pause must not resume capture")
    controller.stop()
    model.shutdown()
    restored.shutdown()
  }
}

extension FloatingMonitorTests {
  @MainActor func testClosingPanelMustNotEraseSavedOptInOnRelaunch() {
    let suite = "Sonoskope.FloatingRelaunch.\(UUID())"
    let settings = UserDefaults(suiteName: suite)!
    defer { settings.removePersistentDomain(forName: suite) }
    let first = MonitorModel(persist: false, runsCollectors: false, settings: settings)
    first.setFloatingMonitorEnabled(true)
    let controller = FloatingMonitorController(model: first)
    controller.closePanel()
    first.shutdown()
    let second = MonitorModel(persist: false, runsCollectors: false,
      settings: UserDefaults(suiteName: suite)!)
    XCTAssertTrue(settings.bool(forKey: "floatingMonitor"))
    XCTAssertTrue(second.floatingMonitorEnabled)
    XCTAssertFalse(second.floatingMonitorDismissed)
    controller.stop()
    second.shutdown()
  }
}
