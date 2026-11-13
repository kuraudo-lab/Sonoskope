import AppKit
import SonoskopeCore

// Isolated lifecycle fixture: no collectors, production preferences, or persisted incidents.
@main enum FloatingPreferenceCheck {
  @MainActor static func main() {
    let mode = CommandLine.arguments[1]
    let defaults = UserDefaults(suiteName: CommandLine.arguments[2])!
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let model = MonitorModel(persist: false, runsCollectors: false, settings: defaults)
    if mode == "read" {
      print("floatingMonitor=\(model.floatingMonitorEnabled)")
      return
    }
    let delegate = PreferenceCheckDelegate(model: model)
    app.delegate = delegate
    model.setFloatingMonitorEnabled(mode != "disable")
    model.outputEnabled = true
    model.outputMeasurement = .init(date: Date(), rmsDB: -20, peakDB: -10,
      clippingFraction: 0, sampleCount: 12000, duration: 0.25,
      suspectGap: false, discontinuity: false)
    delegate.panel.refresh()
    if mode == "close" { delegate.panel.closePanel() }
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(200))
      app.terminate(nil)
    }
    withExtendedLifetime(delegate) { app.run() }
  }
}
@MainActor final class PreferenceCheckDelegate: NSObject, NSApplicationDelegate {
  let model: MonitorModel
  let panel: FloatingMonitorController
  init(model: MonitorModel) { self.model = model; panel = FloatingMonitorController(model: model) }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
  func applicationWillTerminate(_ notification: Notification) { panel.stop(); model.shutdown() }
}
