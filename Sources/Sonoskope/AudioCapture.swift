import AVFoundation
import CoreAudio
import Foundation
import SonoskopeCore

enum CaptureError: LocalizedError {
  case status(String, OSStatus)
  case unsupported, noInput
  var errorDescription: String? {
    switch self {
    case .status(let operation, let status): "\(operation)失败（\(status)）。请检查系统音频录制权限和设备状态。"
    case .unsupported: "当前音频格式不受支持；没有将缺失数据视为正常。"
    case .noInput: "没有可用的默认输入设备。"
    }
  }
}

/// Called serially by one capture source. Only aggregate metrics leave the callback; PCM is never stored.
final class CallbackAnalyzer {
  private var analyzer = AudioAnalyzer()
  private var energy = 0.0
  private var peak = 0.0
  private var clipped = 0
  private var count = 0
  private var duration = 0.0
  private var lastEmit: TimeInterval = 0
  private var pendingGap = false
  private var pendingDiscontinuity = false
  private let report: (AudioMeasurement) -> Void
  init(report: @escaping (AudioMeasurement) -> Void) { self.report = report }
  func accept(
    _ buffers: UnsafePointer<AudioBufferList>, format: AudioStreamBasicDescription,
    sampleTime: Double?
  ) {
    let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffers))
    var squares = 0.0
    var maximum = 0.0
    var clippedCount = 0
    var samples = 0
    var frames = 0
    for buffer in list {
      guard let data = buffer.mData, buffer.mNumberChannels > 0 else { continue }
      let n = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
      frames = max(frames, n / Int(buffer.mNumberChannels))
      let floats = data.assumingMemoryBound(to: Float.self)
      for index in 0..<n {
        let value = Double(floats[index])
        guard value.isFinite else { continue }
        squares += value * value
        maximum = max(maximum, abs(value))
        if abs(value) >= 0.999 { clippedCount += 1 }
        samples += 1
      }
    }
    guard frames > 0, format.mSampleRate > 0 else { return }
    let seconds = Double(frames) / format.mSampleRate
    let now = Date()
    guard
      let measurement = analyzer.measure(
        sumSquares: squares, peak: maximum, clipped: clippedCount,
        sampleCount: samples, duration: seconds, date: now,
        streamTime: sampleTime.map { $0 / format.mSampleRate })
    else { return }
    energy += squares
    peak = max(peak, maximum)
    clipped += clippedCount
    count += samples
    duration += seconds
    pendingGap = pendingGap || measurement.suspectGap
    pendingDiscontinuity = pendingDiscontinuity || measurement.discontinuity
    // Bound main-thread traffic; sample discontinuities are collector evidence, never audio defects.
    if now.timeIntervalSince1970 - lastEmit >= 0.25, count > 0 {
      let rmsDB = 20.0 * log10(max(sqrt(energy / Double(count)), 0.000001))
      let peakDB = 20.0 * log10(max(peak, 0.000001))
      let measurement = AudioMeasurement(
        date: now, rmsDB: rmsDB, peakDB: peakDB,
        clippingFraction: Double(clipped) / Double(count), sampleCount: count, duration: duration,
        suspectGap: pendingGap, discontinuity: pendingDiscontinuity)
      report(measurement)
      energy = 0
      peak = 0
      clipped = 0
      count = 0
      duration = 0
      pendingGap = false
      pendingDiscontinuity = false
      lastEmit = now.timeIntervalSince1970
    }
  }
}

