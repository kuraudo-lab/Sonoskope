import AppKit
import Observation
import SonoskopeCore
import Sparkle

@MainActor @Observable final class SoftwareUpdater: NSObject, SPUUserDriver, SPUUpdaterDelegate {
  enum Phase: String { case disabled, idle, checking, downloading, ready, installing, current, failed }
  private(set) var phase: Phase = .disabled
  private(set) var availableVersion = ""
  private(set) var detail = ""
  private(set) var automatic = true
  @ObservationIgnored var present: (() -> Void)?
  @ObservationIgnored var willInstall: (() -> Void)?
  @ObservationIgnored var stateChanged: (() -> Void)?
  @ObservationIgnored private var sparkle: SPUUpdater?
  @ObservationIgnored private var download: Task<Void, Never>?
  @ObservationIgnored private var schedule: Task<Void, Never>?
  @ObservationIgnored private var package: UpdatePackage?
  @ObservationIgnored private var gate = UpdateInstallGate()
  @ObservationIgnored private let server = VerifiedUpdateServer()
  @ObservationIgnored private var localArchiveURL: URL?
  @ObservationIgnored private var cancellation: (() -> Void)?
  @ObservationIgnored private var suspended = false
  @ObservationIgnored private var started = false
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let bundle: Bundle
  @ObservationIgnored private let cache: URL

  init(bundle: Bundle = .main, defaults: UserDefaults = .standard) {
    self.bundle = bundle
    self.defaults = defaults
    self.cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent(bundle.bundleIdentifier ?? "Sonoskope").appendingPathComponent("VerifiedUpdates", isDirectory: true)
    super.init()
    automatic = defaults.object(forKey: "automaticSoftwareUpdates") as? Bool ?? true
  }

  var isReady: Bool { phase == .ready }
  var canCheck: Bool { started && !suspended && ![.checking, .downloading, .installing].contains(phase) }
  var status: String {
    switch phase {
    case .disabled: L10n.tr("此模式不检查软件更新")
    case .idle: L10n.tr("自动检查并下载，由你安装并重启")
    case .checking: L10n.tr("正在检查更新…")
    case .downloading: L10n.tr("正在后台下载并验证…")
    case .ready: L10n.tr("更新已准备好")
    case .installing: L10n.tr("正在安装，即将重新启动…")
    case .current: L10n.tr("当前没有可安装的新版本")
    case .failed: L10n.tr("更新未完成；现有版本保持不变")
    }
  }

  func start() {
    guard !started else { return }
    guard bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String != nil,
      bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String != nil else { return }
    let updater = SPUUpdater(hostBundle: bundle, applicationBundle: bundle, userDriver: self, delegate: self)
    sparkle = updater
    do {
      try updater.start()
      // We schedule information-only checks and predownload ourselves. Sparkle's
      // automatic installer is never armed before the user's install click.
      updater.automaticallyChecksForUpdates = false
      updater.automaticallyDownloadsUpdates = false
      started = true
      transition(.idle)
      schedule = Task { [weak self] in
        while !Task.isCancelled {
          guard let self else { return }
          let last = self.defaults.object(forKey: "lastSoftwareUpdateCheck") as? Date ?? .distantPast
          if self.automatic && !self.suspended && self.phase != .ready && Date().timeIntervalSince(last) >= 86400 {
            self.check()
          }
          do { try await Task.sleep(for: .seconds(60)) } catch { return }
        }
      }
    } catch { fail(error) }
  }

  func setAutomatic(_ value: Bool) {
    automatic = value
    defaults.set(value, forKey: "automaticSoftwareUpdates")
    if value && canCheck && !isReady { check() }
  }

  func setSuspended(_ value: Bool) {
    suspended = value
    if value && phase != .installing {
      download?.cancel(); download = nil
      if phase == .downloading { transition(.idle) }
    }
  }

  func check() {
    guard canCheck, let sparkle, !sparkle.sessionInProgress else { return }
    if isReady { return }
    detail = ""
    transition(.checking)
    defaults.set(Date(), forKey: "lastSoftwareUpdateCheck")
    sparkle.checkForUpdateInformation()
  }

  func installAndRelaunch() {
    guard !suspended, phase == .ready, let package, let sparkle, !sparkle.sessionInProgress else { return }
    do {
      let file = cache.appendingPathComponent(package.cacheName)
      try package.verify(file, publicKey: publicKey)
      gate.approve(package)
      transition(.installing)
      Task {
        do {
          localArchiveURL = try await server.start(file: file)
          sparkle.checkForUpdates()
        } catch { fail(error) }
      }
    } catch { fail(error) }
  }

