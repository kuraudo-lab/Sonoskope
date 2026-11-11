import AVFoundation
import CoreAudio
import Foundation
import SonoskopeCore

enum CaptureError: LocalizedError {
  case status(String, OSStatus)
  case unsupported, noInput
  var errorDescription: String? { diagnosticText.localized }
  var diagnosticText: LocalizedText {
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
      try check(AudioHardwareCreateProcessTap(description, &tap), "AudioHardwareCreateProcessTap")
      var format = AudioStreamBasicDescription()
      var address = AudioHAL.address(kAudioTapPropertyFormat)
      var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
      try check(
        AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format),
        "AudioObjectGetPropertyData")
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
        AudioHardwareCreateAggregateDevice(configuration as CFDictionary, &aggregate),
        "AudioHardwareCreateAggregateDevice")
      let delivery = MeasurementDelivery { measurement in
        MainActor.assumeIsolated { onMeasurement(measurement) }
      }
      let sink = CallbackAnalyzer { delivery.submit($0) }
      self.sink = sink
      let captureFormat = format
      try check(
        AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregate, queue) { _, input, time, _, _ in
          let timestamp = time.pointee
          sink.accept(
            input, format: captureFormat,
            sampleTime: timestamp.mFlags.contains(.sampleTimeValid) ? timestamp.mSampleTime : nil)
        }, "AudioDeviceCreateIOProcIDWithBlock")
      try check(AudioDeviceStart(aggregate, ioProc), "AudioDeviceStart")
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

enum MicrophoneCaptureEnd {
  case completed, permissionDenied, configurationChanged
  case failed(String)
}
@MainActor protocol MicrophoneCapturing: AnyObject {
  func start(
    deviceID: AudioDeviceID, duration: TimeInterval?, requestPermission: Bool,
    onMeasurement: @escaping @MainActor (AudioMeasurement) -> Void,
    onEnd: @escaping @MainActor (MicrophoneCaptureEnd) -> Void) async
  func stop()
}
struct MicrophoneConfiguration {
  let deviceID: AudioDeviceID
  let format: AVAudioFormat
  func requiresStop(
    running: Bool, currentDeviceID: AudioDeviceID?, currentFormat: AVAudioFormat,
    deviceAlive: Bool
  ) -> Bool {
    !running || !deviceAlive || currentDeviceID != deviceID || !format.isEqual(currentFormat)
  }
}

@MainActor final class MicrophoneCapture: MicrophoneCapturing {
  typealias End = MicrophoneCaptureEnd
  private var engine: AVAudioEngine?
  private var sink: CallbackAnalyzer?
  private var timeout: Task<Void, Never>?
  private var configurationObserver: NSObjectProtocol?
  private var generation = UUID()

  func start(
    deviceID: AudioDeviceID, duration: TimeInterval?, requestPermission: Bool,
    onMeasurement: @escaping @MainActor (AudioMeasurement) -> Void,
    onEnd: @escaping @MainActor (End) -> Void
  ) async {
    stop()
    let token = UUID()
    generation = token
    let permitted: Bool
    if requestPermission {
      permitted = await AVCaptureDevice.requestAccess(for: .audio)
    } else {
      permitted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
    guard generation == token else { return }
    guard permitted else {
      onEnd(.permissionDenied)
      return
    }
    guard deviceID != 0,
      AudioHAL.scalar(deviceID, kAudioDevicePropertyDeviceIsAlive, default: UInt32(0)) != 0
    else {
      onEnd(.failed(L10n.tr("输入设备不可用；已停止采集。")))
      return
    }
    let engine = AVAudioEngine()
    let input = engine.inputNode
    guard let unit = input.audioUnit else {
      onEnd(.failed(L10n.tr("输入设备不可用；已停止采集。")))
      return
    }
    // Bind only this engine to the observed device; never change the system default.
    var selected = deviceID
    let selection = AudioUnitSetProperty(
      unit, kAudioOutputUnitProperty_CurrentDevice,
      kAudioUnitScope_Global, 0, &selected, UInt32(MemoryLayout<AudioDeviceID>.size))
    var actual: AudioDeviceID = 0
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    let verification = AudioUnitGetProperty(
      unit, kAudioOutputUnitProperty_CurrentDevice,
      kAudioUnitScope_Global, 0, &actual, &size)
    guard selection == noErr, verification == noErr, actual == deviceID else {
      onEnd(.failed(L10n.tr("无法绑定目标输入设备；未采集其他麦克风。")))
      return
    }
    let format = input.outputFormat(forBus: 0)
    guard format.channelCount > 0, format.sampleRate > 0, format.commonFormat == .pcmFormatFloat32
    else {
      onEnd(.failed(L10n.tr("输入设备不可用或格式不受支持。")))
      return
    }
    let delivery = MeasurementDelivery { measurement in
      MainActor.assumeIsolated { onMeasurement(measurement) }
    }
    let sink = CallbackAnalyzer { delivery.submit($0) }
    self.sink = sink
    input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, time in
      sink.accept(
        buffer.audioBufferList, format: format.streamDescription.pointee,
        sampleTime: time.isSampleTimeValid ? Double(time.sampleTime) : nil)
    }
    self.engine = engine
    do { try engine.start() } catch {
      stop()
      onEnd(.failed(L10n.tr("麦克风采集启动失败：") + error.localizedDescription))
      return
    }
    configurationObserver = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        guard let self, self.generation == token else { return }
        var currentDevice: AudioDeviceID = 0
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var status = kAudioHardwareBadObjectError
        if let currentUnit = engine.inputNode.audioUnit {
          status = AudioUnitGetProperty(
            currentUnit, kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global, 0, &currentDevice, &propertySize)
        }
        let baseline = MicrophoneConfiguration(deviceID: deviceID, format: format)
        // Device binding can enqueue a startup notification that arrives after start().
        // Keep a healthy, unchanged capture; real route/format/stopped-engine changes still stop it.
        guard
          baseline.requiresStop(
            running: engine.isRunning, currentDeviceID: status == noErr ? currentDevice : nil,
            currentFormat: engine.inputNode.outputFormat(forBus: 0),
            deviceAlive: AudioHAL.scalar(
              deviceID, kAudioDevicePropertyDeviceIsAlive, default: UInt32(0)) != 0)
        else { return }
        self.stop()
        onEnd(.configurationChanged)
      }
    }
    if let duration {
      timeout = Task { [weak self] in
        do { try await Task.sleep(for: .seconds(duration)) } catch { return }
        guard self?.generation == token else { return }
        self?.stop()
        onEnd(.completed)
      }
    }
  }
  func stop() {
    generation = UUID()
    timeout?.cancel()
    timeout = nil
    if let configurationObserver {
      NotificationCenter.default.removeObserver(configurationObserver)
    }
    configurationObserver = nil
    if let engine {
      engine.inputNode.removeTap(onBus: 0)
      engine.stop()
    }
    engine = nil
    sink = nil
  }
}
