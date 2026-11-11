import AppKit
import CoreAudio
import Foundation
import IOBluetooth
import SonoskopeCore

struct AudioDeviceInfo: Identifiable, Equatable, Sendable {
  let id: AudioObjectID
  let uid: String
  let name: String
  let transport: String
  let isBluetooth: Bool
  let inputChannels: Int
  let outputChannels: Int
  let sampleRate: Double
  let bufferFrames: UInt32
  let running: Bool
}
struct AudioProcessInfo: Identifiable, Equatable, Sendable {
  let id: AudioObjectID
  let pid: pid_t
  let bundleID: String
  let name: String
  let inputActive: Bool
  let outputActive: Bool
  let outputDevices: [AudioObjectID]
  let inputDevices: [AudioObjectID]
}
struct BluetoothInfo: Identifiable, Sendable {
  var id: String { name }
  let name: String
  let rssi: Int?
}
struct HardwareSnapshot: Sendable {
  var devices: [AudioDeviceInfo] = []
  var processes: [AudioProcessInfo] = []
  var defaultInput: AudioObjectID = 0
  var defaultOutput: AudioObjectID = 0
  var bluetooth: [BluetoothInfo] = []
  var timestamp = Date()
  var inputProcesses: [InputProcessActivity]? = nil
  var input: AudioDeviceInfo? { devices.first { $0.id == defaultInput } }
  var output: AudioDeviceInfo? { devices.first { $0.id == defaultOutput } }
  var audioActive: Bool { processes.contains { $0.inputActive || $0.outputActive } }
  func inputUsers(of device: AudioObjectID, observerPID: Int32) -> [String] {
    let users = (inputProcesses ?? []).filter {
      $0.pid != observerPID && $0.bundleID != "lab.kuraudo.Sonoskope"
        && $0.running == true && $0.devices?.contains(device) == true
    }.map { process in
      if let name = processes.first(where: { $0.pid == process.pid })?.name, !name.isEmpty {
        return name
      }
      return process.bundleID.isEmpty ? L10n.tr("进程 \(process.pid)") : process.bundleID
    }
    return Array(Set(users)).sorted()
  }

}

