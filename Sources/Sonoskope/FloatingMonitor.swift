import AppKit
import SonoskopeCore
import SwiftUI

/// Presentation only: never starts collectors or interprets missing data as silence.
struct FloatingVisibilityPolicy {
  private var lastActivity: Date?
  mutating func update(enabled: Bool, suspended: Bool, samples: [AudioMeasurement], at now: Date) -> Bool {
    guard enabled, !suspended else { lastActivity = nil; return false }
    let fresh = samples.filter {
      let age = now.timeIntervalSince($0.date)
      return age >= 0 && age <= 3 && !$0.discontinuity && $0.sampleCount > 0
        && $0.rmsDB.isFinite && $0.peakDB.isFinite
    }
    guard !fresh.isEmpty else { lastActivity = nil; return false }
    if let active = fresh.filter({ $0.rmsDB > -100 || $0.peakDB > -100 }).map(\.date).max() {
      lastActivity = active
    }
    guard let lastActivity else { return false }
    return now.timeIntervalSince(lastActivity) < 300
  }
}

/// Close hides a retained window; it never terminates the application or its collectors.
@MainActor final class ResidentWindowDelegate: NSObject, NSWindowDelegate {
  var onClose: (() -> Void)?
  var onMove: (() -> Void)?
  func windowWillMove(_ notification: Notification) { onMove?() }
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    onClose?()
    sender.orderOut(nil)
    return false
  }
}

@MainActor final class FloatingMonitorController {
  private let model: MonitorModel
  private(set) var panel: NSPanel?
  private let closeDelegate = ResidentWindowDelegate()
  private var timer: Timer?
  private var policy = FloatingVisibilityPolicy()
  private let geometry = ActiveWindowGeometry()
  private var positioning: Task<Void, Never>?
  private var frontBounds: CGRect?

