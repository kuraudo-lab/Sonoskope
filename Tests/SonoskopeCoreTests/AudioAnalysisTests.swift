import XCTest

@testable import SonoskopeCore

final class AudioAnalysisTests: XCTestCase {
  func tone(_ count: Int, amplitude: Float = 0.3) -> [Float] {
    (0..<count).map { amplitude * sin(Float($0) * 2 * .pi * 440 / 48000) }
  }
  func testSilenceAloneIsNotGapOrFault() {
    var analyzer = AudioAnalyzer()
    for _ in 0..<100 {
      let sample = analyzer.analyze(samples: .init(repeating: 0, count: 480), sampleRate: 48000)!
      XCTAssertFalse(sample.suspectGap)
      XCTAssertFalse(sample.discontinuity)
      XCTAssertEqual(sample.rmsDB, -120, accuracy: 0.001)
    }
  }
  func testKnownShortDigitalGapIsCandidateOnly() {
    var analyzer = AudioAnalyzer()
    _ = analyzer.analyze(samples: tone(24000), sampleRate: 48000)
    _ = analyzer.analyze(samples: .init(repeating: 0, count: 4800), sampleRate: 48000)
    XCTAssertTrue(analyzer.analyze(samples: tone(4800), sampleRate: 48000)!.suspectGap)
  }
  func testLongNaturalPauseIsNotShortGap() {
    var analyzer = AudioAnalyzer()
    _ = analyzer.analyze(samples: tone(24000), sampleRate: 48000)
    _ = analyzer.analyze(samples: .init(repeating: 0, count: 48000), sampleRate: 48000)
    XCTAssertFalse(analyzer.analyze(samples: tone(4800), sampleRate: 48000)!.suspectGap)
  }
  func testCollectorTimestampGapResetsAudioSuspicion() {
    var analyzer = AudioAnalyzer()
    _ = analyzer.analyze(samples: tone(24000), sampleRate: 48000, streamTime: 0)
    let result = analyzer.analyze(samples: tone(4800), sampleRate: 48000, streamTime: 2)!
    XCTAssertTrue(result.discontinuity)
    XCTAssertFalse(result.suspectGap)
  }
  func testContinuousTimestampsAreNotFaults() {
    var analyzer = AudioAnalyzer()
    for i in 0..<50 {
      let measurement = analyzer.analyze(
        samples: tone(480), sampleRate: 48000, streamTime: Double(i) * 0.01)!
      XCTAssertFalse(measurement.discontinuity)
    }
  }
  func testClippingMeasuresActualNearFullScaleSamples() {
    var analyzer = AudioAnalyzer()
    let measurement = analyzer.analyze(samples: [0, 0.3, 1, -1], sampleRate: 48000)!
    XCTAssertEqual(measurement.clippingFraction, 0.5)
    XCTAssertEqual(measurement.peakDB, 0, accuracy: 0.0001)
  }
  func testInvalidInputIsUnavailableNotNormal() {
    var analyzer = AudioAnalyzer()
    XCTAssertNil(analyzer.analyze(samples: [], sampleRate: 48000))
    XCTAssertNil(analyzer.analyze(samples: [1], sampleRate: 0))
    XCTAssertNil(analyzer.analyze(samples: [.nan], sampleRate: 48000))
  }
  func testProbeRequiresMinimumSamples() {
    XCTAssertFalse(ProbeSummary(samples: [.init(milliseconds: nil)]).degraded)
    XCTAssertTrue(ProbeSummary(samples: (0..<3).map { _ in .init(milliseconds: nil) }).degraded)
  }
  func testProbeRecoveryAndVariation() {
    let good = ProbeSummary(samples: [20, 30, 25].map { .init(milliseconds: $0) })
    XCTAssertFalse(good.degraded)
    XCTAssertEqual(good.medianMilliseconds, 25)
    XCTAssertEqual(good.timeoutFraction, 0)
    XCTAssertTrue(ProbeSummary(samples: [20, 800, 25].map { .init(milliseconds: $0) }).degraded)
  }
  func testInvalidBluetoothSentinelIsNotStrongSignal() {
    XCTAssertNil(BluetoothReading.validRSSI(127))
    XCTAssertEqual(BluetoothReading.validRSSI(-65), -65)
  }
}
