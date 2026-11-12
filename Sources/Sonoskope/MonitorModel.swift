import AVFoundation
import AppKit
import Foundation
import Observation
import ServiceManagement
import SonoskopeCore

@MainActor @Observable final class MonitorModel {
  var hardware = HardwareSnapshot()
  var network = NetworkReading()
  var outputMeasurement: AudioMeasurement?
  var inputMeasurement: AudioMeasurement?
  var outputStatus = L10n.tr("未开启音频分析")
  var inputStatus = L10n.tr("麦克风未采集 · 可开启自动监测或手动测试")
  var microphoneRunning = false
  private(set) var automaticInputEnabled: Bool
  private(set) var automaticInputAuthorizing = false
  private var automaticInputPolicy = AutomaticInputPolicy()
  private var microphoneIsAutomatic = false
  private var microphoneDevice: InputDevice?
  private var microphoneStartedAt = Date()
  private var automaticError: String?
  private var automaticRetryAfter: Date?
  private var lastAutomaticTarget: InputDevice?
  @ObservationIgnored private var automaticAuthorizationGeneration = UUID()
  var paused = false
  var outputEnabled = false
  private(set) var outputSilenceMinutes: Int
  private(set) var outputSilencePauseMinutes: Int?
  @ObservationIgnored private var outputSilencePolicy = OutputSilencePolicy()
  var bluetoothEnabled: Bool
  var networkEnabled: Bool
  var notificationsEnabled: Bool
  var retentionHours: Int
  var selectedProcess: UInt32 = 0
  var selectedIncidentID: UUID?
  var feedback = ""
  var notificationStatus = L10n.tr("通知遵循系统权限与专注模式")
  var loginEnabled = false
  var demoScenario: DemoScenario?
  @ObservationIgnored var onDemoChange: ((Bool) -> Void)?
  var clock = Date()
  var audioHistory = TelemetryHistory()
  var networkHistory = TelemetryHistory()
  private var demoAudioHistory = TelemetryHistory()
  private var demoNetworkHistory = TelemetryHistory()
  private var demoDate = Date()
  var chartEnd: Date {
    if demoScenario != nil { return demoDate }
    if paused { return clock }
    return max(
      clock, max(audioHistory.points.last?.date ?? clock, networkHistory.points.last?.date ?? clock)
    )
  }
  var audioChartPoints: [TelemetryPoint] {
    (demoScenario == nil ? audioHistory : demoAudioHistory).recent(endingAt: chartEnd)
  }
  var networkChartPoints: [TelemetryPoint] {
    (demoScenario == nil ? networkHistory : demoNetworkHistory).recent(endingAt: chartEnd)
  }
  var latestEvents: [DiagnosticEvent] { engine.events.reversed() }
  var incidents: [Incident] { engine.incidents.reversed() }
  var selectedIncident: Incident? {
    if let id = selectedIncidentID, let incident = incidents.first(where: { $0.id == id }) {
      return incident
    }
    return incidents.first
  }
  var activeIncidents: [Incident] { incidents.filter(\.isActive) }
  var title: String {
    if demoScenario != nil { return L10n.tr("场景演示 · 模拟数据") }
    if paused { return L10n.tr("监测已暂停") }
    if automaticInputNeedsPermission { return L10n.tr("麦克风监测需要授权") }
    if let incident = activeIncidents.first(where: {
      $0.confidence == .suspected || $0.key.hasPrefix("deviceDisconnected:")
    }) {
      return incident.title.localized
    }
    if activeIncidents.contains(where: { $0.key.hasPrefix("captureUnavailable:") }) {
      return L10n.tr("音频监测不完整")
    }
    if !outputEnabled && !microphoneRunning { return L10n.tr("正在监测设备与连接") }
    if (outputEnabled && outputMeasurement == nil) || (microphoneRunning && inputMeasurement == nil)
    {
      return L10n.tr("音频分析等待数据")
    }
    if (outputEnabled && outputMeasurement.map { clock.timeIntervalSince($0.date) > 3 } == true)
      || (microphoneRunning
        && inputMeasurement.map { clock.timeIntervalSince($0.date) > 3 } == true)
    {
      return L10n.tr("音频采集暂无新数据")
    }
    return L10n.tr("已观测范围内未见持续异常")
  }
  var subtitle: String {
    if demoScenario != nil { return L10n.tr("真实采集与系统通知已暂停；演示不会写入历史。") }
    if paused, let minutes = outputSilencePauseMinutes {
      return L10n.tr("输出持续静音 \(minutes) 分钟，已自动暂停全部监测。点击恢复监测可重新开始。")
    }
    if paused { return L10n.tr("以下是暂停前的记录，不代表当前状态。") }
    return L10n.tr("只分析本机可见证据；不代表远端听感或耳机实际发声。")
  }
  var outputReading: String {
    guard demoScenario == nil else {
      return demoScenario == .correlated
        ? L10n.tr("模拟：重复可疑缺口")
        : demoScenario == .unavailable ? L10n.tr("模拟：无法采集") : L10n.tr("模拟：见问题记录")
    }
    guard outputEnabled, let sample = outputMeasurement else { return outputStatus }
    guard clock.timeIntervalSince(sample.date) <= 3 else { return L10n.tr("暂无新数据 · 不能判断音频质量") }
    if sample.rmsDB <= -100 { return L10n.tr("收到静音数据 · 不代表故障或采集授权有效") }
    return String(format: L10n.tr("本地数字输出 %.0f dBFS"), sample.rmsDB)
  }
  var inputReading: String {
    if demoScenario != nil { return L10n.tr("未检测（模拟场景）") }
    if automaticInputAuthorizing { return L10n.tr("等待麦克风授权或音频数据") }
    if automaticInputEnabled {
      if paused || sleeping { return L10n.tr("自动麦克风监测已暂停") }
      switch automaticInputPolicy.state {
      case .permissionRequired: return L10n.tr("需要麦克风权限；请在系统设置中允许后重试。")
      case .unknown: return L10n.tr("无法确认输入设备使用状态；未采集")
      case .ambiguous: return L10n.tr("多个输入设备活动；无法明确选择，未采集")
      case .stopping: return L10n.tr("其他应用已停止使用麦克风，正在结束采集…")
      case .waiting, .disabled, .suspended: return L10n.tr("自动待命 · 等待其他应用使用麦克风")
      case .active: break
      }
      if let automaticError { return automaticError + L10n.tr(" · 稍后自动重试") }
    }
    if microphoneRunning, let sample = inputMeasurement {
      guard clock.timeIntervalSince(sample.date) <= 3 else { return L10n.tr("麦克风暂无新数据") }
      return String(
        format: microphoneIsAutomatic ? L10n.tr("自动监测 · %.0f dBFS") : L10n.tr("测试中 · %.0f dBFS"),
        sample.rmsDB)
    }
    return inputStatus
  }
  var automaticInputNeedsPermission: Bool {
    automaticInputEnabled && !automaticInputAuthorizing && !microphoneAuthorized()
  }
  var currentInputDevice: AudioDeviceInfo? {
    if let device = microphoneDevice {
      return hardware.devices.first { $0.uid == device.uid }
    }
    return hardware.input
  }
  var inputDeviceRole: String {
    microphoneDevice == nil ? L10n.tr("系统默认输入") : L10n.tr("正在采集的输入")
  }
  var inputDeviceDetail: String {
    if demoScenario != nil { return L10n.tr("演示不采集麦克风") }
    return inputDeviceRole + " · " + (currentInputDevice?.name ?? L10n.tr("无可用输入"))
  }
  var inputApplicationContext: String? {
    guard let device = microphoneDevice else { return nil }
    let users = hardware.inputUsers(of: device.id, observerPID: getpid())
    if !users.isEmpty { return users.joined(separator: " · ") }
    return microphoneIsAutomatic
      ? L10n.tr("未观察到其他应用 · 结束缓冲") : L10n.tr("Sonoskope · 手动测试")
  }
  @ObservationIgnored lazy var notifications = NotificationService()
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let store = IncidentStore()
  @ObservationIgnored private let persist: Bool
  @ObservationIgnored private var liveEngine = DiagnosticEngine()
  @ObservationIgnored private var demoEngine = DiagnosticEngine()
  private var revision = 0
  private var engine: DiagnosticEngine {
    _ = revision
    return demoScenario == nil ? liveEngine : demoEngine
  }
  @ObservationIgnored private let deviceMonitor = HardwareMonitor()
  @ObservationIgnored private let hardwareReader = HardwareReader()
  @ObservationIgnored private let networkMonitor: any NetworkProbing
  private(set) var networkAudioActive = false
  @ObservationIgnored private var nextProbeAt = Date.distantPast
  @ObservationIgnored private var networkActivityGeneration = UUID()
  @ObservationIgnored private let outputCapture = OutputCapture()
  @ObservationIgnored private let microphone: any MicrophoneCapturing
  @ObservationIgnored private let microphoneAuthorized: @MainActor () -> Bool
  @ObservationIgnored private let requestMicrophoneAuthorization: @MainActor () async -> Bool
  @ObservationIgnored private let readInputHardware: @MainActor () -> HardwareSnapshot
  @ObservationIgnored private let runsCollectors: Bool
  @ObservationIgnored private var pollTask: Task<Void, Never>?
  @ObservationIgnored private var networkTask: Task<Void, Never>?
  @ObservationIgnored private var probeDegraded = false
  @ObservationIgnored private var captureGeneration = UUID()
  @ObservationIgnored private var microphoneGeneration = UUID()
  @ObservationIgnored private var lastAudioEvent: [Direction: Date] = [:]
  @ObservationIgnored private var lastCaptureFault: [Direction: Date] = [:]
  @ObservationIgnored private var wakeObserver: NSObjectProtocol?
  @ObservationIgnored private var sleepObserver: NSObjectProtocol?
  @ObservationIgnored private var sleeping = false

