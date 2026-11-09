import SonoskopeCore
import SwiftUI

struct MonitoringScopeView: View {
  let model: MonitorModel
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text(L10n.tr("当前采集范围与详细指标")).font(.headline)
        Spacer()
        Button(L10n.tr("完成")) { dismiss() }.keyboardShortcut(.cancelAction)
      }
      ScrollView { details.frame(maxWidth: .infinity, alignment: .leading) }
    }.padding(24).frame(width: 550, height: 480)
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
          L10n.tr("输入：按需自动监测或手动测试。应用输出：")
            + (model.outputEnabled ? L10n.tr("已开启") : L10n.tr("未开启")) + L10n.tr("。"))
        Text(L10n.tr("设备每 2 秒轮询，短于轮询间隔的断连可能漏检。"))
        Text(L10n.tr("应用可能使用不同的输出设备；输出电平是所选应用的数字音频。"))
        Text(L10n.tr("仅在输入或输出电平活跃时探测：www.apple.com:443，每次完成后间隔 5 秒；不是会议延迟。"))
        Text(model.network.path)
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