  init(model: MonitorModel) {
    self.model = model
    closeDelegate.onClose = { [weak self] in self?.closePanel() }
    closeDelegate.onMove = { [weak self] in self?.positioning?.cancel() }
  }
  func start() {
    guard timer == nil else { return }
    let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.refresh() }
    }
    self.timer = timer
    RunLoop.main.add(timer, forMode: .common)
    refresh()
  }
  func stop() {
    positioning?.cancel()
    positioning = nil
    timer?.invalidate()
    timer = nil
    panel?.orderOut(nil)
  }
  func refresh(at now: Date = Date()) {
    let samples = [model.outputEnabled ? model.outputMeasurement : nil,
      model.microphoneRunning ? model.inputMeasurement : nil].compactMap { $0 }
    let visible = policy.update(enabled: model.floatingMonitorEnabled && !model.floatingMonitorDismissed,
      suspended: model.monitoringSuspended, samples: samples, at: now)
    guard visible else { panel?.orderOut(nil); return }
    if panel == nil {
      let window = NSPanel(contentRect: .init(x: 0, y: 0, width: 420, height: 350),
        styleMask: [.borderless, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
      window.title = L10n.tr("Sonoskope · 监控浮窗")
      window.isFloatingPanel = false
      window.level = model.floatingMonitorAlwaysOnTop ? .floating : .normal
      window.isMovable = true
      window.isMovableByWindowBackground = true
      window.hidesOnDeactivate = false
      window.isReleasedWhenClosed = false
      window.isOpaque = false
      window.backgroundColor = .clear
      window.hasShadow = true
      window.collectionBehavior = [.managed, .fullScreenNone]
      window.delegate = closeDelegate

      panel = window
      positionPanelInitially()
    }
    let requestedLevel: NSWindow.Level = model.floatingMonitorAlwaysOnTop ? .floating : .normal
    if panel?.level != requestedLevel { panel?.level = requestedLevel }
    // Snapshot at 1 Hz: hidden windows do not rebuild charts on every audio callback.
    let view = FloatingMonitorView(audio: model.audioChartPoints, network: model.networkChartPoints,
      endingAt: model.chartEnd, audioEnabled: model.outputEnabled || model.microphoneRunning,
      networkEnabled: model.networkEnabled, opacity: model.floatingMonitorOpacity,
      close: { [weak self] in self?.closePanel() },
      pause: { [weak self] in self?.pauseMonitoring() })

    if let hosting = panel?.contentView as? NSHostingView<FloatingMonitorView> {
      hosting.rootView = view
    } else {
      panel?.contentView = NSHostingView(rootView: view)
    }
    if panel?.isVisible != true { panel?.orderFrontRegardless() }
  }
  func closePanel() {
    model.dismissFloatingMonitor()
    panel?.orderOut(nil)
  }
  func pauseMonitoring() {
    if !model.paused { model.togglePause() }
    panel?.orderOut(nil)
  }
  private func placePanel() {
    let screens = NSScreen.screens
    let window = frontBounds.map { FloatingPlacement.appKitRect($0, primaryTop: screens.first?.frame.maxY ?? 0) }
    if let index = FloatingPlacement.screenIndex(window: window, screens: screens.map(\.frame),
      pointer: NSEvent.mouseLocation) {
      panel?.setFrameOrigin(FloatingPlacement.origin(in: screens[index].visibleFrame))
    }
  }
  private func positionPanelInitially() {
    let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? getpid()
    placePanel()
    let initialOrigin = panel?.frame.origin
    // One initial placement only. Refreshes, focus changes and re-showing a
    // retained panel must not undo dragging or move it to another desktop.
    positioning = Task { [weak self, geometry] in
      let bounds = await geometry.bounds(pid: pid)
      guard let self else { return }
      self.positioning = nil
      guard !Task.isCancelled, self.panel?.isVisible == true,
        self.panel?.isOnActiveSpace == true, self.panel?.frame.origin == initialOrigin,
        NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
      self.frontBounds = bounds
      self.placePanel()
    }
  }

}

struct FloatingMonitorView: View {
  let audio: [TelemetryPoint]
  let network: [TelemetryPoint]
  let endingAt: Date
  let audioEnabled: Bool
  let networkEnabled: Bool
  var opacity: Double = 0.9
  var close: () -> Void = {}
  var pause: () -> Void = {}
  var body: some View {
    VStack(spacing: 6) {
      HStack {
        Text(L10n.tr("监控浮窗")).font(.caption.weight(.semibold))
          .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
          .overlay(FloatingPanelDragRegion())
          .help(L10n.tr("拖动以移动浮窗"))
        Button(action: pause) { Image(systemName: "pause.fill").frame(width: 26, height: 24) }
          .help(L10n.tr("暂停全部监测"))
          .accessibilityLabel(L10n.tr("暂停全部监测"))
        Button(action: close) { Image(systemName: "xmark").frame(width: 26, height: 24) }
          .help(L10n.tr("关闭浮窗"))
          .accessibilityLabel(L10n.tr("关闭浮窗"))
      }.buttonStyle(.borderless)
      ScrollView {
        TelemetryCharts(audio: audio, network: network, endingAt: endingAt, incidentAt: nil,
          audioEnabled: audioEnabled, networkEnabled: networkEnabled,
          audioHeight: 80, networkHeight: 60)
      }
    }.padding(12).frame(width: 420, height: 350)
      .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .windowBackgroundColor).opacity(opacity)))
      .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.12)))
      .environment(\.locale, L10n.locale)
  }
}

/// A native drag surface on the header only; charts and buttons keep their input.
struct FloatingPanelDragRegion: NSViewRepresentable {
  func makeNSView(context: Context) -> FloatingPanelDragView { FloatingPanelDragView() }
  func updateNSView(_ nsView: FloatingPanelDragView, context: Context) {}
}
final class FloatingPanelDragView: NSView {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override var mouseDownCanMoveWindow: Bool { true }
  override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
  override func resetCursorRects() {
    addCursorRect(bounds, cursor: .openHand)
  }
}