enum AudioHAL {
  static func address(
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
  ) -> AudioObjectPropertyAddress {
    .init(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
  }
  static func scalar<T>(
    _ object: AudioObjectID, _ selector: AudioObjectPropertySelector, default fallback: T,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
  ) -> T {
    var property = address(selector, scope: scope)
    var value = fallback
    var size = UInt32(MemoryLayout<T>.size)
    guard AudioObjectHasProperty(object, &property) else { return fallback }
    let result = withUnsafeMutablePointer(to: &value) {
      AudioObjectGetPropertyData(object, &property, 0, nil, &size, $0)
    }
    return result == noErr ? value : fallback
  }
  static func ids(
    _ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
  ) -> [AudioObjectID] { optionalIDs(object, selector, scope: scope) ?? [] }

  static func optionalIDs(
    _ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
  ) -> [AudioObjectID]? {
    var property = address(selector)
    property.mScope = scope
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(object, &property, 0, nil, &size) == noErr else {
      return nil
    }
    if size == 0 { return [] }
    guard Int(size) % MemoryLayout<AudioObjectID>.size == 0 else { return nil }
    var values = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    let status = values.withUnsafeMutableBytes {
      AudioObjectGetPropertyData(object, &property, 0, nil, &size, $0.baseAddress!)
    }
    guard status == noErr else { return nil }
    return Array(values.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
  }
  static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String {
    var property = address(selector)
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    let status = withUnsafeMutablePointer(to: &value) {
      AudioObjectGetPropertyData(object, &property, 0, nil, &size, $0)
    }
    guard status == noErr else { return "" }
    return value?.takeRetainedValue() as String? ?? ""
  }
  static func channels(_ object: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
    var property = address(kAudioDevicePropertyStreamConfiguration, scope: scope)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(object, &property, 0, nil, &size) == noErr,
      size >= MemoryLayout<AudioBufferList>.size
    else { return 0 }
    let memory = UnsafeMutableRawPointer.allocate(
      byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { memory.deallocate() }
    guard AudioObjectGetPropertyData(object, &property, 0, nil, &size, memory) == noErr else {
      return 0
    }
    return UnsafeMutableAudioBufferListPointer(memory.assumingMemoryBound(to: AudioBufferList.self))
      .reduce(0) { $0 + Int($1.mNumberChannels) }
  }
  static func transport(_ value: UInt32) -> String {
    switch value {
    case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: L10n.tr("蓝牙")
    case kAudioDeviceTransportTypeBuiltIn: L10n.tr("内置")
    case kAudioDeviceTransportTypeUSB: "USB"
    case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate: L10n.tr("虚拟")
    case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: L10n.tr("显示器")
    default: L10n.tr("其他")
    }
  }
  static func snapshot(includeBluetooth: Bool) -> HardwareSnapshot {
    let system = AudioObjectID(kAudioObjectSystemObject)
    var result = HardwareSnapshot()
    result.defaultInput = scalar(
      system, kAudioHardwarePropertyDefaultInputDevice, default: UInt32(0))
    result.defaultOutput = scalar(
      system, kAudioHardwarePropertyDefaultOutputDevice, default: UInt32(0))
    result.devices = ids(system, kAudioHardwarePropertyDevices).compactMap { id in
      let name = string(id, kAudioObjectPropertyName)
      guard !name.hasPrefix("Sonoskope Tap") else { return nil }
      let transportType = scalar(id, kAudioDevicePropertyTransportType, default: UInt32(0))
      return .init(
        id: id, uid: string(id, kAudioDevicePropertyDeviceUID), name: name,
        transport: transport(transportType),
        isBluetooth: transportType == kAudioDeviceTransportTypeBluetooth
          || transportType == kAudioDeviceTransportTypeBluetoothLE,
        inputChannels: channels(id, scope: kAudioDevicePropertyScopeInput),
        outputChannels: channels(id, scope: kAudioDevicePropertyScopeOutput),
        sampleRate: scalar(id, kAudioDevicePropertyNominalSampleRate, default: Double(0)),
        bufferFrames: scalar(id, kAudioDevicePropertyBufferFrameSize, default: UInt32(0)),
        running: scalar(id, kAudioDevicePropertyDeviceIsRunningSomewhere, default: UInt32(0)) != 0)
    }
    if #available(macOS 14.2, *),
      let processIDs = optionalIDs(system, kAudioHardwarePropertyProcessObjectList)
    {
      var usage: [InputProcessActivity] = []
      var complete = true
      result.processes = processIDs.compactMap { id in
        let pid = scalar(id, kAudioProcessPropertyPID, default: pid_t(0))
        guard pid > 0 else {
          complete = false
          return nil
        }
        let bundle = string(id, kAudioProcessPropertyBundleID)
        let runningInput = scalar(id, kAudioProcessPropertyIsRunningInput, default: UInt32.max)
        let inputDevices = optionalIDs(
          id, kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeInput)
        usage.append(
          .init(
            pid: pid, bundleID: bundle,
            running: runningInput <= 1 ? runningInput == 1 : nil, devices: inputDevices))
        guard pid != getpid(), bundle != "lab.kuraudo.Sonoskope" else { return nil }
        let name =
          NSRunningApplication(processIdentifier: pid)?.localizedName ?? bundle.split(
            separator: "."
          ).last.map(String.init) ?? L10n.tr("进程 \(pid)")
        return .init(
          id: id, pid: pid, bundleID: bundle, name: name,
          inputActive: runningInput == 1,
          outputActive: scalar(id, kAudioProcessPropertyIsRunningOutput, default: UInt32(0)) != 0,
          outputDevices: ids(
            id, kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeOutput),
          inputDevices: inputDevices ?? []
        )
      }.sorted { $0.name < $1.name }
      result.inputProcesses = complete ? usage : nil
    }
    if includeBluetooth, let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] {
      result.bluetooth = devices.filter { $0.isConnected() }.map {
        .init(name: $0.name ?? L10n.tr("蓝牙设备"), rssi: BluetoothReading.validRSSI(Int($0.rawRSSI())))
      }
    }
    return result
  }
}

@MainActor final class HardwareMonitor {
  private var previous: HardwareSnapshot?
  private var missing: [String: AudioDeviceInfo] = [:]
  // Polling is intentionally honest: brief reconnects between snapshots can be missed.
  func poll(snapshot next: HardwareSnapshot) -> (HardwareSnapshot, [DiagnosticEvent], Bool) {
    var events: [DiagnosticEvent] = []
    let wasActive = previous?.audioActive ?? false
    if let old = previous {
      let watchedInputIDs = Set(
        [old.defaultInput] + old.processes.filter { $0.inputActive }.flatMap(\.inputDevices))
      let watchedOutputIDs = Set(
        [old.defaultOutput] + old.processes.filter { $0.outputActive }.flatMap(\.outputDevices))
      let watchedIDs = watchedInputIDs.union(watchedOutputIDs)
      for device in old.devices
      where watchedIDs.contains(device.id)
        && !next.devices.contains(where: { $0.uid == device.uid })
      {
        missing[device.uid] = device
        let direction: Direction =
          watchedInputIDs.contains(device.id) && watchedOutputIDs.contains(device.id)
          ? .shared : watchedInputIDs.contains(device.id) ? .input : .output
        events.append(
          .init(
            kind: .deviceDisconnected, direction: direction, source: device.uid,
            message: "\(device.name) 从音频设备列表消失（2 秒轮询）"))
      }
      for device in next.devices {
        if missing.removeValue(forKey: device.uid) != nil {
          events.append(
            .init(kind: .deviceRestored, source: device.uid, message: "\(device.name) 重新可用"))
        }
        if let before = old.devices.first(where: { $0.uid == device.uid }),
          before.sampleRate != device.sampleRate
        {
          events.append(
            .init(
              kind: .formatChanged, source: device.uid,
              message:
                "\(device.name)：\(Int(before.sampleRate)) → \(Int(device.sampleRate)) Hz；格式变化不代表故障")
          )
        }
      }
      if old.defaultInput != next.defaultInput || old.defaultOutput != next.defaultOutput {
        events.append(
          .init(kind: .routeChanged, source: "system", message: "系统默认输入／输出发生变化；应用可能使用独立选择"))
      }
    }
    previous = next
    return (next, events, wasActive || next.audioActive)
  }
  func reset() {
    previous = nil
    missing.removeAll()
  }
}
