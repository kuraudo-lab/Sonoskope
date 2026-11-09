import AVFoundation
import XCTest

@testable import Sonoskope

final class MicrophoneConfigurationTests: XCTestCase {
  private func format(rate: Double = 48000, channels: AVAudioChannelCount = 1) -> AVAudioFormat {
    AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels)!
  }
  func testQueuedStartupNotificationKeepsUnchangedRunningInput() {
    let baseline = MicrophoneConfiguration(deviceID: 107, format: format())
    XCTAssertFalse(
      baseline.requiresStop(
        running: true, currentDeviceID: 107,
        currentFormat: format(), deviceAlive: true))
  }
  func testStoppedEngineRequiresStopEvenWhenFormatMatches() {
    let baseline = MicrophoneConfiguration(deviceID: 107, format: format())
    XCTAssertTrue(
      baseline.requiresStop(
        running: false, currentDeviceID: 107,
        currentFormat: format(), deviceAlive: true))
  }
  func testChangedOrUnreadableDeviceRequiresStop() {
    let baseline = MicrophoneConfiguration(deviceID: 107, format: format())
    for device: UInt32? in [108, nil] {
      XCTAssertTrue(
        baseline.requiresStop(
          running: true, currentDeviceID: device,
          currentFormat: format(), deviceAlive: true))
    }
  }
  func testSampleRateOrChannelChangeRequiresStop() {
    let baseline = MicrophoneConfiguration(deviceID: 107, format: format())
    for changed in [format(rate: 44100), format(channels: 2)] {
      XCTAssertTrue(
        baseline.requiresStop(
          running: true, currentDeviceID: 107,
          currentFormat: changed, deviceAlive: true))
    }
  }
  func testDisconnectedDeviceRequiresStop() {
    let baseline = MicrophoneConfiguration(deviceID: 107, format: format())
    XCTAssertTrue(
      baseline.requiresStop(
        running: true, currentDeviceID: 107,
        currentFormat: format(), deviceAlive: false))
  }
}
