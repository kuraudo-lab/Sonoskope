import XCTest

@testable import SonoskopeCore

final class LocalizationTests: XCTestCase {
  func testPreferredLanguageOrderAndFallback() {
    XCTAssertEqual(AppLanguage.resolve(["zh-Hans-CN", "en-US"]), .chinese)
    XCTAssertEqual(AppLanguage.resolve(["zh-Hant-TW"]), .chinese)
    XCTAssertEqual(AppLanguage.resolve(["zh_HK"]), .chinese)
    XCTAssertEqual(AppLanguage.resolve(["en-GB", "zh-CN"]), .english)
    XCTAssertEqual(AppLanguage.resolve(["ja-JP", "zh-Hans"]), .chinese)
    XCTAssertEqual(AppLanguage.resolve(["ja-JP", "en-US"]), .english)
    XCTAssertEqual(AppLanguage.resolve(["fr-FR"]), .english)
    XCTAssertEqual(AppLanguage.resolve([]), .english)
  }
  func testBundledCatalogsHaveMatchingKeysAndFormatSpecifiers() throws {
    let english = try XCTUnwrap(L10n.catalogs[.english])
    let chinese = try XCTUnwrap(L10n.catalogs[.chinese])
    XCTAssertGreaterThan(english.count, 200)
    XCTAssertEqual(Set(english.keys), Set(chinese.keys))
    let specifier = try NSRegularExpression(pattern: #"%(?:\d+\$)?(?:\.\d+)?[@df]|%%"#)
    for (key, translation) in english {
      XCTAssertFalse(translation.isEmpty, key)
      XCTAssertNil(translation.range(of: #"[\p{Han}]"#, options: .regularExpression), key)
      func formats(_ text: String) -> [String] {
        specifier.matches(in: text, range: NSRange(text.startIndex..., in: text))
          .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
      }
      XCTAssertEqual(formats(key), formats(translation), key)
      XCTAssertEqual(chinese[key], key)
    }
  }
  func testInterpolationsKeepDeviceNamesAndDoNotReinterpretPlaceholders() {
    let name = "耳机 %@ Test"
    let text: LocalizedText = "\(name) 从音频设备列表消失（2 秒轮询）"
    XCTAssertEqual(
      text.resolved(in: .english),
      "耳机 %@ Test disappeared from the audio device list (2-second polling)")
    XCTAssertEqual(text.resolved(in: .chinese), "耳机 %@ Test 从音频设备列表消失（2 秒轮询）")
  }
  func testPersistedIncidentCanRenderInBothLanguagesAfterReload() throws {
    var engine = DiagnosticEngine()
    _ = engine.ingest(
      .init(
        kind: .deviceDisconnected, source: "headset",
        message: "\("Test Headset") 从音频设备列表消失（2 秒轮询）"), audioActive: true)
    _ = engine.ingest(
      .init(
        kind: .deviceRestored, source: "headset",
        message: "\("Test Headset") 重新可用"), audioActive: true)
    let data = try JSONEncoder().encode(engine.incidents)
    let restored = try JSONDecoder().decode([Incident].self, from: data)[0]
    XCTAssertEqual(restored.title.resolved(in: .english), "Audio device disconnected")
    XCTAssertEqual(restored.title.resolved(in: .chinese), "音频设备连接中断")
    XCTAssertEqual(restored.endReason?.resolved(in: .english), "Test Headset is available again")
    XCTAssertEqual(restored.evidence[0].message.arguments, ["Test Headset"])
  }
  func testLegacyPlainStringIncidentMigratesWithoutLosingIdentity() throws {
    var engine = DiagnosticEngine()
    for event in DemoScenario.recovered.events() { _ = engine.ingest(event, audioActive: true) }
    let original = engine.incidents[0]
    var json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
    // Recreate the v0.1.0 schema: human-readable text was stored as plain strings.
    json["title"] = original.title.resolved(in: .chinese)
    json["explanation"] = original.explanation.resolved(in: .chinese)
    json["nextStep"] = original.nextStep.resolved(in: .chinese)
    json["endReason"] = "Test Headset 重新可用"
    json["evidence"] = try original.evidence.map { event -> [String: Any] in
      var entry = try XCTUnwrap(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(event)) as? [String: Any])
      entry["message"] = event.message.resolved(in: .chinese)
      return entry
    }
    let restored = try JSONDecoder().decode(
      Incident.self, from: JSONSerialization.data(withJSONObject: json))
    XCTAssertEqual(restored.id, original.id)
    XCTAssertEqual(restored.recovered, original.recovered)
    XCTAssertEqual(restored.title.resolved(in: .english), "Audio device disconnected")
    XCTAssertEqual(restored.endReason?.resolved(in: .english), "Test Headset is available again")
    XCTAssertEqual(
      restored.evidence[0].message.resolved(in: .english), "Demo: headset disconnected")
  }
  func testUnknownHistoricalTextAndSystemErrorsRemainVerbatim() throws {
    let original = "Third-party error: 未知设备 %@"
    let decoded = try JSONDecoder().decode(LocalizedText.self, from: JSONEncoder().encode(original))
    XCTAssertEqual(decoded.resolved(in: .english), original)
    XCTAssertEqual(decoded.resolved(in: .chinese), original)
    XCTAssertTrue(decoded.verbatim)
  }
  func testAllDemoDiagnosticsResolveInEnglish() {
    for scenario in DemoScenario.allCases {
      var engine = DiagnosticEngine()
      for event in scenario.events() { _ = engine.ingest(event, audioActive: true) }
      for incident in engine.incidents {
        let texts =
          [incident.title, incident.explanation, incident.nextStep]
          + incident.evidence.map(\.message) + [incident.endReason].compactMap { $0 }
        for text in texts {
          XCTAssertNil(
            text.resolved(in: .english).range(of: #"[\p{Han}]"#, options: .regularExpression),
            text.key)
        }
      }
    }
  }
}
