import SonoskopeCore
import SwiftUI

struct IncidentDetailView: View {
  let incident: Incident
  @State private var expanded = true
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(incident.confidenceLabel).font(.caption).foregroundStyle(.secondary)
        Spacer()
        Text(incident.isActive ? L10n.tr("待确认／持续观察") : L10n.tr("事件已结束")).font(.caption)
          .foregroundStyle(
            incident.isActive ? .orange : .secondary)
      }
      Text(incident.title.localized).font(.headline)
      Text(
        incident.started.uiFormatted(date: .abbreviated, time: .standard) + " · "
          + incident.direction.label
      ).font(.caption).foregroundStyle(.secondary)
      Text(incident.explanation.localized).font(.callout)
      if let recovered = incident.recovered {
        Text(
          L10n.tr("记录更新于 ") + recovered.uiFormatted(date: .omitted, time: .standard) + " · "
            + (incident.endReason?.localized ?? L10n.tr("观察结束")) + L10n.tr("。不代表端到端音质已验证。")
        ).font(.caption).foregroundStyle(.secondary)
      }
      DisclosureGroup(L10n.tr("查看依据（\(incident.evidence.count)）"), isExpanded: $expanded) {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(incident.evidence) { event in
            Text(
              event.date.uiFormatted(date: .omitted, time: .standard) + " · "
                + event.message.localized)
          }
        }.font(.caption).textSelection(.enabled).padding(.top, 8)
          .frame(maxWidth: .infinity, alignment: .leading)
      }.font(.callout)
      Divider()
      Text(L10n.tr("建议下一步")).font(.caption).foregroundStyle(.secondary)
      Text(incident.nextStep.localized).font(.callout)
    }.padding(16).background(
      Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
  }
}

