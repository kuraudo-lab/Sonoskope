import AppKit
import SonoskopeCore
import SwiftUI

// A separate presentation executable. Reuses shipping views with isolated fixtures;
// never starts collectors, changes live preferences, or writes live incident history.
@MainActor @Observable final class DemoPresentation {
  let model = MonitorModel(persist: false, runsCollectors: false)
  var scene = 0
  let titles = ["When a call\nbreaks up.", "Put the clues\non a timeline.", "See the device\nevidence.", "Know what is\nstill unknown."]
  let captions = [
    "Review local evidence and a suggested next step, right from your Mac.",
    "Compare audio levels with connection probes. Timing is a clue, not proof of a cause.",
    "A missing audio device is observable. Why it disconnected may still be uncertain.",
    "Unavailable capture is shown explicitly. Missing data never means healthy audio."
  ]
  func select(_ index: Int) {
    scene = index
    model.runDemo(index < 2 ? .correlated : index == 2 ? .bluetooth : .unavailable)
  }
}

struct DemoPresentationView: View {
  @Bindable var presentation: DemoPresentation
  var body: some View {
    HStack(spacing: 36) {
      VStack(alignment: .leading, spacing: 24) {
        HStack(spacing: 12) {
          Image(nsImage: BrandAssets.applicationIcon).resizable().frame(width: 48, height: 48)
          Text("Sonoskope").font(.system(size: 25, weight: .semibold))
        }
        Spacer()
        Text(presentation.titles[presentation.scene])
          .font(.system(size: 44, weight: .bold, design: .rounded)).lineSpacing(2)
        Text(presentation.captions[presentation.scene])
          .font(.system(size: 20)).foregroundStyle(.secondary).lineSpacing(5)
        HStack(spacing: 8) {
          ForEach(0..<4) { i in
            Capsule().fill(i == presentation.scene ? Color.accentColor : Color.gray.opacity(0.25))
              .frame(width: i == presentation.scene ? 34 : 12, height: 5)
          }
        }.padding(.top, 12)
        Spacer()
        Text("SIMULATED DATA · ACTUAL APP VIEWS")
          .font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
        Text("macOS 14.2+  ·  No raw audio saved")
          .font(.system(size: 14)).foregroundStyle(.secondary)
        Text("github.com/kuraudo-lab/Sonoskope")
          .font(.system(size: 13)).foregroundStyle(.secondary)
      }.frame(width: 410).padding(.vertical, 24)
      Group {
        if presentation.scene == 1 {
          VStack(alignment: .leading, spacing: 20) {
            Text("Sound levels & network probes").font(.title2.bold())
            Text("Simulated audio gaps and connection delays")
              .font(.callout).foregroundStyle(.secondary)
            TelemetryCharts(
              audio: presentation.model.audioChartPoints,
              network: presentation.model.networkChartPoints,
              endingAt: presentation.model.chartEnd,
              incidentAt: presentation.model.selectedIncident?.started,
              audioEnabled: true, networkEnabled: true)
            Text("Connection probes are not meeting latency or packet loss.")
              .font(.callout).foregroundStyle(.secondary)
          }.padding(24).frame(width: 520, height: 740)
            .background(Color(nsColor: .windowBackgroundColor))
        } else {
          StatusView(model: presentation.model, openSettings: {})
            .frame(width: 520, height: 740).allowsHitTesting(false)
        }
      }.clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.gray.opacity(0.2)))
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
    }.padding(32).frame(width: 1030, height: 804)
      .background(Color(nsColor: .underPageBackgroundColor))
      .environment(\.locale, L10n.locale)
  }
}

@main enum DemoPresentationMain {
  @MainActor static func main() throws {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.appearance = NSAppearance(named: .aqua)
    let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let presentation = DemoPresentation()
    presentation.select(0)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1030, height: 804),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "Sonoskope Demo · Simulated data"
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: DemoPresentationView(presentation: presentation))
    window.center()
    window.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)
    try String(window.windowNumber).write(to: destination.appendingPathComponent("window-id"), atomically: true, encoding: .utf8)
    var began: Date?
    let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
      MainActor.assumeIsolated {
        guard FileManager.default.fileExists(atPath: destination.appendingPathComponent("recording-started").path) else { return }
        if began == nil { began = Date().addingTimeInterval(1) }
        let elapsed = Date().timeIntervalSince(began!)
        let scene = min(3, max(0, Int(elapsed / 8)))
        if scene != presentation.scene { presentation.select(scene) }
        if elapsed > 34 { app.terminate(nil) }
      }
    }
    withExtendedLifetime((presentation, window, timer)) { app.run() }
    presentation.model.shutdown()
  }
}
