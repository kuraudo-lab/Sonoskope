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
          Text("声音电平").font(.callout.weight(.medium))
          Spacer()
          Text("dBFS · 最近 60 秒").font(.caption).foregroundStyle(.secondary)
        }
        HStack(spacing: 12) {
          Label("应用输出", systemImage: "minus").foregroundStyle(.blue)
          Label("麦克风测试", systemImage: "minus").foregroundStyle(.purple)
        }.font(.caption)
        if audio.contains(where: { $0.value != nil }) {
          Chart {
            ForEach(audio) { point in
              if let value = point.value {
                LineMark(
                  x: .value("时间", point.date), y: .value("电平", max(-80, value)),
                  series: .value("连续片段", point.series)
                )
                .foregroundStyle(point.source == "input" ? Color.purple : Color.blue)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.linear)
              }
            }
            if let incidentAt, domain.contains(incidentAt) {
              RuleMark(x: .value("问题时间", incidentAt)).foregroundStyle(.secondary).lineStyle(
                StrokeStyle(lineWidth: 1, dash: [3]))
            }
            if let selectedAudioDate, domain.contains(selectedAudioDate) {
              RuleMark(x: .value("查看时间", selectedAudioDate)).foregroundStyle(
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
          .frame(height: 110)
          .accessibilityLabel("最近一分钟本地音频电平，蓝色为应用输出，紫色为主动麦克风测试。缺失数据不连线。")
          Text(audioDetail).font(.caption).foregroundStyle(.secondary).monospacedDigit()
        } else {
          empty(audioEnabled ? "等待可用音频数据" : "开启输出分析或主动麦克风测试后显示")
        }
      }
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Text("网络探测").font(.callout.weight(.medium))
          Spacer()
          Text("TCP 连接耗时 · ms").font(.caption).foregroundStyle(.secondary)
        }
        if !network.isEmpty {
          Chart {
            ForEach(network.filter { $0.value != nil }) { point in
              if let value = point.value {
                LineMark(
                  x: .value("时间", point.date), y: .value("连接耗时", value),
                  series: .value("连续片段", point.series)
                )
                .foregroundStyle(.teal).lineStyle(StrokeStyle(lineWidth: 1.5))
                PointMark(x: .value("时间", point.date), y: .value("连接耗时", value)).foregroundStyle(
                  .teal
                ).symbolSize(16)
              }
            }
            ForEach(network.filter { $0.value == nil }) { point in
              RuleMark(x: .value("失败或超时", point.date)).foregroundStyle(.orange).lineStyle(
                StrokeStyle(lineWidth: 1, dash: [2]))
            }
            if let incidentAt, domain.contains(incidentAt) {
              RuleMark(x: .value("问题时间", incidentAt)).foregroundStyle(.secondary).lineStyle(
                StrokeStyle(lineWidth: 1, dash: [3]))
            }
            if let selectedNetworkDate, domain.contains(selectedNetworkDate) {
              RuleMark(x: .value("查看时间", selectedNetworkDate)).foregroundStyle(
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
          .accessibilityLabel("最近一分钟到测试目标的 TCP 连接耗时，含 DNS。橙色竖线表示探测失败或超时，不是零延迟。")
          Text(networkDetail).font(.caption).foregroundStyle(.secondary).monospacedDigit()
        } else {
          empty(networkEnabled ? "等待网络探测数据" : "主动网络探测已关闭")
        }
        Text("测试目标 www.apple.com:443；不是会议延迟或丢包率。")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
  }
  private func empty(_ text: String) -> some View {
    Text(text).font(.caption).foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, minHeight: 58, alignment: .center)
      .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
  }
  private var audioDetail: String {
    guard let selectedAudioDate, let point = nearest(audio, to: selectedAudioDate),
      let value = point.value
    else {
      return "电平不等于音质；静音不是中断，缺失数据留空。"
    }
    return point.date.formatted(date: .omitted, time: .standard) + " · "
      + (point.source == "input" ? "麦克风测试 " : "应用输出 ") + String(format: "%.1f dBFS", value)
  }
  private var networkDetail: String {
    if let selectedNetworkDate, let point = nearest(network, to: selectedNetworkDate) {
      return point.date.formatted(date: .omitted, time: .standard) + " · "
        + (point.value.map { String(format: "%.0f ms", $0) } ?? "失败／超时")
    }
    let failures = network.filter { $0.value == nil }.count
    return failures > 0 ? "橙色虚线：\(failures) 次失败／超时；不计作会议丢包。" : "点击图表查看时间点；断线处没有有效读数。"
  }
  private func nearest(_ points: [TelemetryPoint], to date: Date) -> TelemetryPoint? {
    points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
  }
}
