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

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
  private var model: MonitorModel!
  private var statusItem: NSStatusItem!
  private var statusWindow: NSWindow?
  private var settingsWindow: NSWindow?
  private var gettingStartedWindow: NSWindow?
  func applicationDidFinishLaunching(_ notification: Notification) {
    let smoke = CommandLine.arguments.contains("--smoke-test")
    // Explicit bounded hardware check; never enabled by the passive smoke test or CI.
    let microphoneCheck = !smoke && CommandLine.arguments.contains("--microphone-check")
    model = MonitorModel(persist: !smoke && !microphoneCheck)
    model.notifications.openIncident = { [weak self] id in
      self?.model.selectedIncidentID = id
      self?.showStatus()
    }
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    NSApp.applicationIconImage = BrandAssets.applicationIcon
    statusItem.button?.image = BrandAssets.menuBarIcon
    statusItem.button?.toolTip = L10n.tr("Sonoskope · 查看音频状态")
    statusItem.button?.target = self
    statusItem.button?.action = #selector(statusClicked)
    statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
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
      if let index = CommandLine.arguments.firstIndex(of: "--demo"),
        CommandLine.arguments.count > index + 1,
        let scenario = DemoScenario(rawValue: CommandLine.arguments[index + 1])
      {
        model.runDemo(scenario)
      }
      if !CommandLine.arguments.contains("--background") {
        if model.demoScenario == nil && !UserDefaults.standard.bool(forKey: "gettingStartedSeen") {
          showGettingStarted()
        } else {
          showStatus()
        }
      }
    }
    let appMenu = NSMenu()
    let item = NSMenuItem()
    appMenu.addItem(item)
    let menu = NSMenu()
    menu.addItem(withTitle: L10n.tr("音频状态"), action: #selector(showStatus), keyEquivalent: "1")
    menu.addItem(withTitle: L10n.tr("设置…"), action: #selector(showSettings), keyEquivalent: ",")
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
        title: L10n.tr("Sonoskope · 音频状态"), size: NSSize(width: 520, height: 740),
        view: StatusView(model: model, openSettings: { [weak self] in self?.showSettings() }))
    }
    statusWindow?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
  @objc func showGettingStarted() {
    if gettingStartedWindow == nil {
      gettingStartedWindow = window(
        title: L10n.tr("Sonoskope · 使用指南"), size: NSSize(width: 600, height: 710),
        view: GettingStartedView(
          model: model,
          finish: { [weak self] in
            UserDefaults.standard.set(true, forKey: "gettingStartedSeen")
            self?.gettingStartedWindow?.close()
            self?.showStatus()
          },
          openSettings: { [weak self] in self?.showSettings() }))
    }
    gettingStartedWindow?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
  @objc func showSettings() {
    if settingsWindow == nil {
      settingsWindow = window(
        title: L10n.tr("Sonoskope · 设置"), size: NSSize(width: 540, height: 700),
        view: SettingsView(model: model))
    }
    settingsWindow?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
  private func window<V: View>(title: String, size: NSSize, view: V) -> NSWindow {
    let window = NSWindow(
      contentRect: .init(origin: .zero, size: size),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
    )
    window.title = title
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: view.environment(\.locale, L10n.locale))
    window.center()
    return window
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
  func applicationWillTerminate(_ notification: Notification) { model?.shutdown() }
}
