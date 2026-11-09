import SonoskopeCore
import SwiftUI

/// Presenting or stepping through the guide never enables capture or requests permission.
struct GettingStartedView: View {
  @Bindable var model: MonitorModel
  var finish: () -> Void
  var openSettings: () -> Void
  @State private var step: OnboardingStep

  init(
    model: MonitorModel, initialStep: OnboardingStep = .welcome,
    finish: @escaping () -> Void, openSettings: @escaping () -> Void
  ) {
    self.model = model
    self.finish = finish
    self.openSettings = openSettings
    _step = State(initialValue: initialStep)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 10) {
        Image(nsImage: BrandAssets.applicationIcon).resizable().frame(width: 30, height: 30)
          .accessibilityHidden(true)
        Text("Sonoskope").font(.headline)
        Spacer()
        Button(L10n.tr("跳过引导"), action: finish).buttonStyle(.link)
      }.padding(.bottom, 24)
      HStack(spacing: 12) {
        ForEach(OnboardingStep.allCases, id: \.self) { item in
          VStack(alignment: .leading, spacing: 7) {
            Capsule().fill(item == step ? Color.accentColor : Color.secondary.opacity(0.2))
              .frame(height: 3)
            Text("\(item.rawValue + 1) · " + item.title).font(.caption)
              .foregroundStyle(item == step ? .primary : .secondary)
              .accessibilityAddTraits(item == step ? .isSelected : [])
          }
        }
      }.padding(.bottom, 24)
      ScrollView {
        Group {
          switch step {
          case .welcome: welcome
          case .monitoring: monitoring
          case .ready: ready
          }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 8)
      }.frame(maxWidth: .infinity, maxHeight: .infinity)
      Divider().padding(.vertical, 16)
      HStack {
        if step == .welcome {
          Button(L10n.tr("先看看演示")) {
            model.runDemo(.correlated)
            finish()
          }
        } else {
          Button(L10n.tr("返回")) { step = OnboardingStep(rawValue: step.rawValue - 1) ?? .welcome }
        }
        Spacer()
        if step == .ready {
          Button(L10n.tr("进入概览"), action: finish).buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        } else {
          Button(L10n.tr("继续")) { step = OnboardingStep(rawValue: step.rawValue + 1) ?? .ready }
            .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
        }
      }
    }.padding(28)
      .frame(minWidth: 580, idealWidth: 640, minHeight: 560, idealHeight: 620)
      .background(Color(nsColor: .windowBackgroundColor))
  }

  private var welcome: some View {
    VStack(alignment: .leading, spacing: 22) {
      heading("声音出问题时，知道先查哪里。", detail: "查看本机声音、设备连接与网络线索，帮助你决定下一步。")
      explanation(
        "随时从菜单栏打开", symbol: "menubar.rectangle", detail: "关闭窗口后仍在菜单栏运行；点击 Sonoskope 图标可重新查看状态。")
      explanation("听到异常，标记当下", symbol: "flag", detail: "点击“刚才声音有问题”，在问题记录中对照当时的本地证据。")
      explanation(
        "保留线索，不保存录音", symbol: "waveform.badge.magnifyingglass",
        detail: "音频采集由你开启。本机读数不能证明远端听感或耳机实际发声。")
    }
  }

  private var monitoring: some View {
    VStack(alignment: .leading, spacing: 16) {
      heading("由你选择采集范围", detail: "可全部跳过，之后在设置中开启。仅在你开启相应功能时请求权限。")
      if model.demoScenario != nil || model.paused {
        Text(model.subtitle).font(.callout).foregroundStyle(.secondary)
        Button(model.demoScenario != nil ? L10n.tr("返回实时监测") : L10n.tr("恢复监测")) {
          model.togglePause()
        }
      }
      VStack(alignment: .leading, spacing: 6) {
        Label(L10n.tr("设备连接状态"), systemImage: "hifispeaker.and.homepodmini").font(.headline)
        Text(L10n.tr("只观察设备是否可用，不采集音频。"))
          .font(.callout).foregroundStyle(.secondary)
      }
      Divider()
      VStack(alignment: .leading, spacing: 7) {
        Toggle(
          L10n.tr("分析应用输出音频"),
          isOn: Binding(
            get: { model.outputEnabled }, set: { model.setOutputEnabled($0) })
        )
        .font(.headline).toggleStyle(.switch)
        .disabled(model.demoScenario != nil || model.paused)
        .accessibilityIdentifier("onboarding-output")
        Text(L10n.tr("开启时请求系统音频录制权限。仅计算指标，不保存或上传录音。多应用混音无法区分参会者。"))
          .font(.caption).foregroundStyle(.secondary)
        Text(model.outputReading).font(.caption)
      }
      Divider()
      VStack(alignment: .leading, spacing: 7) {
        Toggle(
          L10n.tr("自动监测麦克风电平"),
          isOn: Binding(
            get: { model.automaticInputEnabled }, set: { model.setAutomaticInputEnabled($0) })
        )
        .font(.headline).toggleStyle(.switch)
        .disabled(model.demoScenario != nil || model.paused)
        .accessibilityIdentifier("onboarding-microphone")
        Text(L10n.tr("其他应用使用输入设备时采集，停止使用后关闭。会打开麦克风，可能改变蓝牙模式；会议静音不一定停止采集。"))
          .font(.caption).foregroundStyle(.secondary)
        Text(model.inputReading).font(.caption)
        if model.automaticInputNeedsPermission { Button(L10n.tr("打开设置"), action: openSettings) }
      }
    }
  }

  private var ready: some View {
    VStack(alignment: .leading, spacing: 20) {
      heading("准备好了", detail: "点击菜单栏图标回到概览。需要测试时，可主动进行一次 10 秒麦克风测试。")
      VStack(alignment: .leading, spacing: 14) {
        summary("麦克风输入", value: model.inputReading)
        Divider()
        summary("应用输出", value: model.outputReading)
      }.padding(16).background(
        Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
      Toggle(
        L10n.tr("登录后启动"), isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) })
      )
      .toggleStyle(.switch)
      Text(L10n.tr("在菜单栏运行。点击图标或问题提醒可打开音频状态。"))
        .font(.caption).foregroundStyle(.secondary)
      if !model.feedback.isEmpty { Text(model.feedback).font(.caption).foregroundStyle(.secondary) }
      Text(L10n.tr("可从菜单栏菜单再次打开使用指南。"))
        .font(.caption).foregroundStyle(.secondary)
    }
  }

  private func heading(_ title: LocalizedText, detail: LocalizedText) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(L10n.tr(title)).font(.title2.weight(.semibold)).fixedSize(
        horizontal: false, vertical: true)
      Text(L10n.tr(detail)).font(.callout).foregroundStyle(.secondary).fixedSize(
        horizontal: false, vertical: true)
    }
  }
  private func explanation(_ title: LocalizedText, symbol: String, detail: LocalizedText)
    -> some View
  {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: symbol).font(.title3).frame(width: 26).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 5) {
        Text(L10n.tr(title)).font(.headline)
        Text(L10n.tr(detail)).font(.callout).foregroundStyle(.secondary).fixedSize(
          horizontal: false, vertical: true)
      }
    }
  }
  private func summary(_ title: LocalizedText, value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(L10n.tr(title)).font(.callout.weight(.medium))
      Text(value).font(.callout).foregroundStyle(.secondary).fixedSize(
        horizontal: false, vertical: true)
    }
  }
}
