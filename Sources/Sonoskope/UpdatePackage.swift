import CryptoKit
import Foundation

struct UpdatePackage: Codable, Equatable {
  let version: String
  let displayVersion: String
  let url: URL
  let signature: String
  let length: UInt64

  func verify(_ file: URL, publicKey: String) throws {
    guard let keyData = Data(base64Encoded: publicKey), let signature = Data(base64Encoded: signature),
      length > 0, length <= 256 * 1024 * 1024
    else { throw UpdateValidationError.invalidPackage }
    let values = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    guard values.isRegularFile == true, UInt64(values.fileSize ?? 0) == length else {
      throw UpdateValidationError.invalidPackage
    }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
    guard key.isValidSignature(signature, for: try Data(contentsOf: file, options: .mappedIfSafe)) else {
      throw UpdateValidationError.invalidSignature
    }
  }

  var cacheName: String {
    SHA256.hash(data: Data((url.absoluteString + signature).utf8)).map { String(format: "%02x", $0) }.joined() + ".zip"
  }
}

enum UpdateValidationError: Error {
  case invalidPackage, invalidSignature, changedUpdate
}

/// Consent is tied to the exact archive, not just the advertised version number.
struct UpdateInstallGate {
  private(set) var approved: UpdatePackage?
  mutating func approve(_ package: UpdatePackage) { approved = package }
  mutating func reset() { approved = nil }
  func allows(_ package: UpdatePackage) -> Bool { approved == package }
}
