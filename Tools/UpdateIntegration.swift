// Disposable app harness; never part of the distributed Sonoskope executable.
import AppKit
import Foundation

@main enum UpdateIntegration {
  @MainActor static func main() {
    let app = NSApplication.shared
    let delegate = UpdateIntegrationDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
  }
}

@MainActor final class UpdateIntegrationDelegate: NSObject, NSApplicationDelegate {
  let updater = SoftwareUpdater()
  var timer: Timer?
  let root = URL(fileURLWithPath: Bundle.main.object(forInfoDictionaryKey: "TestDirectory") as! String)
  let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String
  func applicationDidFinishLaunching(_ notification: Notification) {
    updater.stateChanged = { [weak self] in self?.record() }
    record()
    updater.start()
    updater.check()
    timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.poll() }
    }
  }
  func record() {
    let entry = "\(version) \(updater.phase.rawValue) \(updater.detail)\n"
    let file = root.appendingPathComponent("events.log")
    if !FileManager.default.fileExists(atPath: file.path) { FileManager.default.createFile(atPath: file.path, contents: nil) }
    if let handle = try? FileHandle(forWritingTo: file) {
      defer { try? handle.close() }
      try? handle.seekToEnd(); try? handle.write(contentsOf: Data(entry.utf8))
    }
    try? Data(entry.utf8).write(to: root.appendingPathComponent("state"), options: .atomic)
  }
  func poll() {
    let file = root.appendingPathComponent("command")
    guard let command = try? String(contentsOf: file).trimmingCharacters(in: .whitespacesAndNewlines) else { return }
    try? FileManager.default.removeItem(at: file)
    switch command {
    case "install": updater.installAndRelaunch()
    case "check": updater.check()
    case "quit": NSApp.terminate(nil)
    default: break
    }
  }
}