  private var publicKey: String { bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? "" }
  private var allowsLocalTestFeed: Bool {
    bundle.bundleIdentifier == "lab.kuraudo.Sonoskope.UpdateTest"
      && bundle.object(forInfoDictionaryKey: "SonoskopeUpdateTest") as? Bool == true
  }
  private func metadata(_ item: SUAppcastItem) throws -> UpdatePackage {
    guard !item.isInformationOnlyUpdate, let url = item.fileURL,
      url.scheme == "https" || (allowsLocalTestFeed && url.scheme == "http" && url.host == "127.0.0.1"),
      let enclosure = item.propertiesDictionary["enclosure"] as? [String: Any],
      let signature = enclosure["sparkle:edSignature"] as? String,
      item.contentLength > 0, item.contentLength <= 256 * 1024 * 1024
    else { throw UpdateValidationError.invalidPackage }
    return UpdatePackage(version: item.versionString, displayVersion: item.displayVersionString,
      url: url, signature: signature, length: item.contentLength)
  }

  private func predownload(_ item: SUAppcastItem) {
    guard !suspended else { transition(.idle); return }
    do {
      let candidate = try metadata(item)
      package = candidate
      availableVersion = candidate.displayVersion
      download?.cancel()
      transition(.downloading)
      download = Task { [weak self] in
        guard let self else { return }
        do {
          try FileManager.default.createDirectory(at: self.cache, withIntermediateDirectories: true)
          let target = self.cache.appendingPathComponent(candidate.cacheName)
          if (try? candidate.verify(target, publicKey: self.publicKey)) == nil {
            let request = URLRequest(url: candidate.url, timeoutInterval: 120)
            let (temp, response) = try await URLSession.shared.download(for: request)
            defer { try? FileManager.default.removeItem(at: temp) }
            try Task.checkCancellation()
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            try candidate.verify(temp, publicKey: self.publicKey)
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.moveItem(at: temp, to: target)
          }
          try Task.checkCancellation()
          guard self.package == candidate, !self.suspended else { return }
          self.transition(.ready)
          // Keep one archive only. Never start Sparkle's installer in this path.
          for file in (try? FileManager.default.contentsOfDirectory(at: self.cache, includingPropertiesForKeys: nil)) ?? [] where file != target {
            try? FileManager.default.removeItem(at: file)
          }
        } catch is CancellationError { }
        catch { if !Task.isCancelled { self.fail(error) } }
      }
    } catch { fail(error) }
  }

  private func transition(_ value: Phase) { phase = value; stateChanged?() }
  private func fail(_ error: Error) {
    server.stop(); localArchiveURL = nil
    gate.reset()
    detail = error is UpdateValidationError ? L10n.tr("更新包验证失败，请稍后重试。") : error.localizedDescription
    transition(.failed)
  }

  // MARK: Sparkle delegate — information-only checks cannot arm the installer.
  func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool { false }
  func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
    if gate.approved == nil { predownload(item) }
  }
  func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
    gate.reset(); detail = ""; availableVersion = ""; package = nil; transition(.current)
  }
  func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
    let error = error as NSError
    if error.domain == SUSparkleErrorDomain && error.code == SUError.noUpdateError.rawValue {
      updaterDidNotFindUpdate(updater, error: error)
    } else { fail(error) }
  }
  func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
    guard let candidate = try? metadata(item), gate.allows(candidate) else { return }
    if let localArchiveURL { request.url = localArchiveURL }
  }
  func updater(_ updater: SPUUpdater, shouldDownloadReleaseNotesForUpdate item: SUAppcastItem) -> Bool { false }
  func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) { willInstall?() }

  // MARK: Sparkle UI driver — this path only starts after install consent.
  func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
    reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
  }
  func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) { self.cancellation = cancellation }
  func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
    guard let candidate = try? metadata(appcastItem), gate.allows(candidate), !suspended else {
      reply(state.stage == .installing ? .skip : .dismiss)
      fail(UpdateValidationError.changedUpdate)
      return
    }
    reply(.install)
  }
  func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
  func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
  func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
    updaterDidNotFindUpdate(sparkle!, error: error); acknowledgement()
  }
  func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) { fail(error); acknowledgement() }
  func showDownloadInitiated(cancellation: @escaping () -> Void) { self.cancellation = cancellation }
  func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
  func showDownloadDidReceiveData(ofLength length: UInt64) {}
  func showDownloadDidStartExtractingUpdate() {}
  func showExtractionReceivedProgress(_ progress: Double) {}
  func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
    guard gate.approved != nil, !suspended else { reply(.skip); return }
    willInstall?()
    reply(.install)
  }
  func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
    transition(.installing)
  }
  func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { acknowledgement() }
  func dismissUpdateInstallation() { cancellation = nil; gate.reset(); server.stop(); localArchiveURL = nil }
  func showUpdateInFocus() { present?() }
}
