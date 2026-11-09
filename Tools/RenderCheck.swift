import AppKit
import SonoskopeCore
import SwiftUI

// Renders this app's own views offscreen. No desktop capture, UI automation,
// audio capture, network probes, or production preferences are involved.
@main enum RenderCheck {
  @MainActor static func main() throws {
    _ = NSApplication.shared
    let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    let model = MonitorModel(persist: false)
    for scenario in DemoScenario.allCases {
      model.runDemo(scenario)
      try render(
        StatusView(model: model, openSettings: {}),
        to: destination.appendingPathComponent(scenario.rawValue + ".png"),
        size: NSSize(width: 520, height: 740))
    }
    model.runDemo(.correlated)
    try render(
      TelemetryCharts(
        audio: model.audioChartPoints, network: model.networkChartPoints,
        endingAt: model.chartEnd, incidentAt: model.selectedIncident?.started,
        audioEnabled: true, networkEnabled: true
      ).padding(20).background(Color(nsColor: .windowBackgroundColor)),
      to: destination.appendingPathComponent("charts.png"),
      size: NSSize(width: 520, height: 440))
    try render(
      SettingsView(model: model), to: destination.appendingPathComponent("settings.png"),
      size: NSSize(width: 540, height: 760))
    model.shutdown()
    print("Rendered 7 isolated scenarios, charts and settings with the actual SwiftUI views.")
  }
  @MainActor private static func render<V: View>(_ view: V, to url: URL, size: NSSize) throws {
    let host = NSHostingView(rootView: view.environment(\.locale, L10n.locale))
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered,
      defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    host.setFrameSize(size)
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
      throw RenderError.failed
    }
    host.cacheDisplay(in: host.bounds, to: bitmap)
    guard let data = bitmap.representation(using: .png, properties: [:]), data.count > 1000 else {
      throw RenderError.failed
    }
    try data.write(to: url)
    print(url.lastPathComponent, bitmap.pixelsWide, bitmap.pixelsHigh, data.count)
    window.close()
  }
  enum RenderError: Error { case failed }
}
