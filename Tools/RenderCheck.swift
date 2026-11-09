import AppKit
import SonoskopeCore
import SwiftUI

// Renders this app's own views offscreen. No desktop capture, UI automation,
// audio capture, network probes, or production preferences are involved.
@main enum RenderCheck {
  @MainActor static func main() async throws {
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
    var fixture = HardwareSnapshot()
    fixture.defaultOutput = 200
    fixture.defaultInput = 100
    fixture.devices = [
      .init(
        id: 100, uid: "render-mic", name: "MacBook Air Microphone", transport: L10n.tr("内置"),
        isBluetooth: false, inputChannels: 1, outputChannels: 0, sampleRate: 48000,
        bufferFrames: 1024, running: false),
      .init(
        id: 200, uid: "render-speaker", name: "MacBook Air Speakers", transport: L10n.tr("内置"),
        isBluetooth: false, inputChannels: 0, outputChannels: 2, sampleRate: 48000,
        bufferFrames: 1024, running: false),
    ]
    fixture.inputProcesses = []
    let automatic = MonitorModel(
      persist: false, microphone: RenderInputCapture(),
      microphoneAuthorized: { true }, requestMicrophoneAuthorization: { true },
      readInputHardware: { fixture }, runsCollectors: false)
    automatic.setAutomaticInputEnabled(true)
    for _ in 0..<12 { await Task.yield() }
    try render(
      StatusView(model: automatic, openSettings: {}),
      to: destination.appendingPathComponent("automatic-waiting.png"),
      size: NSSize(width: 520, height: 740))
    fixture.inputProcesses = [
      .init(pid: 1_234_567, bundleID: "com.apple.VoiceMemos", running: true, devices: [100]),
      .init(pid: 1_234_568, bundleID: "com.microsoft.teams2", running: true, devices: [100]),
    ]
    fixture.processes = [
      .init(
        id: 300, pid: 1_234_567, bundleID: "com.apple.VoiceMemos", name: "Voice Memos",
        inputActive: true, outputActive: false, outputDevices: [], inputDevices: [100]),
      .init(
        id: 301, pid: 1_234_568, bundleID: "com.microsoft.teams2", name: "Microsoft Teams",
        inputActive: true, outputActive: true, outputDevices: [200], inputDevices: [100]),
    ]
    fixture.timestamp = Date()
    automatic.acceptHardwareSnapshot(fixture)
    for _ in 0..<12 { await Task.yield() }
    automatic.audioHistory = TelemetryHistory()
    for i in 0..<120 {
      automatic.audioHistory.append(
        value: -28 + 8 * sin(Double(i) * 0.3), source: "input",
        date: automatic.clock.addingTimeInterval(Double(i) * 0.5 - 60), maximumGap: 2,
        context: i < 60 ? "Voice Memos" : "Microsoft Teams · Voice Memos")
    }
    try render(
      StatusView(model: automatic, openSettings: {}),
      to: destination.appendingPathComponent("automatic-active.png"),
      size: NSSize(width: 520, height: 900))
    try render(
      TelemetryCharts(
        audio: automatic.audioChartPoints, network: [], endingAt: automatic.chartEnd,
        incidentAt: nil, audioEnabled: true, networkEnabled: false
      )
      .padding(20).background(Color(nsColor: .windowBackgroundColor)),
      to: destination.appendingPathComponent("automatic-apps-chart.png"),
      size: NSSize(width: 520, height: 440))
    try render(
      SettingsView(model: automatic),
      to: destination.appendingPathComponent("automatic-settings.png"),
      size: NSSize(width: 540, height: 760))
    let denied = MonitorModel(
      persist: false, microphone: RenderInputCapture(), microphoneAuthorized: { false },
      requestMicrophoneAuthorization: { false }, readInputHardware: { fixture },
      runsCollectors: false)
    denied.setAutomaticInputEnabled(true)
    for _ in 0..<12 { await Task.yield() }
    try render(
      StatusView(model: denied, openSettings: {}),
      to: destination.appendingPathComponent("microphone-permission.png"),
      size: NSSize(width: 520, height: 740))
    denied.shutdown()
    automatic.shutdown()
    model.shutdown()
    print(
      "Rendered isolated scenarios, automatic input fixtures, charts and settings with the actual SwiftUI views."
    )
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

@MainActor private final class RenderInputCapture: MicrophoneCapturing {
  func start(
    deviceID: UInt32, duration: TimeInterval?, requestPermission: Bool,
    onMeasurement: @escaping @MainActor (AudioMeasurement) -> Void,
    onEnd: @escaping @MainActor (MicrophoneCaptureEnd) -> Void
  ) async {
    onMeasurement(
      .init(
        date: Date(), rmsDB: -24, peakDB: -12, clippingFraction: 0,
        sampleCount: 1024, duration: 0.02, suspectGap: false, discontinuity: false))
  }
  func stop() {}
}
