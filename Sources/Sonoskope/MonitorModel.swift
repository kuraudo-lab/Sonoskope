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
  var outputStatus = "未开启音频分析"
  var inputStatus = "未检测 · 仅在主动测试时采集"
  var microphoneRunning = false
  var paused = false
  var outputEnabled = false
  var bluetoothEnabled: Bool
  var networkEnabled: Bool
  var notificationsEnabled: Bool
  var retentionHours: Int
  var selectedProcess: UInt32 = 0
  var selectedIncidentID: UUID?
  var feedback = ""
  var notificationStatus = "通知遵循系统权限与专注模式"
  var loginEnabled = false
  var demoScenario: DemoScenario?
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
    if demoScenario != nil { return "场景演示 · 模拟数据" }
    if paused { return "监测已暂停" }
    if let incident = activeIncidents.first(where: {
      $0.confidence == .suspected || $0.key.hasPrefix("deviceDisconnected:")
    }) {
      return incident.title
    }
    if activeIncidents.contains(where: { $0.key.hasPrefix("captureUnavailable:") }) {
      return "音频监测不完整"
    }
    if !outputEnabled { return "正在监测设备与连接" }
    if outputMeasurement == nil { return "音频分析等待数据" }
    if let measurement = outputMeasurement, clock.timeIntervalSince(measurement.date) > 3 {
      return "音频采集暂无新数据"
    }
    return "已观测范围内未见持续异常"
  }
  var subtitle: String {
    if demoScenario != nil { return "真实采集与系统通知已暂停；演示不会写入历史。" }
    if paused { return "以下是暂停前的记录，不代表当前状态。" }
    return "只分析本机可见证据；不代表远端听感或耳机实际发声。"
  }
  var outputReading: String {
    guard demoScenario == nil else {
      return demoScenario == .correlated
        ? "模拟：重复可疑缺口" : demoScenario == .unavailable ? "模拟：无法采集" : "模拟：见问题记录"
    }
    guard outputEnabled, let sample = outputMeasurement else { return outputStatus }
    guard clock.timeIntervalSince(sample.date) <= 3 else { return "暂无新数据 · 不能判断音频质量" }
    if sample.rmsDB <= -100 { return "收到静音数据 · 不代表故障或采集授权有效" }
    return String(format: "本地数字输出 %.0f dBFS", sample.rmsDB)
  }
  var inputReading: String {
    if demoScenario != nil { return "未检测（模拟场景）" }
    if microphoneRunning, let sample = inputMeasurement {
      return String(format: "测试中 · %.0f dBFS", sample.rmsDB)
    }
    return inputStatus
  }
  @ObservationIgnored let notifications = NotificationService()
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
  @ObservationIgnored private let networkMonitor = NetworkMonitor()
  @ObservationIgnored private let outputCapture = OutputCapture()
  @ObservationIgnored private let microphone = MicrophoneTest()
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

  init(persist: Bool = true) {
    self.persist = persist
    defaults =
      persist ? .standard : UserDefaults(suiteName: "Sonoskope.Tests." + UUID().uuidString)!
    bluetoothEnabled = defaults.bool(forKey: "bluetooth")
    networkEnabled = defaults.object(forKey: "network") as? Bool ?? true
    notificationsEnabled = defaults.bool(forKey: "notifications")
    retentionHours = defaults.object(forKey: "retention") as? Int ?? 24
    liveEngine = DiagnosticEngine(
      incidents: persist ? store.load(retentionHours: retentionHours) : [])
    loginEnabled = SMAppService.mainApp.status == .enabled
    networkMonitor.onPath = { [weak self] path in self?.network.path = path }
    wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        self.sleeping = false
        self.deviceMonitor.reset()
        self.network.samples = []
        self.probeDegraded = false
        if !self.paused && self.demoScenario == nil { self.startCollectors() }
        self.receive(.init(kind: .lifecycle, source: "system", message: "系统唤醒，重新建立基线"))
      }
    }
    sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.sleeping = true
        self?.stopCollectors()
      }
    }
  }
  func start() { if !paused && demoScenario == nil { startCollectors() } }
  private func startCollectors() {
    guard !sleeping, pollTask == nil else { return }
    deviceMonitor.reset()
    liveEngine.resetObservationWindow()
    lastAudioEvent.removeAll()
    lastCaptureFault.removeAll()
    networkMonitor.start()
    pollTask = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        let (snapshot, events, active) = self.deviceMonitor.poll(bluetooth: self.bluetoothEnabled)
        self.hardware = snapshot
        self.clock = Date()
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
    stopMicrophone()
  }
  func shutdown() {
    stopCollectors()
    save()
  }
  func togglePause() {
    if demoScenario != nil {
      exitDemo()
      return
    }
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
      feedback = loginEnabled ? "登录启动已启用" : "登录启动未启用；如需批准，请检查系统登录项。"
    } catch {
      loginEnabled = SMAppService.mainApp.status == .enabled
      feedback = error.localizedDescription
    }
  }
  func requestNotifications() {
    Task { notificationStatus = await notifications.authorize() }
  }
  private func restartNetwork() {
    networkTask?.cancel()
    networkTask = nil
    networkMonitor.stop()
    networkMonitor.start()
    network.samples = []
    networkHistory.breakSeries("network")
    probeDegraded = false
    guard networkEnabled else {
      network.probe = "主动探测已关闭"
      return
    }
    networkTask = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        let value = await self.networkMonitor.probe()
        guard !Task.isCancelled, self.demoScenario == nil, !self.paused else { return }
        let sample = ProbeSample(milliseconds: value)
        self.network.samples = Array((self.network.samples + [sample]).suffix(12))
        self.networkHistory.append(
          value: value, source: "network", date: sample.date, maximumGap: 15)
        self.network.duration = value
        self.network.lastUpdated = Date()
        self.network.wifi = NetworkMonitor.wifiDescription()
        let summary = ProbeSummary(samples: self.network.samples)
        self.network.probe = value.map { String(format: "TCP 连接 %.0f ms", $0) } ?? "测试连接失败／超时"
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
    outputEnabled = enabled
    outputMeasurement = nil
    lastAudioEvent[.output] = nil
    captureGeneration = UUID()
    outputCapture.stop()
    if enabled && !paused && demoScenario == nil {
      startOutput()
    } else {
      outputStatus = enabled ? "等待恢复监测" : "未开启音频分析"
    }
  }
  func selectProcess(_ id: UInt32) {
    selectedProcess = id
    if outputEnabled { setOutputEnabled(true) }
  }
  private func startOutput() {
    audioHistory.breakSeries("output")
    captureGeneration = UUID()
    let token = captureGeneration
    outputMeasurement = nil
    outputStatus = "等待采集授权或音频数据"
    guard #available(macOS 14.2, *) else {
      outputStatus = "需要 macOS 14.2 或更新版本"
      return
    }
    if selectedProcess != 0 && !hardware.processes.contains(where: { $0.id == selectedProcess }) {
      outputStatus = "所选音频进程已退出，请重新选择"
      return
    }
    do {
      try outputCapture.start(processes: selectedProcess == 0 ? nil : [selectedProcess]) {
        [weak self] sample in
        guard let self, self.captureGeneration == token, self.outputEnabled, !self.paused,
          self.demoScenario == nil
        else { return }
        let first = self.outputMeasurement == nil
        self.outputMeasurement = sample
        self.outputStatus = "正在分析本地输出"
        if first {
          self.receive(
            .init(
              kind: .captureRestored, direction: .output, source: "output",
              message: "已收到采集回调；全静音仍不能证明权限或声音质量正常"))
        }
        self.handle(sample, direction: .output)
      }
    } catch {
      outputStatus = error.localizedDescription
      receive(
        .init(
          kind: .captureUnavailable, direction: .output, source: "output",
          message: error.localizedDescription))
    }
  }
  func startMicrophone() {
    audioHistory.breakSeries("input")
    guard demoScenario == nil, !paused, !microphoneRunning else { return }
    microphoneGeneration = UUID()
    let token = microphoneGeneration
    microphoneRunning = true
    inputMeasurement = nil
    inputStatus = "等待麦克风权限／开始测试"
    lastAudioEvent[.input] = nil
    Task { [self] in
      guard microphoneGeneration == token, microphoneRunning, !paused, demoScenario == nil else {
        return
      }
      await microphone.start(
        onMeasurement: { [weak self] sample in
          guard let self, self.microphoneGeneration == token, self.microphoneRunning else { return }
          self.inputMeasurement = sample
          self.handle(sample, direction: .input)
        },
        onEnd: { [weak self] message in
          guard let self, self.microphoneGeneration == token else { return }
          self.microphoneRunning = false
          self.inputStatus = message
          if let sample = self.inputMeasurement {
            self.inputStatus += String(format: " 最后电平 %.0f dBFS。", sample.rmsDB)
          }
        })
    }
  }
  func stopMicrophone() {
    microphoneGeneration = UUID()
    microphone.stop()
    if microphoneRunning { inputStatus = "测试已停止；结果仅代表本地输入" }
    microphoneRunning = false
  }
  private func handle(_ sample: AudioMeasurement, direction: Direction) {
    audioHistory.append(
      value: sample.discontinuity ? nil : sample.rmsDB, source: direction.rawValue,
      date: sample.date, maximumGap: 2)
    if sample.discontinuity {
      if lastCaptureFault[direction] == nil
        || sample.date.timeIntervalSince(lastCaptureFault[direction]!) > 10
      {
        lastCaptureFault[direction] = sample.date
        receive(
          .init(
            kind: .captureUnavailable, direction: direction, source: direction.rawValue,
            message: "采集时间戳不连续；不能把它直接归为耳机播放中断"))
      }
      return
    }
    if let lastFault = lastCaptureFault[direction], sample.date.timeIntervalSince(lastFault) > 2 {
      lastCaptureFault[direction] = nil
      receive(
        .init(
          kind: .captureRestored, direction: direction, source: direction.rawValue,
          message: "采集时间戳恢复连续；不代表端到端音质正常"))
    }
    if let last = lastAudioEvent[direction], sample.date.timeIntervalSince(last) < 1 { return }
    let kind: EventKind? =
      sample.clippingFraction > 0.02 ? .clipping : sample.suspectGap ? .audioGap : nil
    if let kind {
      lastAudioEvent[direction] = sample.date
      receive(
        .init(
          kind: kind, direction: direction, source: direction.rawValue,
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
      feedback = "演示中不创建真实记录。请先返回实时监测。"
      return
    }
    receive(.init(kind: .userMarked, direction: direction, source: "user", message: "用户手工标记声音异常"))
    feedback = "已记录时间点及近期事件；不包含录音。"
  }
  func runDemo(_ scenario: DemoScenario) {
    if demoScenario == nil {
      save()
      stopCollectors()
    }
    demoScenario = scenario
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
      feedback = "问题记录保存失败：" + error.localizedDescription
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
      feedback = "已导出问题与证据；含设备／应用标识，不含录音。"
    } catch { feedback = "导出失败：" + error.localizedDescription }
  }
}