@MainActor final class OutputCapture {
  private var tap: AudioObjectID = 0
  private var aggregate: AudioObjectID = 0
  private var ioProc: AudioDeviceIOProcID?
  private let queue = DispatchQueue(label: "lab.kuraudo.Sonoskope.tap", qos: .userInitiated)
  private var sink: CallbackAnalyzer?
  var isRunning: Bool { ioProc != nil }
  @available(macOS 14.2, *)
  func start(
    processes: [AudioObjectID]?, onMeasurement: @escaping @MainActor (AudioMeasurement) -> Void
  ) throws {
    stop()
    let description: CATapDescription
    if let processes, !processes.isEmpty {
      description = CATapDescription(stereoMixdownOfProcesses: processes)
    } else {
      let own = AudioHAL.ids(
        AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList
      ).filter {
        AudioHAL.scalar($0, kAudioProcessPropertyPID, default: pid_t(0)) == getpid()
      }
      description = CATapDescription(stereoGlobalTapButExcludeProcesses: own)
    }
    description.name = "Sonoskope Output Analysis"
    description.uuid = UUID()
    description.isPrivate = true
    description.muteBehavior = .unmuted
    do {
      try check(AudioHardwareCreateProcessTap(description, &tap), "创建音频采集")
      var format = AudioStreamBasicDescription()
      var address = AudioHAL.address(kAudioTapPropertyFormat)
      var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
      try check(AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format), "读取采集格式")
      guard format.mFormatID == kAudioFormatLinearPCM,
        format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
        format.mBitsPerChannel == 32, format.mSampleRate > 0
      else { throw CaptureError.unsupported }
      let configuration: [String: Any] = [
        kAudioAggregateDeviceNameKey: "Sonoskope Tap",
        kAudioAggregateDeviceUIDKey: "lab.kuraudo.Sonoskope.tap." + UUID().uuidString,
        kAudioAggregateDeviceIsPrivateKey: true,
        kAudioAggregateDeviceTapAutoStartKey: true,
        kAudioAggregateDeviceTapListKey: [
          [
            kAudioSubTapUIDKey: description.uuid.uuidString,
            kAudioSubTapDriftCompensationKey: true,
          ]
        ],
      ]
      try check(
        AudioHardwareCreateAggregateDevice(configuration as CFDictionary, &aggregate), "创建采集设备")
      let sink = CallbackAnalyzer { measurement in Task { @MainActor in onMeasurement(measurement) }
      }
      self.sink = sink
      let captureFormat = format
      try check(
        AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregate, queue) { _, input, time, _, _ in
          let timestamp = time.pointee
          sink.accept(
            input, format: captureFormat,
            sampleTime: timestamp.mFlags.contains(.sampleTimeValid) ? timestamp.mSampleTime : nil)
        }, "安装采集回调")
      try check(AudioDeviceStart(aggregate, ioProc), "启动音频采集")
    } catch {
      stop()
      throw error
    }
  }
  func stop() {
    if let ioProc, aggregate != 0 {
      AudioDeviceStop(aggregate, ioProc)
      AudioDeviceDestroyIOProcID(aggregate, ioProc)
    }
    ioProc = nil
    if aggregate != 0 {
      AudioHardwareDestroyAggregateDevice(aggregate)
      aggregate = 0
    }
    if tap != 0 {
      if #available(macOS 14.2, *) { AudioHardwareDestroyProcessTap(tap) }
      tap = 0
    }
    sink = nil
  }
  private func check(_ status: OSStatus, _ operation: String) throws {
    if status != noErr { throw CaptureError.status(operation, status) }
  }
}

@MainActor final class MicrophoneTest {
  private var engine: AVAudioEngine?
  private var sink: CallbackAnalyzer?
  private var timeout: Task<Void, Never>?
  private var generation = UUID()
  func start(
    onMeasurement: @escaping @MainActor (AudioMeasurement) -> Void,
    onEnd: @escaping @MainActor (String) -> Void
  ) async {
    stop()
    let token = UUID()
    generation = token
    let permitted = await AVCaptureDevice.requestAccess(for: .audio)
    guard generation == token else { return }
    guard permitted else {
      onEnd("麦克风权限未授权；没有进行测试。")
      return
    }
    let engine = AVAudioEngine()
    let input = engine.inputNode
    let format = input.outputFormat(forBus: 0)
    guard format.channelCount > 0, format.sampleRate > 0, format.commonFormat == .pcmFormatFloat32
    else {
      onEnd("默认输入设备不可用或格式不受支持。")
      return
    }
    let sink = CallbackAnalyzer { measurement in Task { @MainActor in onMeasurement(measurement) } }
    self.sink = sink
    self.engine = engine
    input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, time in
      sink.accept(
        buffer.audioBufferList, format: format.streamDescription.pointee,
        sampleTime: time.isSampleTimeValid ? Double(time.sampleTime) : nil)
    }
    do { try engine.start() } catch {
      stop()
      onEnd("麦克风测试启动失败：" + error.localizedDescription)
      return
    }
    timeout = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(10)) } catch { return }
      guard self?.generation == token else { return }
      self?.stop()
      onEnd("10 秒本地测试已结束。结果不代表远端听感。")
    }
  }
  func stop() {
    generation = UUID()
    timeout?.cancel()
    timeout = nil
    if let engine {
      engine.inputNode.removeTap(onBus: 0)
      engine.stop()
    }
    engine = nil
    sink = nil
  }
}
