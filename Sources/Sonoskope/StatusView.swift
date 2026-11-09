import SonoskopeCore
import SwiftUI

struct StatusView: View {
  @Bindable var model: MonitorModel
  @Bindable var navigation: StatusNavigation
  var openSettings: () -> Void
  var updater: SoftwareUpdater?
  var openUpdates: () -> Void
  @State private var confirmMicrophone = false
  @State private var sheet: DetailSheet?

  private enum DetailSheet: String, Identifiable {
    case scope
    var id: String { rawValue }
  }

  init(model: MonitorModel, navigation: StatusNavigation? = nil, updater: SoftwareUpdater? = nil,
    openUpdates: @escaping () -> Void = {}, openSettings: @escaping () -> Void)
  {
    self.model = model
    self.navigation = navigation ?? StatusNavigation()
    self.openSettings = openSettings
    self.updater = updater
    self.openUpdates = openUpdates
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      Picker(L10n.tr("音频状态"), selection: $navigation.section) {
        ForEach(StatusSection.allCases, id: \.self) { section in
          Text(section.title).tag(section)
        }
      }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 20).padding(.vertical, 12)
      Group {
        switch navigation.section {
        case .overview:
          // The fallback keeps long device names, system errors and larger text
          // reachable; ordinary states fit the default window without scrolling.
          ViewThatFits(in: .vertical) {
            overview.fixedSize(horizontal: false, vertical: true)
            ScrollView { overview }
          }
        case .trends:
          ScrollView { trends.padding(20) }
        case .issues:
          issues
        }
      }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      footer
    }
    .frame(minWidth: 580, idealWidth: 640, minHeight: 580, idealHeight: 620)
    .background(Color(nsColor: .windowBackgroundColor))
    .onChange(of: model.demoScenario) { _, _ in
      // Drop a record from the other mode, but preserve a real notification's
      // explicit destination when it exits the demo and opens live history.
      if let id = navigation.incidentID, !model.incidents.contains(where: { $0.id == id }) {
        navigation.showOverview()
      }
    }
    .sheet(item: $sheet) { _ in MonitoringScopeView(model: model) }
    .confirmationDialog(
      L10n.tr("开始 10 秒本地麦克风测试？"), isPresented: $confirmMicrophone,
      titleVisibility: .visible
    ) {
      Button(L10n.tr("开始 10 秒测试")) { model.startMicrophone() }
      Button(L10n.tr("取消"), role: .cancel) {}
    } message: {
      Text(L10n.tr("将使用系统默认麦克风，可能改变蓝牙耳机模式。请先安静约 2 秒，再正常讲话。结果仅代表到达 Mac 的声音；不保存录音。"))
    }
  }

  private var header: some View {
    HStack(spacing: 10) {
      Image(nsImage: BrandAssets.applicationIcon).resizable().frame(width: 26, height: 26)
        .accessibilityHidden(true)
      Text("Sonoskope").font(.headline)
      Spacer()
      if updater?.isReady == true {
        Button(L10n.tr("更新已准备好"), action: openUpdates).controlSize(.small)
      }
      if model.demoScenario != nil {
        Label(L10n.tr("模拟数据"), systemImage: "play.circle").font(.caption).foregroundStyle(.orange)
      }
      Button {
        sheet = .scope
      } label: {
        Image(systemName: "info.circle")
      }
      .help(L10n.tr("当前采集范围与详细指标"))
      .accessibilityLabel(L10n.tr("当前采集范围与详细指标"))
      Button(action: openSettings) { Image(systemName: "gearshape") }
        .help(L10n.tr("设置")).accessibilityLabel(L10n.tr("打开设置"))
    }.padding(.horizontal, 20).padding(.vertical, 12)
  }

  private var overview: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 6) {
        Text(model.title).font(.title2.weight(.semibold)).fixedSize(
          horizontal: false, vertical: true
        )
        .accessibilityIdentifier("health-title")
        Text(model.subtitle).font(.callout).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      if let scenario = model.demoScenario {
        HStack {
          Text(scenario.label).font(.callout)
          Spacer()
          Button(L10n.tr("返回实时监测")) {
            model.exitDemo()
            navigation.showOverview()
          }
        }
      }
      HStack(alignment: .top, spacing: 12) {
        DirectionSummary(
          title: L10n.tr("麦克风输入"), icon: "mic", reading: model.inputReading,
          device: model.inputDeviceDetail,
          scope: model.inputApplicationContext ?? L10n.tr("仅本机输入；不代表远端听感。"))
        DirectionSummary(
          title: L10n.tr("应用输出"), icon: "headphones", reading: model.outputReading,
          device: outputDevice,
          scope: outputScope)
      }
      if model.automaticInputNeedsPermission {
        HStack {
          Label(L10n.tr("麦克风权限不可用"), systemImage: "mic.slash")
            .font(.caption).foregroundStyle(.secondary)
          Spacer()
          Button(L10n.tr("打开设置"), action: openSettings)
        }
      }
      HStack(alignment: .top, spacing: 20) {
        connection(
          symbol: "antenna.radiowaves.left.and.right", title: L10n.tr("蓝牙"), value: bluetoothSummary
        )
        connection(
          symbol: "network", title: L10n.tr("网络"),
          value: model.demoScenario == nil ? model.network.probe : L10n.tr("模拟状态见问题依据"))
      }
      if let incident = model.incidents.first {
        HStack(alignment: .center, spacing: 12) {
          VStack(alignment: .leading, spacing: 5) {
            Text(
              L10n.tr("最近问题") + " · "
                + incident.started.uiFormatted(date: .omitted, time: .shortened)
            )
            .font(.caption).foregroundStyle(.secondary)
            Text(incident.title.localized).font(.callout.weight(.semibold))
            Text(incident.nextStep.localized).font(.caption).foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          Spacer(minLength: 0)
          Button(L10n.tr("查看依据")) { navigation.showIncident(incident.id) }
            .fixedSize()
        }.padding(14).background(
          Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.08)))
      } else {
        Text(L10n.tr("尚无问题记录。没有发现异常，不代表整条通话链路已验证正常。"))
          .font(.callout).foregroundStyle(.secondary)
      }
    }.padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 16)
  }

  private var trends: some View {
    VStack(alignment: .leading, spacing: 14) {
      if model.paused && model.demoScenario == nil {
        Text(model.subtitle).font(.caption).foregroundStyle(.secondary)
      }
      if let incident = chartIncident {
        Text(
          L10n.tr("问题时间") + " · "
            + incident.started.uiFormatted(date: .abbreviated, time: .standard)
        )
        .font(.caption).foregroundStyle(.secondary)
        if incident.started < model.chartEnd.addingTimeInterval(-60)
          || incident.started > model.chartEnd
        {
          Text(L10n.tr("该问题不在最近 60 秒内；下方曲线不代表当时的数据。"))
            .font(.caption).foregroundStyle(.secondary)
        }
      }
      TelemetryCharts(
        audio: model.audioChartPoints, network: model.networkChartPoints,
        endingAt: model.chartEnd, incidentAt: chartIncident?.started,
        audioEnabled: model.outputEnabled || model.microphoneRunning || model.automaticInputEnabled
          || model.demoScenario != nil,
        networkEnabled: model.networkEnabled || model.demoScenario != nil,
        audioHeight: 120, networkHeight: 80)
      Button(L10n.tr("当前采集范围与详细指标")) { sheet = .scope }.buttonStyle(.link)
    }
  }

  private var issues: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        if navigation.incidentID != nil {
          Button {
            navigation.incidentID = nil
          } label: {
            Label(L10n.tr("所有记录"), systemImage: "chevron.left")
          }
        } else {
          Text(L10n.tr("历史事件，与当前状态分开显示。"))
            .font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        if chartIncident != nil {
          Button(L10n.tr("查看趋势")) { navigation.section = .trends }
        }
        Button(L10n.tr("导出问题记录…")) { model.exportReport() }.disabled(model.incidents.isEmpty)
      }
      if let id = navigation.incidentID {
        if let incident = model.incidents.first(where: { $0.id == id }) {
          ScrollView { IncidentDetailView(incident: incident).id(id) }
        } else {
          ContentUnavailableView(L10n.tr("这条记录已不再保留"), systemImage: "clock.badge.questionmark")
        }
      } else if model.incidents.isEmpty {
        ContentUnavailableView(L10n.tr("尚无问题记录"), systemImage: "waveform.path")
      } else {
        ScrollView {
          LazyVStack(spacing: 8) {
            ForEach(model.incidents) { incident in
              Button {
                navigation.showIncident(incident.id)
              } label: {
                HStack(alignment: .top, spacing: 14) {
                  Text(incident.started.uiFormatted(date: .omitted, time: .shortened))
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .leading)
                  VStack(alignment: .leading, spacing: 5) {
                    Text(incident.title.localized).font(.callout.weight(.semibold))
                    Text(
                      incident.confidenceLabel + " · "
                        + (incident.isActive ? L10n.tr("待确认／持续观察") : L10n.tr("事件已结束"))
                    )
                    .font(.caption).foregroundStyle(.secondary)
                    Text(incident.explanation.localized).font(.caption).foregroundStyle(.secondary)
                  }
                  Spacer(minLength: 0)
                  Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                  .background(
                    Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10)
                  )
                  .contentShape(Rectangle())
              }.buttonStyle(.plain)
            }
          }
        }
      }
    }.padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 16)
  }

  private var footer: some View {
    VStack(alignment: .leading, spacing: 8) {
      Divider()
      HStack {
        Menu(L10n.tr("刚才声音有问题")) {
          Button(L10n.tr("别人听不清我")) { mark(.input) }
          Button(L10n.tr("我听不清别人")) { mark(.output) }
        }.fixedSize()
        if model.automaticInputEnabled {
          Menu(L10n.tr("自动麦克风监测")) {
            Button(L10n.tr("自动监测设置…"), action: openSettings)
            Button(L10n.tr("关闭自动监测")) { model.setAutomaticInputEnabled(false) }
          }
        } else if model.microphoneRunning {
          Button(L10n.tr("停止麦克风测试")) { model.stopMicrophone() }
        } else {
          Button(L10n.tr("10 秒测试…")) { confirmMicrophone = true }
            .disabled(model.paused || model.demoScenario != nil)
        }
        Spacer(minLength: 4)
        Button(
          model.demoScenario != nil
            ? L10n.tr("结束演示") : model.paused ? L10n.tr("恢复监测") : L10n.tr("暂停监测")
        ) {
          model.togglePause()
        }.buttonStyle(.link).fixedSize()
      }.padding(.top, 4)
      Text(model.feedback.isEmpty ? L10n.tr("只保留诊断事件和数值指标，不保存原始音频。") : model.feedback)
        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        .accessibilityIdentifier("feedback")
    }.padding(.horizontal, 20).padding(.bottom, 14)
  }

  private func mark(_ direction: Direction) {
    model.mark(direction)
    if model.demoScenario == nil, let id = model.selectedIncidentID { navigation.showIncident(id) }
  }

  private var chartIncident: Incident? {
    guard let id = navigation.incidentID else { return nil }
    return model.incidents.first { $0.id == id }
  }

  private func connection(symbol: String, title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Label(title, systemImage: symbol).font(.caption.weight(.medium))
      Text(value).font(.caption).foregroundStyle(.secondary).fixedSize(
        horizontal: false, vertical: true)
    }.frame(maxWidth: .infinity, alignment: .leading)
  }

  private var outputDevice: String {
    guard model.demoScenario == nil else { return L10n.tr("演示不采集应用输出") }
    return L10n.tr("系统默认输出") + " · " + (model.hardware.output?.name ?? L10n.tr("无可用输出"))
  }

  private var outputScope: String {
    guard model.demoScenario == nil else { return L10n.tr("应用数字输出；不代表耳机实际发声。") }
    let scope =
      model.selectedProcess == 0
      ? L10n.tr("所有应用输出（排除 Sonoskope）")
      : model.hardware.processes.first(where: { $0.id == model.selectedProcess })?.name
        ?? L10n.tr("所选音频进程已退出，请重新选择")
    return L10n.tr("分析范围") + " · " + scope
  }

  private var bluetoothSummary: String {
    guard model.demoScenario == nil else { return L10n.tr("模拟状态见问题依据") }
    guard model.hardware.devices.contains(where: \.isBluetooth) else { return L10n.tr("未发现蓝牙音频设备") }
    if !model.bluetoothEnabled { return L10n.tr("音频设备可见 · RSSI 未启用") }
    if model.hardware.bluetooth.isEmpty { return L10n.tr("信号读数不可用／未授权") }
    return model.hardware.bluetooth.map {
      $0.name + " " + ($0.rssi.map { "\($0) dBm" } ?? L10n.tr("RSSI 不可用"))
    }.joined(separator: L10n.tr("；"))
  }
}

private struct DirectionSummary: View {
  let title: String
  let icon: String
  let reading: String
  let device: String
  let scope: String
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(title, systemImage: icon).font(.callout.weight(.medium))
      Text(reading).font(.callout.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
      Text(device).font(.caption).foregroundStyle(.secondary).lineLimit(2).help(device)
      Text(scope).font(.caption).foregroundStyle(.secondary).fixedSize(
        horizontal: false, vertical: true)
    }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
      .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
      .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.08)))
  }
}
