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
  func applicationDidFinishLaunching(_ notification: Notification) {
    let smoke = CommandLine.arguments.contains("--smoke-test")
    model = MonitorModel(persist: !smoke)
    model.notifications.openIncident = { [weak self] id in
      self?.model.selectedIncidentID = id
      self?.showStatus()
    }
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    statusItem.button?.image = NSImage(
      systemSymbolName: "waveform.path", accessibilityDescription: L10n.tr("Sonoskope 音频诊断"))
    statusItem.button?.toolTip = L10n.tr("Sonoskope · 查看音频状态")
    statusItem.button?.target = self
    statusItem.button?.action = #selector(statusClicked)
    statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    model.start()
    if smoke {
      Task {
        try? await Task.sleep(for: .seconds(7))
        let payload: [String: Any] = [
          "application": "Sonoskope",
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
      if !CommandLine.arguments.contains("--background") { showStatus() }
    }
    let appMenu = NSMenu()
    let item = NSMenuItem()
    appMenu.addItem(item)
    let menu = NSMenu()
    menu.addItem(withTitle: L10n.tr("音频状态"), action: #selector(showStatus), keyEquivalent: "1")
    menu.addItem(withTitle: L10n.tr("设置…"), action: #selector(showSettings), keyEquivalent: ",")
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
