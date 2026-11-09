import SonoskopeCore
import SwiftUI

struct StatusView: View {
  @Bindable var model: MonitorModel
  var openSettings: () -> Void
  @State private var confirmMicrophone = false
  @State private var showDetails = false
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Label("Sonoskope", systemImage: "waveform.path").font(.headline)
        Spacer()
        if model.demoScenario != nil {
          Text(L10n.tr("模拟数据")).font(.caption).foregroundStyle(.orange)
        }
        Button(action: openSettings) { Image(systemName: "gearshape") }.help(L10n.tr("设置"))
          .accessibilityLabel(L10n.tr("打开设置"))
      }.padding(18)
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          VStack(alignment: .leading, spacing: 8) {
            Text(model.title).font(.title2.weight(.semibold)).accessibilityIdentifier(
              "health-title")
            Text(model.subtitle).font(.callout).foregroundStyle(.secondary)
          }
          if let scenario = model.demoScenario {
            HStack {
              Text(scenario.label).font(.callout)
              Spacer()
              Button(L10n.tr("返回实时监测")) { model.exitDemo() }
            }.padding(10).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
          }
          VStack(spacing: 14) {
            DirectionRow(
              title: L10n.tr("我的声音"), icon: "mic", status: model.inputReading,
              detail: model.demoScenario == nil
                ? L10n.tr("系统默认：") + (model.hardware.input?.name ?? L10n.tr("无可用输入"))
                : L10n.tr("演示不采集麦克风"))
            Divider()
            DirectionRow(
              title: L10n.tr("我听到的声音"), icon: "headphones", status: model.outputReading,
              detail: model.demoScenario == nil
                ? L10n.tr("系统默认：") + (model.hardware.output?.name ?? L10n.tr("无可用输出"))
                : L10n.tr("演示不采集应用输出"))
          }
          Divider()
          VStack(alignment: .leading, spacing: 10) {
            EvidenceRow(label: L10n.tr("蓝牙"), value: bluetoothSummary)
            EvidenceRow(
              label: L10n.tr("网络"),
              value: model.demoScenario == nil ? model.network.probe : L10n.tr("模拟状态见问题依据"))
            if model.demoScenario == nil {
              Text(model.network.path).font(.caption).foregroundStyle(.secondary)
            }
          }
          if let incident = model.selectedIncident {
            IncidentView(incident: incident)
          } else {
            Text(L10n.tr("尚无问题记录。没有发现异常，不代表整条通话链路已验证正常。"))
              .font(.callout).foregroundStyle(.secondary)
          }
          TelemetryCharts(
            audio: model.audioChartPoints, network: model.networkChartPoints,
            endingAt: model.chartEnd, incidentAt: model.selectedIncident?.started,
            audioEnabled: model.outputEnabled || model.microphoneRunning
              || model.demoScenario != nil,
            networkEnabled: model.networkEnabled || model.demoScenario != nil)
          if model.incidents.count > 1 {
            Picker(
              L10n.tr("问题记录"),
              selection: Binding(
                get: { model.selectedIncident?.id }, set: { model.selectedIncidentID = $0 })
            ) {
              ForEach(model.incidents) { item in
                Text(
                  item.started.uiFormatted(date: .omitted, time: .standard) + " · "
                    + item.title.localized
                )
                .tag(Optional(item.id))
              }
            }
          }
          DisclosureGroup(L10n.tr("当前采集范围与详细指标"), isExpanded: $showDetails) {
            details.padding(.top, 8)
          }.font(.callout)
          if !model.feedback.isEmpty {
            Text(model.feedback).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier(
              "feedback")
          }
        }.padding(20)
      }
      Divider()
      VStack(spacing: 10) {
        HStack {
          Menu(L10n.tr("刚才声音有问题")) {
            Button(L10n.tr("别人听不清我")) { model.mark(.input) }
            Button(L10n.tr("我听不清别人")) { model.mark(.output) }
          }
          Spacer()
          if model.microphoneRunning {
            Button(L10n.tr("停止麦克风测试")) { model.stopMicrophone() }
          } else {
            Button(L10n.tr("测试我的声音…")) { confirmMicrophone = true }.disabled(
              model.paused || model.demoScenario != nil)
          }
        }
        HStack {
          Button(
            model.demoScenario != nil
              ? L10n.tr("结束演示") : model.paused ? L10n.tr("恢复监测") : L10n.tr("暂停监测")
          ) {
            model.togglePause()
          }
          .buttonStyle(.link)
          Spacer()
          Button(L10n.tr("导出问题记录…")) { model.exportReport() }.buttonStyle(.link).disabled(
            model.incidents.isEmpty)
        }.font(.caption)
      }.padding(16)
    }
    .frame(minWidth: 450, idealWidth: 520, minHeight: 520, idealHeight: 730)
    .background(Color(nsColor: .windowBackgroundColor))
    .confirmationDialog(
      L10n.tr("开始 10 秒本地麦克风测试？"), isPresented: $confirmMicrophone, titleVisibility: .visible
    ) {
      Button(L10n.tr("开始 10 秒测试")) { model.startMicrophone() }
      Button(L10n.tr("取消"), role: .cancel) {}
    } message: {
      Text(L10n.tr("将使用系统默认麦克风，可能改变蓝牙耳机模式。请先安静约 2 秒，再正常讲话。结果仅代表到达 Mac 的声音；不保存录音。"))
    }
  }
  private var bluetoothSummary: String {
    guard model.demoScenario == nil else { return L10n.tr("模拟状态见问题依据") }
    let audioBluetooth = model.hardware.devices.filter { $0.isBluetooth }
    guard !audioBluetooth.isEmpty else { return L10n.tr("未发现蓝牙音频设备") }
    if !model.bluetoothEnabled { return L10n.tr("音频设备可见 · RSSI 未启用") }
    if model.hardware.bluetooth.isEmpty { return L10n.tr("信号读数不可用／未授权") }
    return model.hardware.bluetooth.map { item in
      item.name + " " + (item.rssi.map { "\($0) dBm" } ?? L10n.tr("RSSI 不可用"))
    }.joined(separator: L10n.tr("；"))
  }
  private func names(_ ids: [UInt32]) -> String {
    let names = ids.compactMap { id in model.hardware.devices.first { $0.id == id }?.name }
    return names.isEmpty ? L10n.tr("未返回") : names.joined(separator: L10n.tr("、"))
  }
  @ViewBuilder private var details: some View {
    if model.demoScenario != nil {
      Text(L10n.tr("演示事件与真实采集隔离，不会保存到真实历史或发送系统通知。"))
    } else {
      VStack(alignment: .leading, spacing: 8) {
        Text(
          L10n.tr("输入：仅主动测试。应用输出：") + (model.outputEnabled ? L10n.tr("已开启") : L10n.tr("未开启"))
            + L10n.tr("。"))
        Text(L10n.tr("设备每 2 秒轮询，短于轮询间隔的断连可能漏检。"))
        Text(L10n.tr("探测：www.apple.com:443，每次完成后间隔 5 秒；连接耗时包含 DNS，不是会议延迟。"))
        Text(model.network.wifi)
        ForEach(model.hardware.devices) { device in
          Text(
            L10n.tr(
              "\(device.name) · \(device.transport) · \(Int(device.sampleRate)) Hz · 输入 \(device.inputChannels) / 输出 \(device.outputChannels) 声道"
            )
          )
        }
        if let measurement = model.outputMeasurement {
          Text(
            String(
              format: L10n.tr("输出峰值 %.1f dBFS · 近满幅 %.2f%% · %@"), measurement.peakDB,
              measurement.clippingFraction * 100,
              measurement.date.uiFormatted(date: .omitted, time: .standard)))
        }
        Text(L10n.tr("当前音频进程")).fontWeight(.medium)
        ForEach(model.hardware.processes.filter { $0.inputActive || $0.outputActive }) { process in
          VStack(alignment: .leading, spacing: 2) {
            Text(
              L10n.tr(
                "\(process.name) · PID \(process.pid) · 输入 \(process.inputActive ? L10n.tr("活动") : L10n.tr("无")) / 输出 \(process.outputActive ? L10n.tr("活动") : L10n.tr("无"))"
              )
            )
            Text(
              L10n.tr("输入关联：") + names(process.inputDevices) + L10n.tr("；输出关联：")
                + names(process.outputDevices))
          }
        }
        Text(L10n.tr("进程输入活动不等于正在讲话；默认输入不一定是会议应用所选麦克风。输入／输出关联设备仅按系统实际返回列表显示。"))
      }.font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
    }
  }
}