  init(
    persist: Bool = true, microphone: (any MicrophoneCapturing)? = nil,
    microphoneAuthorized: (@MainActor () -> Bool)? = nil,
    requestMicrophoneAuthorization: (@MainActor () async -> Bool)? = nil,
    readInputHardware: (@MainActor () -> HardwareSnapshot)? = nil,
    runsCollectors: Bool = true, networkMonitor: (any NetworkProbing)? = nil,
    settings: UserDefaults? = nil
  ) {
    self.networkMonitor = networkMonitor ?? NetworkMonitor()
    self.persist = persist
    self.microphone = microphone ?? MicrophoneCapture()
    self.microphoneAuthorized =
      microphoneAuthorized ?? { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }
    self.requestMicrophoneAuthorization =
      requestMicrophoneAuthorization ?? { await AVCaptureDevice.requestAccess(for: .audio) }
    self.readInputHardware = readInputHardware ?? { AudioHAL.snapshot(includeBluetooth: false) }
    self.runsCollectors = runsCollectors
    defaults =
      settings ?? (persist ? .standard : UserDefaults(suiteName: "Sonoskope.Tests." + UUID().uuidString)!)
    automaticInputEnabled = (persist || settings != nil) && defaults.bool(forKey: "automaticInput")
    outputEnabled = defaults.bool(forKey: "outputAnalysis")
    let silenceMinutes = defaults.object(forKey: "outputSilenceMinutes") as? Int ?? 5
    outputSilenceMinutes = (0...60).contains(silenceMinutes) ? silenceMinutes : 5
    bluetoothEnabled = defaults.bool(forKey: "bluetooth")
    networkEnabled = defaults.object(forKey: "network") as? Bool ?? true
    notificationsEnabled = defaults.bool(forKey: "notifications")
    retentionHours = defaults.object(forKey: "retention") as? Int ?? 24
    liveEngine = DiagnosticEngine(
      incidents: persist ? store.load(retentionHours: retentionHours) : [])
    loginEnabled = runsCollectors && SMAppService.mainApp.status == .enabled
    self.networkMonitor.onPath = { [weak self] path in self?.network.path = path }
    guard runsCollectors else { return }
    wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.systemDidWake()
      }
    }
    sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.systemWillSleep()
      }
    }
  }
  func systemWillSleep() {
    sleeping = true
    stopCollectors()
  }
  func systemDidWake() {
    sleeping = false
    deviceMonitor.reset()
    network.samples = []
    probeDegraded = false
    if !paused && demoScenario == nil { startCollectors() }
    receive(.init(kind: .lifecycle, source: "system", message: "系统唤醒，重新建立基线"))
  }
  func start() { if !paused && demoScenario == nil { startCollectors() } }
  private func startCollectors() {
    guard runsCollectors, !sleeping, pollTask == nil else { return }
    deviceMonitor.reset()
    liveEngine.resetObservationWindow()
    lastAudioEvent.removeAll()
    lastCaptureFault.removeAll()
    networkMonitor.start()
    pollTask = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        let reading = await self.hardwareReader.snapshot(bluetooth: self.bluetoothEnabled)
        guard !Task.isCancelled, !self.paused, !self.sleeping, self.demoScenario == nil else { return }
        let (snapshot, events, active) = self.deviceMonitor.poll(snapshot: reading)
        self.acceptHardwareSnapshot(snapshot)
        for event in events { self.receive(event, audioActive: active) }
        if self.outputEnabled
          && events.contains(where: { $0.kind == .formatChanged || $0.kind == .routeChanged })
        {
          self.startOutput()
        }
        self.liveEngine.settle(at: self.clock)
        if self.retentionHours > 0 {
          self.liveEngine.prune(
            before: self.clock.addingTimeInterval(-Double(self.retentionHours) * 3600))
        }
        self.revision += 1
        do { try await Task.sleep(for: .seconds(2)) } catch { return }
      }
    }
    restartNetwork()
    if outputEnabled { startOutput() }
  }
  private func stopCollectors() {
    outputSilencePolicy.reset()
    clock = Date()
    audioHistory.breakSeries("input")
    audioHistory.breakSeries("output")
    networkHistory.breakSeries("network")
    pollTask?.cancel()
    pollTask = nil
    networkTask?.cancel()
    networkTask = nil
    networkMonitor.stop()
    captureGeneration = UUID()
    outputCapture.stop()
    outputMeasurement = nil
    stopMicrophoneCapture()
    automaticInputPolicy.suspend()
    lastAutomaticTarget = nil
  }
  func shutdown() {
    automaticAuthorizationGeneration = UUID()
    automaticInputAuthorizing = false
    paused = true
    stopCollectors()
    save()
  }
  func togglePause() {
    if demoScenario != nil {
      exitDemo()
      return
    }
    outputSilencePauseMinutes = nil
    paused.toggle()
    if paused { stopCollectors() } else { startCollectors() }
  }
  func updateSettings() {
    defaults.set(bluetoothEnabled, forKey: "bluetooth")
    defaults.set(networkEnabled, forKey: "network")
    defaults.set(notificationsEnabled, forKey: "notifications")
    defaults.set(retentionHours, forKey: "retention")
    if retentionHours > 0 {
      liveEngine.prune(before: Date().addingTimeInterval(-Double(retentionHours) * 3600))
      revision += 1
    }
    save()
    if !paused && demoScenario == nil { restartNetwork() }
  }
  func setLogin(_ value: Bool) {
    do {
      if value {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      loginEnabled = SMAppService.mainApp.status == .enabled
      feedback = loginEnabled ? L10n.tr("登录启动已启用") : L10n.tr("登录启动未启用；如需批准，请检查系统登录项。")
    } catch {
      loginEnabled = SMAppService.mainApp.status == .enabled
      feedback = error.localizedDescription
    }
  }
  func requestNotifications() {
    Task { notificationStatus = await notifications.authorize() }
  }
  // A valid PCM window above the analyzer's near-silence floor is activity,
  // not evidence that the device or remote participant sounds good.
  func updateNetworkActivity(at now: Date = Date()) {
    let active =
      networkEnabled && !paused && !sleeping && demoScenario == nil
      && [(microphoneRunning, inputMeasurement), (outputEnabled, outputMeasurement)].contains {
        enabled, sample in
        guard enabled, let sample else { return false }
        let age = now.timeIntervalSince(sample.date)
        return age >= 0 && age <= 3 && sample.sampleCount > 0
          && !sample.discontinuity && sample.rmsDB.isFinite && sample.rmsDB > -65
      }
    if networkAudioActive != active { networkActivityGeneration = UUID() }
    if networkAudioActive && !active {
      networkMonitor.cancelProbe()
      network.samples = []
      network.duration = nil
      network.lastUpdated = nil
      networkHistory.breakSeries("network")
      probeDegraded = false
    }
    networkAudioActive = active
    if !active {
      network.probe = networkEnabled ? L10n.tr("等待音频活动 · 网络探测待命") : L10n.tr("主动探测已关闭")
    }
  }
  func restartNetwork() {
    networkTask?.cancel()
    networkTask = nil
    networkMonitor.stop()
    networkMonitor.start()
    network.samples = []
    networkHistory.breakSeries("network")
    probeDegraded = false
    updateNetworkActivity()
    guard networkEnabled else {
      network.probe = L10n.tr("主动探测已关闭")
      return
    }
    networkTask = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        self.updateNetworkActivity()
        guard self.networkAudioActive, Date() >= self.nextProbeAt else {
          do { try await Task.sleep(for: .seconds(1)) } catch { return }
          continue
        }
        let activityGeneration = self.networkActivityGeneration
        let value = await self.networkMonitor.probe()
        self.nextProbeAt = Date().addingTimeInterval(5)
        guard !Task.isCancelled, self.demoScenario == nil, !self.paused else { return }
        self.updateNetworkActivity()
        guard self.networkAudioActive, self.networkActivityGeneration == activityGeneration else {
          continue
        }
        let sample = ProbeSample(milliseconds: value)
        self.network.samples = Array((self.network.samples + [sample]).suffix(12))
        self.networkHistory.append(
          value: value, source: "network", date: sample.date, maximumGap: 15)
        self.network.duration = value
        self.network.lastUpdated = Date()
        self.network.wifi = NetworkMonitor.wifiDescription()
        let summary = ProbeSummary(samples: self.network.samples)
        self.network.probe =
          value.map { String(format: L10n.tr("TCP 连接 %.0f ms"), $0) } ?? L10n.tr("测试连接失败／超时")
        if summary.degraded {
          self.receive(
            .init(
              kind: .networkDegraded, source: "probe",
              message: "到 www.apple.com:443 的测试连接异常（含 DNS）；并非会议丢包率"))
        } else if self.probeDegraded {
          self.receive(.init(kind: .networkRecovered, source: "probe", message: "测试连接最近窗口未再超出阈值"))
        }
        self.probeDegraded = summary.degraded
        do { try await Task.sleep(for: .seconds(5)) } catch { return }
      }
    }
  }
  func setOutputEnabled(_ enabled: Bool) {
    guard enabled != outputEnabled else { return }
    outputSilencePolicy.reset()
    outputEnabled = enabled
    if demoScenario == nil { defaults.set(enabled && selectedProcess == 0, forKey: "outputAnalysis") }
    outputMeasurement = nil
    updateNetworkActivity()
    lastAudioEvent[.output] = nil
    captureGeneration = UUID()
    outputCapture.stop()
    if enabled && runsCollectors && !paused && demoScenario == nil {
      startOutput()
    } else {
      outputStatus = enabled ? L10n.tr("等待恢复监测") : L10n.tr("未开启音频分析")
    }
  }
  func selectProcess(_ id: UInt32) {
    outputSilencePolicy.reset()
    selectedProcess = id
    // Process object IDs are session-local. Never restore a single-process opt-in
    // as a broader global capture after relaunch.
    if demoScenario == nil { defaults.set(outputEnabled && id == 0, forKey: "outputAnalysis") }
    if outputEnabled && runsCollectors && !paused && demoScenario == nil { startOutput() }
  }
  private func startOutput() {
    outputSilencePolicy.reset()
    lastAudioEvent[.output] = nil
    audioHistory.breakSeries("output")
    captureGeneration = UUID()
    let token = captureGeneration
    outputMeasurement = nil
    updateNetworkActivity()
    outputStatus = L10n.tr("等待采集授权或音频数据")
    guard #available(macOS 14.2, *) else {
      outputStatus = L10n.tr("需要 macOS 14.2 或更新版本")
      return
    }
    if selectedProcess != 0 && !hardware.processes.contains(where: { $0.id == selectedProcess }) {
      outputStatus = L10n.tr("所选音频进程已退出，请重新选择")
      return
    }
    do {
      try outputCapture.start(processes: selectedProcess == 0 ? nil : [selectedProcess]) {
        [weak self] sample in
        guard let self, self.captureGeneration == token, self.outputEnabled, !self.paused,
          self.demoScenario == nil
        else { return }
        self.acceptOutputMeasurement(sample)
      }
    } catch {
      outputStatus = error.localizedDescription
      receive(
        .init(
          kind: .captureUnavailable, direction: .output, source: "output",
          message: (error as? CaptureError)?.diagnosticText
            ?? LocalizedText(verbatim: error.localizedDescription)))
    }
  }
  func setOutputSilenceMinutes(_ minutes: Int) {
    guard demoScenario == nil else { return }
    outputSilenceMinutes = min(60, max(0, minutes))
    defaults.set(outputSilenceMinutes, forKey: "outputSilenceMinutes")
    outputSilencePolicy.reset()
  }
  func acceptOutputMeasurement(_ sample: AudioMeasurement, receivedAt now: Date = Date()) {
    guard outputEnabled, !paused, !sleeping, demoScenario == nil else { return }
    let age = now.timeIntervalSince(sample.date)
    guard age >= 0, age <= 3 else { outputSilencePolicy.reset(); return }
    let first = outputMeasurement == nil
    outputMeasurement = sample
    outputStatus = L10n.tr("正在分析本地输出")
    if first {
      receive(.init(kind: .captureRestored, direction: .output, source: "output",
        message: "已收到采集回调；全静音仍不能证明权限或声音质量正常"))
    }
    handle(sample, direction: .output)
    if outputSilencePolicy.observe(sample, timeout: Double(outputSilenceMinutes) * 60) {
      outputSilencePauseMinutes = outputSilenceMinutes
      paused = true
      stopCollectors()
    }
  }
  func setAutomaticInputEnabled(_ enabled: Bool) {
    guard !enabled || demoScenario == nil else { return }
    automaticAuthorizationGeneration = UUID()
    let token = automaticAuthorizationGeneration
    automaticInputAuthorizing = false
    automaticInputEnabled = enabled
    if persist { defaults.set(enabled, forKey: "automaticInput") }
    automaticError = nil
    automaticRetryAfter = nil
    lastAutomaticTarget = nil
    automaticInputPolicy.suspend()
    stopMicrophoneCapture()
    guard enabled else { return }
    automaticInputAuthorizing = true
    Task { [weak self] in
      guard let self else { return }
      let granted = await self.requestMicrophoneAuthorization()
      guard self.automaticAuthorizationGeneration == token, self.automaticInputEnabled
      else { return }
      self.automaticInputAuthorizing = false
      if !granted { self.automaticError = L10n.tr("需要麦克风权限；请在系统设置中允许后重试。") }
      guard !self.paused, !self.sleeping, self.demoScenario == nil else { return }
      self.acceptHardwareSnapshot(self.readInputHardware())
    }
  }
  func acceptHardwareSnapshot(_ snapshot: HardwareSnapshot) {
    hardware = snapshot
    clock = snapshot.timestamp
    reconcileAutomaticInput()
    updateNetworkActivity(at: clock)
  }
  private func reconcileAutomaticInput() {
    let devices = hardware.devices.filter {
      $0.inputChannels > 0 && $0.sampleRate > 0 && !$0.uid.isEmpty
    }
    .map { InputDevice(id: $0.id, uid: $0.uid, sampleRate: $0.sampleRate) }
    let desired = automaticInputPolicy.update(
      enabled: automaticInputEnabled,
      suspended: paused || sleeping || demoScenario != nil
        || (microphoneRunning && !microphoneIsAutomatic),
      authorized: microphoneAuthorized(),
      processes: hardware.inputProcesses, devices: devices, defaultInput: hardware.defaultInput,
      observerPID: getpid(), observerBundleID: "lab.kuraudo.Sonoskope", at: clock)
    if desired != lastAutomaticTarget {
      automaticRetryAfter = nil
      automaticError = nil
      lastAutomaticTarget = desired
    }
    if microphoneIsAutomatic && microphoneDevice != desired { stopMicrophoneCapture() }
    guard let desired else { return }
    if microphoneIsAutomatic, microphoneRunning,
      clock.timeIntervalSince(inputMeasurement?.date ?? microphoneStartedAt) > 5
    {
      stopMicrophoneCapture()
      automaticError = L10n.tr("麦克风暂无新数据；已停止采集，稍后重试。")
      automaticRetryAfter = clock.addingTimeInterval(10)
    }
    guard !microphoneRunning, automaticRetryAfter.map({ clock >= $0 }) ?? true else { return }
    automaticError = nil
    beginMicrophone(device: desired, automatic: true)
  }
  func startMicrophone() {
    guard demoScenario == nil, !paused, !sleeping, !microphoneRunning, !automaticInputEnabled else {
      return
    }
    let snapshot = readInputHardware()
    guard let input = snapshot.input, input.inputChannels > 0 else {
      inputStatus = L10n.tr("输入设备不可用；已停止采集。")
      return
    }
    beginMicrophone(
      device: .init(id: input.id, uid: input.uid, sampleRate: input.sampleRate), automatic: false)
  }
  private func beginMicrophone(device: InputDevice, automatic: Bool) {
    stopMicrophoneCapture()
    let token = microphoneGeneration
    microphoneRunning = true
    microphoneIsAutomatic = automatic
    microphoneDevice = device
    microphoneStartedAt = Date()
    inputMeasurement = nil
    inputStatus = L10n.tr("等待麦克风授权或音频数据")
    lastAudioEvent[.input] = nil
    lastCaptureFault[.input] = nil
    Task { [weak self] in
      guard let self, self.microphoneGeneration == token, self.microphoneRunning,
        !self.paused, !self.sleeping, self.demoScenario == nil
      else { return }
      await self.microphone.start(
        deviceID: device.id, duration: automatic ? nil : 10,
        requestPermission: !automatic,
        onMeasurement: { [weak self] sample in
          guard let self, self.microphoneGeneration == token, self.microphoneRunning,
            !self.paused, !self.sleeping, self.demoScenario == nil
          else { return }
          self.inputMeasurement = sample
          self.handle(sample, direction: .input)
        },
        onEnd: { [weak self] end in
          guard let self, self.microphoneGeneration == token else { return }
          let lastLevel = self.inputMeasurement?.rmsDB
          self.stopMicrophoneCapture()
          switch end {
          case .completed:
            self.inputStatus = L10n.tr("10 秒本地测试已结束。结果不代表远端听感。")
            if let lastLevel {
              self.inputStatus += String(format: L10n.tr(" 最后电平 %.0f dBFS。"), lastLevel)
            }
          case .permissionDenied:
            self.inputStatus = L10n.tr("需要麦克风权限；请在系统设置中允许后重试。")
          case .configurationChanged:
            self.inputStatus = L10n.tr("输入设备配置变化；已停止采集。")
          case .failed(let message): self.inputStatus = message
          }
          if automatic {
            self.automaticError = self.inputStatus
            self.automaticRetryAfter = Date().addingTimeInterval(10)
          }
        })
    }
  }
  func stopMicrophone() {
    if automaticInputEnabled { setAutomaticInputEnabled(false) } else { stopMicrophoneCapture() }
  }
  private func stopMicrophoneCapture() {
    microphoneGeneration = UUID()
    microphone.stop()
    if microphoneRunning { inputStatus = L10n.tr("麦克风采集已停止") }
    microphoneRunning = false
    microphoneIsAutomatic = false
    microphoneDevice = nil
    inputMeasurement = nil
    audioHistory.breakSeries("input")
    updateNetworkActivity()
  }
  private func handle(_ sample: AudioMeasurement, direction: Direction) {
    updateNetworkActivity()
    audioHistory.append(
      value: sample.discontinuity ? nil : sample.rmsDB, source: direction.rawValue,
      date: sample.date, maximumGap: 2,
      context: direction == .input ? inputApplicationContext : nil)
    let eventSource =
      direction == .input
      ? microphoneDevice.map { "input:\($0.uid)" } ?? "input" : direction.rawValue
    if sample.discontinuity {
      if lastCaptureFault[direction] == nil
        || sample.date.timeIntervalSince(lastCaptureFault[direction]!) > 10
      {
        lastCaptureFault[direction] = sample.date
        receive(
          .init(
            kind: .captureUnavailable, direction: direction, source: eventSource,
            message: "采集时间戳不连续；不能把它直接归为耳机播放中断"))
      }
      return
    }
    if let lastFault = lastCaptureFault[direction], sample.date.timeIntervalSince(lastFault) > 2 {
      lastCaptureFault[direction] = nil
      receive(
        .init(
          kind: .captureRestored, direction: direction, source: eventSource,
          message: "采集时间戳恢复连续；不代表端到端音质正常"))
    }
    if let last = lastAudioEvent[direction], sample.date.timeIntervalSince(last) < 1 { return }
    let kind: EventKind? =
      sample.clippingFraction > 0.02 ? .clipping : sample.suspectGap ? .audioGap : nil
    if let kind {
      lastAudioEvent[direction] = sample.date
      receive(
        .init(
          kind: kind, direction: direction, source: eventSource,
          message: kind == .clipping
            ? "近满幅样本超过 2%；可能削波或内容本身如此" : "活动音频之间出现 40–250 ms 近静音缺口；只是启发式线索", date: sample.date),
        audioActive: true)
    }
  }
  func receive(_ event: DiagnosticEvent, audioActive: Bool? = nil) {
    guard demoScenario == nil else { return }
    let update = liveEngine.ingest(event, audioActive: audioActive ?? hardware.audioActive)
    revision += 1
    if let incident = update.changedIncident {
      selectedIncidentID = incident.id
      save()
    }
    if let incident = update.notification, notificationsEnabled, !paused {
      notifications.post(incident)
    }
  }
  func mark(_ direction: Direction) {
    if demoScenario != nil {
      feedback = L10n.tr("演示中不创建真实记录。请先返回实时监测。")
      return
    }
    receive(.init(kind: .userMarked, direction: direction, source: "user", message: "用户手工标记声音异常"))
    feedback = L10n.tr("已记录时间点及近期事件；不包含录音。")
  }
  func runDemo(_ scenario: DemoScenario) {
    if demoScenario == nil {
      save()
      stopCollectors()
    }
    demoScenario = scenario
    onDemoChange?(true)
    demoDate = Date()
    demoAudioHistory = TelemetryHistory()
    demoNetworkHistory = TelemetryHistory()
    for index in 0..<120 {
      let date = demoDate.addingTimeInterval(Double(index) * 0.5 - 60)
      if scenario != .unavailable {
        let gap = scenario == .correlated && [92, 98, 106].contains(index)
        let missing = scenario == .bluetooth && index > 108
        let level = gap ? -120.0 : -28.0 + sin(Double(index) * 0.31) * 8
        demoAudioHistory.append(
          value: missing ? nil : level, source: "output", date: date, maximumGap: 2)
      }
      if index % 10 == 0 {
        let badNetwork = (scenario == .networkOnly || scenario == .correlated) && index >= 90
        demoNetworkHistory.append(
          value: badNetwork && index == 100 ? nil : badNetwork ? 650 : 25 + Double(index % 7),
          source: "network", date: date, maximumGap: 15)
      }
    }
    demoEngine = DiagnosticEngine()
    selectedIncidentID = nil
    for event in scenario.events(at: demoDate.addingTimeInterval(-10)) {
      _ = demoEngine.ingest(event, audioActive: true)
    }
    revision += 1
  }
  func exitDemo() {
    demoScenario = nil
    onDemoChange?(false)
    demoEngine.clear()
    selectedIncidentID = nil
    revision += 1
    if !paused { startCollectors() }
  }
  func clearHistory() {
    if demoScenario != nil {
      demoEngine.clear()
    } else {
      liveEngine.clear()
      save()
    }
    selectedIncidentID = nil
    revision += 1
  }
  func save() {
    guard persist, demoScenario == nil else { return }
    do { try store.save(liveEngine.incidents, retentionHours: retentionHours) } catch {
      feedback = L10n.tr("问题记录保存失败：") + error.localizedDescription
    }
  }
  func exportReport() {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.json]
    panel.nameFieldStringValue = "Sonoskope-diagnostics.json"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      encoder.dateEncodingStrategy = .iso8601
      try encoder.encode(incidents).write(to: url, options: .atomic)
      feedback = L10n.tr("已导出问题与证据；含设备／应用标识，不含录音。")
    } catch { feedback = L10n.tr("导出失败：") + error.localizedDescription }
  }
}
