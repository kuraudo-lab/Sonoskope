import SonoskopeCore
import SwiftUI

/// Merely presenting this view never starts audio capture or requests permission.
struct GettingStartedView: View {
  @Bindable var model: MonitorModel
  var finish: () -> Void
  var openSettings: () -> Void
  @State private var confirmMicrophone = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        HStack(spacing: 14) {
          Image(nsImage: BrandAssets.applicationIcon).resizable().frame(width: 52, height: 52)
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 5) {
            Text(L10n.tr("从这里开始排查声音")).font(.title2.bold())
            Text(L10n.tr("选择你想检查的内容，采集由你决定。"))
              .foregroundStyle(.secondary)
          }
        }
        Text(L10n.tr("设备和网络路径监测无需采集音频。声音曲线需要你开启相应分析；空白不代表音频正常。"))
          .font(.callout).foregroundStyle(.secondary)
        choice(
          title: "检查麦克风", symbol: "mic",
          detail: "进行 10 秒本地测试，查看麦克风是否收到声音。需要麦克风权限，可能改变蓝牙耳机模式。"
        ) {
          Button(L10n.tr("10 秒测试…")) { confirmMicrophone = true }
            .disabled(
              model.paused || model.demoScenario != nil || model.microphoneRunning
                || model.automaticInputEnabled)
          if model.automaticInputEnabled {
            Text(L10n.tr("自动麦克风监测已开启；可在设置中管理。"))
              .font(.caption).foregroundStyle(.secondary)
            Button(L10n.tr("打开设置"), action: openSettings)
          }
        }
        choice(
          title: "分析应用声音", symbol: "waveform",
          detail: "开启后分析应用的数字输出，系统可能请求音频录制权限。默认分析所有应用输出，不代表耳机实际发声。"
        ) {
          Button(L10n.tr("开启分析并查看状态")) {
            model.setOutputEnabled(true)
            finish()
          }.disabled(model.paused || model.demoScenario != nil)
        }
        choice(
          title: "先看看演示", symbol: "play.rectangle",
          detail: "用模拟场景了解图表和问题证据。不会打开麦克风、采集应用声音或写入真实问题历史。"
        ) {
          Button(L10n.tr("查看演示")) {
            model.runDemo(.correlated)
            finish()
          }
        }
        Text(L10n.tr("只保留诊断事件和数值指标，不保存原始音频。"))
          .font(.caption).foregroundStyle(.secondary)
        HStack {
          Button(L10n.tr("先查看状态"), action: finish)
          Spacer()
          Text(L10n.tr("可从菜单栏菜单再次打开使用指南。"))
            .font(.caption).foregroundStyle(.secondary)
        }
      }.padding(28)
    }
    .frame(minWidth: 540, idealWidth: 600, minHeight: 600, idealHeight: 710)
    .background(Color(nsColor: .windowBackgroundColor))
    .confirmationDialog(
      L10n.tr("开始 10 秒本地麦克风测试？"), isPresented: $confirmMicrophone,
      titleVisibility: .visible
    ) {
      Button(L10n.tr("开始 10 秒测试")) {
        model.startMicrophone()
        finish()
      }
      Button(L10n.tr("取消"), role: .cancel) {}
    } message: {
      Text(L10n.tr("将使用系统默认麦克风，可能改变蓝牙耳机模式。请先安静约 2 秒，再正常讲话。结果仅代表到达 Mac 的声音；不保存录音。"))
    }
  }

  private func choice<Actions: View>(
    title: LocalizedText, symbol: String, detail: LocalizedText, @ViewBuilder actions: () -> Actions
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(L10n.tr(title), systemImage: symbol).font(.headline)
      Text(L10n.tr(detail)).font(.callout).foregroundStyle(.secondary).fixedSize(
        horizontal: false, vertical: true)
      actions()
    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
      .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
  }
}
