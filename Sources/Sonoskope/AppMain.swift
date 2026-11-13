import AppKit
import SonoskopeCore
import SwiftUI

@main enum SonoskopeMain {
  @MainActor static func main() {
    if CommandLine.arguments.contains("--localization-check") {
      // Package verification only: no app windows, collectors, or permissions.
      let payload = [
        "language": L10n.language.rawValue,
        "soundLevel": L10n.tr("声音电平"),
        "resourceBundle": L10n.resourceBundleURL.path,
        "microphonePermission": Bundle.main.localizedInfoDictionary?["NSMicrophoneUsageDescription"]
          as? String ?? "",
      ]
      if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
        let output = String(data: data, encoding: .utf8)
      {
        print(output)
      }
      return
    }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
  }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  private var model: MonitorModel!
  private var floatingMonitor: FloatingMonitorController?
  private let navigation = StatusNavigation()
  private let onboarding = OnboardingProgress()
  private let updater = SoftwareUpdater()
  private var updateWindow: NSWindow?
  private var statusItem: NSStatusItem!
  private var statusWindow: NSWindow?
  private var settingsWindow: NSWindow?
  private var gettingStartedWindow: NSWindow?
  func applicationDidFinishLaunching(_ notification: Notification) {
    let smoke = CommandLine.arguments.contains("--smoke-test")
    // Explicit bounded hardware check; never enabled by the passive smoke test or CI.
    let microphoneCheck = !smoke && CommandLine.arguments.contains("--microphone-check")
    model = MonitorModel(persist: !smoke && !microphoneCheck)
    updater.present = { [weak self] in self?.showUpdates() }
    updater.willInstall = { [weak self] in self?.model.shutdown() }
    model.onDemoChange = { [weak self] active in
      self?.updater.setSuspended(active)
      self?.floatingMonitor?.refresh()
    }
    model.notifications.openIncident = { [weak self] id in
      guard let self else { return }
      if self.model.demoScenario != nil { self.model.exitDemo() }
      self.navigation.showIncident(id)
      self.showStatus()
    }
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    NSApp.applicationIconImage = BrandAssets.applicationIcon
    statusItem.button?.image = BrandAssets.menuBarIcon
    statusItem.button?.toolTip = L10n.tr("Sonoskope · 查看音频状态")
    statusItem.button?.target = self
    statusItem.button?.action = #selector(statusClicked)
    statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    // Resolve demo mode before starting any restored live opt-ins.
    if !smoke && !microphoneCheck,
      let index = CommandLine.arguments.firstIndex(of: "--demo"),
      CommandLine.arguments.count > index + 1,
      let scenario = DemoScenario(rawValue: CommandLine.arguments[index + 1])
    { model.runDemo(scenario) }
    model.start()
    if microphoneCheck { model.startMicrophone() }
    if smoke || microphoneCheck {
      Task {
        try? await Task.sleep(for: .seconds(microphoneCheck ? 12 : 7))
        let payload: [String: Any] = [
          "application": "Sonoskope",
          "appIconBundled": Bundle.main.url(forResource: "AppIcon", withExtension: "icns") != nil,
          "menuBarIconIsTemplate": statusItem.button?.image?.isTemplate ?? true,
          "interfaceLanguage": L10n.language.rawValue,
          "statusTitle": model.title,
          "microphonePermissionDescription": Bundle.main.localizedInfoDictionary?[
            "NSMicrophoneUsageDescription"] ?? "",
          "devices": model.hardware.devices.map {
            ["name": $0.name, "transport": $0.transport, "sampleRate": $0.sampleRate]
              as [String: Any]
          },
          "audioProcessCount": model.hardware.processes.count,
          "networkPath": model.network.path, "probe": model.network.probe,
          "microphoneRunning": model.microphoneRunning,
          "inputStatus": model.inputReading,
          "inputChartValues": model.audioHistory.points.filter {
            $0.source == "input" && $0.value != nil
          }.count,
          "automaticInputEnabled": model.automaticInputEnabled,
          "inputUsageAvailable": model.hardware.inputProcesses != nil,
          "activeInputProcessCount": model.hardware.inputProcesses?.filter {
            $0.pid != getpid() && $0.running == true
          }.count ?? 0,
          "outputCaptureEnabled": model.outputEnabled,
          "liveIncidentCount": model.incidents.count,
        ]
        if let data = try? JSONSerialization.data(
          withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
          let output = String(data: data, encoding: .utf8)
        {
          print(output)
        }
        NSApp.terminate(nil)
      }
    } else {
      if !CommandLine.arguments.contains("--background") {
        if model.demoScenario == nil && onboarding.shouldPresent {
          showGettingStarted()
        } else {
          showStatus()
        }
      }
      if model.demoScenario == nil { updater.start() }
      floatingMonitor = FloatingMonitorController(model: model)
      model.onFloatingMonitorChange = { [weak self] in self?.floatingMonitor?.refresh() }
      floatingMonitor?.start()
    }
    let appMenu = NSMenu()
    let item = NSMenuItem()
    appMenu.addItem(item)
    let menu = NSMenu()
    menu.addItem(withTitle: L10n.tr("音频状态"), action: #selector(showStatus), keyEquivalent: "1")
    menu.addItem(withTitle: L10n.tr("设置…"), action: #selector(showSettings), keyEquivalent: ",")
    menu.addItem(withTitle: L10n.tr("检查更新…"), action: #selector(showUpdates), keyEquivalent: "")
    menu.addItem(
      withTitle: L10n.tr("使用指南…"), action: #selector(showGettingStarted), keyEquivalent: "")
    menu.addItem(.separator())
    menu.addItem(
      withTitle: L10n.tr("退出 Sonoskope"), action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")
    for entry in menu.items where entry.action != #selector(NSApplication.terminate(_:)) {
      entry.target = self
    }
    item.submenu = menu
    NSApp.mainMenu = appMenu
  }
  @objc private func statusClicked() {
    if NSApp.currentEvent?.type == .rightMouseUp {
      let menu = NSMenu()
      let status = menu.addItem(
        withTitle: L10n.tr("音频状态"), action: #selector(showStatus), keyEquivalent: "")
      status.target = self
      let settings = menu.addItem(
        withTitle: L10n.tr("设置…"), action: #selector(showSettings), keyEquivalent: "")
      settings.target = self
      let update = menu.addItem(withTitle: L10n.tr(updater.isReady ? "更新已准备好" : "检查更新…"), action: #selector(showUpdates), keyEquivalent: "")
      update.target = self
      let guide = menu.addItem(
        withTitle: L10n.tr("使用指南…"), action: #selector(showGettingStarted), keyEquivalent: "")
      guide.target = self
      menu.addItem(.separator())
      menu.addItem(
        withTitle: L10n.tr("退出 Sonoskope"), action: #selector(NSApplication.terminate(_:)),
        keyEquivalent: "q")
      statusItem.menu = menu
      statusItem.button?.performClick(nil)
      statusItem.menu = nil
    } else {
      showStatus()
    }
  }
  @objc func showStatus() {
    if statusWindow == nil {
      statusWindow = window(
        title: L10n.tr("Sonoskope · 音频状态"), size: NSSize(width: 640, height: 620),
        view: StatusView(
          model: model, navigation: navigation, updater: updater,
          openUpdates: { [weak self] in self?.showUpdates() },
          openSettings: { [weak self] in self?.showSettings() }))
    }
    present(statusWindow)
  }
  @objc func showGettingStarted() {
    if gettingStartedWindow == nil {
      gettingStartedWindow = window(
        title: L10n.tr("Sonoskope · 使用指南"), size: NSSize(width: 640, height: 620),
        view: GettingStartedView(
          model: model,
          finish: { [weak self] in
            self?.onboarding.acknowledge()
            self?.gettingStartedWindow?.close()
            self?.navigation.showOverview()
            self?.showStatus()
          },
          openSettings: { [weak self] in self?.showSettings() }))
      gettingStartedWindow?.delegate = self
    }
    present(gettingStartedWindow)
  }
  @objc func showSettings() {
    if settingsWindow == nil {
      settingsWindow = window(
        title: L10n.tr("Sonoskope · 设置"), size: NSSize(width: 540, height: 700),
        view: SettingsView(model: model, updater: updater, openUpdates: { [weak self] in self?.showUpdates() }))
    }
    present(settingsWindow)
  }
  @objc func showUpdates() {
    if updateWindow == nil {
      updateWindow = window(title: L10n.tr("软件更新"), size: NSSize(width: 520, height: 400), view: SoftwareUpdateView(updater: updater))
    }
    present(updateWindow)
    updater.check()
  }
  private func present(_ window: NSWindow?) {
    // A visible settings window needs normal application activation while macOS
    // presents privacy UI. Accessory apps can hand focus back to the prior app.
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
  }
  private func window<V: View>(title: String, size: NSSize, view: V) -> NSWindow {
    let window = NSWindow(
      contentRect: .init(origin: .zero, size: size),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
    )
    window.title = title
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.contentView = NSHostingView(rootView: view.environment(\.locale, L10n.locale))
    window.center()
    return window
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    showStatus()
    return true
  }
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    // Retain the regular activation policy after a window has been opened, so
    // closing it leaves both the Dock and menu-bar entry available for reopening.
    if sender === gettingStartedWindow { onboarding.acknowledge() }
    sender.orderOut(nil)
    return false
  }
  func applicationWillTerminate(_ notification: Notification) {
    floatingMonitor?.stop()
    model?.shutdown()
  }
}
