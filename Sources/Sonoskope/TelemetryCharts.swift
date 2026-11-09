import Charts
import SonoskopeCore
import SwiftUI

struct TelemetryCharts: View {
  let audio: [TelemetryPoint]
  let network: [TelemetryPoint]
  let endingAt: Date
  let incidentAt: Date?
  let audioEnabled: Bool
  let networkEnabled: Bool
  @State private var selectedAudioDate: Date?
  @State private var selectedNetworkDate: Date?
  private var domain: ClosedRange<Date> { endingAt.addingTimeInterval(-60)...endingAt }
  private var networkCeiling: Double {
    max(100, ceil((network.compactMap(\.value).max() ?? 0) / 100) * 100)
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Text(L10n.tr("声音电平")).font(.callout.weight(.medium))
          Spacer()
          Text(L10n.tr("dBFS · 最近 60 秒")).font(.caption).foregroundStyle(.secondary)
        }
        HStack(spacing: 12) {
          Label(L10n.tr("应用输出"), systemImage: "minus").foregroundStyle(.blue)
          Label(L10n.tr("麦克风输入"), systemImage: "minus").foregroundStyle(.purple)
        }.font(.caption)
        if audio.contains(where: { $0.value != nil }) {
          Chart {
            ForEach(audio) { point in
              if let value = point.value {
                LineMark(
                  x: .value(L10n.tr("时间"), point.date), y: .value(L10n.tr("电平"), max(-80, value)),
                  series: .value(L10n.tr("连续片段"), point.series)
                )
                .foregroundStyle(point.source == "input" ? Color.purple : Color.blue)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.linear)
              }
            }
            ForEach(inputChanges) { point in
              RuleMark(x: .value(L10n.tr("应用变化"), point.date))
                .foregroundStyle(.purple.opacity(0.25))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }
            if let point = focusedInput, let value = point.value, let context = point.context {
              PointMark(
                x: .value(L10n.tr("时间"), point.date),
                y: .value(L10n.tr("电平"), max(-80, value))
              )
              .foregroundStyle(.purple).symbolSize(24)
              .annotation(
                position: .top, alignment: .trailing, spacing: 5,
                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
              ) {
                VStack(alignment: .leading, spacing: 2) {
                  Text(point.date.uiFormatted(date: .omitted, time: .standard))
                    .foregroundStyle(.secondary)
                  Text(context).fontWeight(.medium).lineLimit(2)
                }.font(.caption2).frame(maxWidth: 210, alignment: .leading)
                  .padding(6).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                  .help(context)
              }
            }
            if let incidentAt, domain.contains(incidentAt) {
              RuleMark(x: .value(L10n.tr("问题时间"), incidentAt)).foregroundStyle(.secondary)
                .lineStyle(
                  StrokeStyle(lineWidth: 1, dash: [3]))
            }
            if let selectedAudioDate, domain.contains(selectedAudioDate) {
              RuleMark(x: .value(L10n.tr("查看时间"), selectedAudioDate)).foregroundStyle(
                .secondary.opacity(0.5))
            }
          }
          .chartXScale(domain: domain).chartYScale(domain: -80...0)
          .chartXAxis {
            AxisMarks(values: .stride(by: .second, count: 15)) { _ in
              AxisGridLine()
              AxisValueLabel(format: .dateTime.minute().second())
            }
          }
          .chartYAxis {
            AxisMarks(position: .leading, values: [-80, -40, 0]) { value in
              AxisGridLine()
              AxisValueLabel {
                if let number = value.as(Int.self) { Text(number == -80 ? "≤−80" : String(number)) }
              }
            }
          }
          .chartXSelection(value: $selectedAudioDate)
          .frame(height: 140)
          .accessibilityLabel(L10n.tr("最近一分钟本地音频电平，蓝色为应用输出，紫色为麦克风输入。缺失数据不连线。"))
          Text(audioDetail).font(.caption).foregroundStyle(.secondary).monospacedDigit()
          if audio.contains(where: { $0.context != nil }) {
            Text(L10n.tr("标签表示使用此麦克风的应用；不是各应用的独立音量。点击曲线可查看过去的应用。"))
              .font(.caption).foregroundStyle(.secondary).fixedSize(
                horizontal: false, vertical: true)
          }
        } else {
          empty(audioEnabled ? L10n.tr("等待可用音频数据") : L10n.tr("开启输出分析、自动麦克风监测或手动测试后显示"))
        }
      }
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Text(L10n.tr("网络探测")).font(.callout.weight(.medium))
          Spacer()
          Text(L10n.tr("TCP 连接耗时 · ms")).font(.caption).foregroundStyle(.secondary)
        }
        if !network.isEmpty {
          Chart {
            ForEach(network.filter { $0.value != nil }) { point in
              if let value = point.value {
                LineMark(
                  x: .value(L10n.tr("时间"), point.date), y: .value(L10n.tr("连接耗时"), value),
                  series: .value(L10n.tr("连续片段"), point.series)
                )
                .foregroundStyle(.teal).lineStyle(StrokeStyle(lineWidth: 1.5))
                PointMark(x: .value(L10n.tr("时间"), point.date), y: .value(L10n.tr("连接耗时"), value))
                  .foregroundStyle(
                    .teal
                  ).symbolSize(16)
              }
            }
            ForEach(network.filter { $0.value == nil }) { point in
              RuleMark(x: .value(L10n.tr("失败或超时"), point.date)).foregroundStyle(.orange).lineStyle(
                StrokeStyle(lineWidth: 1, dash: [2]))
            }
            if let incidentAt, domain.contains(incidentAt) {
              RuleMark(x: .value(L10n.tr("问题时间"), incidentAt)).foregroundStyle(.secondary)
                .lineStyle(
                  StrokeStyle(lineWidth: 1, dash: [3]))
            }
            if let selectedNetworkDate, domain.contains(selectedNetworkDate) {
              RuleMark(x: .value(L10n.tr("查看时间"), selectedNetworkDate)).foregroundStyle(
                .secondary.opacity(0.5))
            }
          }
          .chartXScale(domain: domain).chartYScale(domain: 0...networkCeiling)
          .chartXAxis {
            AxisMarks(values: .stride(by: .second, count: 15)) { _ in
              AxisGridLine()
              AxisValueLabel(format: .dateTime.minute().second())
            }
          }
          .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
          .chartXSelection(value: $selectedNetworkDate)
          .frame(height: 100)
          .accessibilityLabel(L10n.tr("最近一分钟到测试目标的 TCP 连接耗时，含 DNS。橙色竖线表示探测失败或超时，不是零延迟。"))
          Text(networkDetail).font(.caption).foregroundStyle(.secondary).monospacedDigit()
        } else {
          empty(networkEnabled ? L10n.tr("等待网络探测数据") : L10n.tr("主动网络探测已关闭"))
        }
        Text(L10n.tr("测试目标 www.apple.com:443；不是会议延迟或丢包率。"))
          .font(.caption).foregroundStyle(.secondary)
      }
    }
  }
  private func empty(_ text: String) -> some View {
    Text(text).font(.caption).foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, minHeight: 58, alignment: .center)
      .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
  }
  private var focusedInput: TelemetryPoint? {
    let inputs = audio.filter { $0.source == "input" && $0.value != nil }
    guard let selectedAudioDate else { return inputs.last }
    guard let point = nearest(inputs, to: selectedAudioDate),
      abs(point.date.timeIntervalSince(selectedAudioDate)) <= 2
    else { return nil }
    return point
  }
  private var inputChanges: [TelemetryPoint] {
    var previous: String?
    return audio.filter { point in
      guard point.source == "input" else { return false }
      defer { previous = point.context }
      return point.context != nil && previous != nil && previous != point.context
    }
  }
  private var audioDetail: String {
    guard let selectedAudioDate, let point = nearest(audio, to: selectedAudioDate),
      let value = point.value
    else {
      return L10n.tr("电平不等于音质；静音不是中断，缺失数据留空。")
    }
    return point.date.uiFormatted(date: .omitted, time: .standard) + " · "
      + (point.source == "input" ? L10n.tr("麦克风输入 ") : L10n.tr("应用输出 "))
      + String(format: "%.1f dBFS", value)
      + (point.context.map { " · " + $0 } ?? "")
  }
  private var networkDetail: String {
    if let selectedNetworkDate, let point = nearest(network, to: selectedNetworkDate) {
      return point.date.uiFormatted(date: .omitted, time: .standard) + " · "
        + (point.value.map { String(format: "%.0f ms", $0) } ?? L10n.tr("失败／超时"))
    }
    let failures = network.filter { $0.value == nil }.count
    return failures > 0
      ? L10n.tr("橙色虚线：\(failures) 次失败／超时；不计作会议丢包。") : L10n.tr("点击图表查看时间点；断线处没有有效读数。")
  }
  private func nearest(_ points: [TelemetryPoint], to date: Date) -> TelemetryPoint? {
    points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
  }
}
