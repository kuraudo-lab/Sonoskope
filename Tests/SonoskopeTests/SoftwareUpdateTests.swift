import CryptoKit
import XCTest
@testable import Sonoskope

final class SoftwareUpdateTests: XCTestCase {
  func testArchiveVerificationRejectsTamperingWrongKeyAndWrongLength() throws {
    let key = Curve25519.Signing.PrivateKey()
    let bytes = Data("signed update archive".utf8)
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    try bytes.write(to: file)
    let package = UpdatePackage(version: "10", displayVersion: "0.2.1", url: URL(string: "https://example.invalid/update.zip")!, signature: try key.signature(for: bytes).base64EncodedString(), length: UInt64(bytes.count))
    try package.verify(file, publicKey: key.publicKey.rawRepresentation.base64EncodedString())
    XCTAssertThrowsError(try package.verify(file, publicKey: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()))
    try Data(repeating: 0, count: bytes.count).write(to: file)
    XCTAssertThrowsError(try package.verify(file, publicKey: key.publicKey.rawRepresentation.base64EncodedString()))
    try Data([0]).write(to: file)
    XCTAssertThrowsError(try package.verify(file, publicKey: key.publicKey.rawRepresentation.base64EncodedString()))
  }

  func testConsentIsRequiredAndCannotTransferToChangedArchive() {
    let original = UpdatePackage(version: "10", displayVersion: "0.2.1", url: URL(string: "https://example.invalid/a.zip")!, signature: "original", length: 100)
    let changed = UpdatePackage(version: "10", displayVersion: "0.2.1", url: original.url, signature: "changed", length: 100)
    var gate = UpdateInstallGate()
    XCTAssertFalse(gate.allows(original))
    gate.approve(original)
    XCTAssertTrue(gate.allows(original))
    XCTAssertFalse(gate.allows(changed))
    gate.reset()
    XCTAssertFalse(gate.allows(original))
  }

  @MainActor func testVerifiedArchiveBridgeServesDownloadAndRejectsOtherPaths() async throws {
    let bytes = Data(repeating: 7, count: 700_000)
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    try bytes.write(to: file)
    let server = VerifiedUpdateServer()
    let url = try await server.start(file: file)
    defer { server.stop() }
    XCTAssertEqual(url.host, "127.0.0.1")
    let session = URLSession(configuration: .ephemeral)
    defer { session.invalidateAndCancel() }
    let (download, response) = try await session.download(from: url)
    XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    XCTAssertEqual(try Data(contentsOf: download), bytes)
    do {
      _ = try await session.download(from: url.deletingLastPathComponent().appendingPathComponent("unknown"))
      XCTFail("Only the random archive path may be served")
    } catch { }
  }
}