struct SettingsView: View {
  @Bindable var model: MonitorModel
  var updater: SoftwareUpdater? = nil
  var openUpdates: () -> Void = {}
  var body: some View {
    Form {
      if let updater {
        Section(L10n.tr("软件更新")) {
          Toggle(L10n.tr("自动检查并下载更新"), isOn: Binding(get: { updater.automatic }, set: updater.setAutomatic))
          HStack {
            Text(updater.status).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button(L10n.tr(updater.isReady ? "更新已准备好" : "检查更新…"), action: openUpdates)
          }
        }
      }
      Section(L10n.tr("运行")) {
        Toggle(
          L10n.tr("登录后启动"), isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
        Text(L10n.tr("在菜单栏运行。点击图标或问题提醒可打开音频状态。"))
      }
      Section(L10n.tr("监控浮窗")) {
        Toggle(L10n.tr("有电平活动时显示浮窗"), isOn: Binding(
          get: { model.floatingMonitorEnabled }, set: model.setFloatingMonitorEnabled))
          .disabled(model.demoScenario != nil)
        if model.floatingMonitorEnabled && model.floatingMonitorDismissed {
          Button(L10n.tr("重新显示浮窗")) { model.setFloatingMonitorEnabled(true) }
            .disabled(model.demoScenario != nil)
        }
        HStack {
          Text(L10n.tr("背景不透明度"))
          Slider(value: Binding(get: { model.floatingMonitorOpacity }, set: model.setFloatingMonitorOpacity),
            in: 0.4...1, step: 0.05)
            .accessibilityLabel(L10n.tr("背景不透明度"))
          Text("\(Int((model.floatingMonitorOpacity * 100).rounded()))%").monospacedDigit()
            .frame(width: 42, alignment: .trailing)
        }.disabled(model.demoScenario != nil)
        Text(L10n.tr("默认关闭。开关设置会保留。关闭浮窗仅在本次运行中隐藏，不会关闭开关或停止监测；可重新显示，或在下次启动后自动显示。"))
      }
      Section(L10n.tr("麦克风")) {
        Toggle(
          L10n.tr("自动监测麦克风电平"),
          isOn: Binding(
            get: { model.automaticInputEnabled }, set: { model.setAutomaticInputEnabled($0) })
        )
        .disabled(model.demoScenario != nil && !model.automaticInputEnabled)
        Text(L10n.tr("仅在其他应用使用输入设备时采集，停止使用后自动关闭。开启后记住此设置；暂停、睡眠和演示期间停止采集。"))
        Text(L10n.tr("会实际打开麦克风，可能改变蓝牙耳机模式。不保存或上传录音；会议静音按钮不一定关闭输入流。"))
        Text(model.inputReading).font(.caption).foregroundStyle(.secondary)
        if model.automaticInputNeedsPermission {
          Button(L10n.tr("重新检查麦克风权限")) { model.setAutomaticInputEnabled(true) }
          Text(L10n.tr("若未弹出授权提示，请到系统设置 → 隐私与安全性 → 麦克风中允许 Sonoskope。"))
        }
      }
      Section(L10n.tr("采集范围")) {
        Toggle(
          L10n.tr("分析应用输出音频"),
          isOn: Binding(get: { model.outputEnabled }, set: { model.setOutputEnabled($0) }))
        Picker(
          L10n.tr("分析范围"),
          selection: Binding(get: { model.selectedProcess }, set: { model.selectProcess($0) })
        ) {
          Text(L10n.tr("所有应用输出（排除 Sonoskope）")).tag(UInt32(0))
          ForEach(model.hardware.processes) { process in
            Text("\(process.name) · PID \(process.pid)").tag(process.id)
          }
        }.disabled(model.demoScenario != nil)
        Text(L10n.tr("开启时请求系统音频录制权限。仅计算指标，不保存或上传录音。多应用混音无法区分参会者。"))
        Picker(L10n.tr("输出静音后自动暂停"), selection: Binding(
          get: { model.outputSilenceMinutes }, set: model.setOutputSilenceMinutes
        )) {
          Text(L10n.tr("不自动暂停")).tag(0)
          ForEach(1...60, id: \.self) { minutes in
            Text(L10n.tr("\(minutes) 分钟")).tag(minutes)
          }
        }.disabled(model.demoScenario != nil)
        Text(L10n.tr("默认 5 分钟。连续收到近零输出电平后暂停全部监测，需手动恢复；无数据不算静音。"))
        Toggle(L10n.tr("读取已连接蓝牙设备的信号强度"), isOn: $model.bluetoothEnabled).onChange(
          of: model.bluetoothEnabled
        ) { _, _ in model.updateSettings() }
        Text(L10n.tr("可能请求蓝牙权限；部分设备不提供读数。只作辅助证据，不计算蓝牙音质分数。"))
        Toggle(L10n.tr("轻量网络探测"), isOn: $model.networkEnabled).onChange(of: model.networkEnabled) {
          _, _ in
          model.updateSettings()
        }
        Text(L10n.tr("仅在采集到活跃输入或输出电平时进行 TCP 探测；静音或无新数据时待命。不上传音频，不代表会议媒体质量。"))
      }
      Section(L10n.tr("提醒")) {
        Toggle(L10n.tr("明确中断或持续疑似异常时提醒"), isOn: $model.notificationsEnabled).onChange(
          of: model.notificationsEnabled
        ) { _, enabled in
          model.updateSettings()
          if enabled { model.requestNotifications() }
        }
        Text(model.notificationStatus)
      }
      Section(L10n.tr("记录")) {
        Picker(L10n.tr("保留问题记录"), selection: $model.retentionHours) {
          Text(L10n.tr("仅当前运行")).tag(0)
          Text(L10n.tr("24 小时")).tag(24)
          Text(L10n.tr("7 天")).tag(168)
        }.onChange(of: model.retentionHours) { _, _ in model.updateSettings() }
        Text(L10n.tr("最多 100 条问题。可能含设备／应用标识与时间，不含原始音频。"))
        Button(L10n.tr("清除问题记录"), role: .destructive) { model.clearHistory() }
      }
      Section(L10n.tr("测试与演示")) {
        Menu(L10n.tr("选择模拟场景")) {
          ForEach(DemoScenario.allCases) { scenario in
            Button(scenario.label) { model.runDemo(scenario) }
          }
        }
        if model.demoScenario != nil { Button(L10n.tr("结束演示，返回实时监测")) { model.exitDemo() } }
        Text(L10n.tr("场景回放会暂停真实采集，不写入历史，不发送系统提醒。麦克风测试请从状态窗口主动发起。"))
      }
      if !model.feedback.isEmpty { Section { Text(model.feedback) } }
      Section {
        Text(
          L10n.tr(
            "Sonoskope \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.6") · macOS 14.2+\n系统层诊断；不使用 Zoom／Teams 接口。"
          )
        ).font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .frame(minWidth: 480, idealWidth: 540, minHeight: 550, idealHeight: 700)
  }
}