private struct DirectionRow: View {
  let title: String
  let icon: String
  let status: String
  let detail: String
  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: icon).font(.title3).frame(width: 24).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.callout.weight(.medium))
        Text(status).font(.callout)
        Text(detail).font(.caption).foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }
  }
}
private struct EvidenceRow: View {
  let label: String
  let value: String
  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(label).foregroundStyle(.secondary).frame(minWidth: 68, alignment: .leading)
      Text(value).frame(maxWidth: .infinity, alignment: .trailing)
    }.font(.callout)
  }
}
private struct IncidentView: View {
  let incident: Incident
  @State private var expanded = false
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(L10n.tr("最近问题")).font(.caption).foregroundStyle(.secondary)
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
  var body: some View {
    Form {
      Section(L10n.tr("运行")) {
        Toggle(
          L10n.tr("登录后启动"), isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
        Text(L10n.tr("在菜单栏运行。点击图标或问题提醒可打开音频状态。"))
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
        Toggle(L10n.tr("读取已连接蓝牙设备的信号强度"), isOn: $model.bluetoothEnabled).onChange(
          of: model.bluetoothEnabled
        ) { _, _ in model.updateSettings() }
        Text(L10n.tr("可能请求蓝牙权限；部分设备不提供读数。只作辅助证据，不计算蓝牙音质分数。"))
        Toggle(L10n.tr("轻量网络探测"), isOn: $model.networkEnabled).onChange(of: model.networkEnabled) {
          _, _ in
          model.updateSettings()
        }
        Text(L10n.tr("与 www.apple.com:443 建立 TCP 测试连接，每次完成后间隔 5 秒。不上传音频，不代表会议媒体质量。"))
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
            "Sonoskope \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.2") · macOS 14.2+\n系统层诊断；不使用 Zoom／Teams 接口。"
          )
        ).font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .frame(minWidth: 480, idealWidth: 540, minHeight: 550, idealHeight: 700)
  }
}
