import Foundation
import SonoskopeCore

struct IncidentStore {
  let file: URL
  init() {
    let directory = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(
        "Sonoskope", isDirectory: true)
    file = directory.appendingPathComponent("incidents.json")
  }
  func load(retentionHours: Int) -> [Incident] {
    guard retentionHours > 0, let data = try? Data(contentsOf: file),
      let incidents = try? JSONDecoder().decode([Incident].self, from: data)
    else { return [] }
    return incidents.filter {
      $0.lastSeen > Date().addingTimeInterval(-Double(retentionHours) * 3600)
    }
  }
  func save(_ incidents: [Incident], retentionHours: Int) throws {
    guard retentionHours > 0 else {
      if FileManager.default.fileExists(atPath: file.path) {
        try FileManager.default.removeItem(at: file)
      }
      return
    }
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    let filtered = Array(
      incidents.filter { $0.lastSeen > Date().addingTimeInterval(-Double(retentionHours) * 3600) }
        .suffix(100))
    try JSONEncoder().encode(filtered).write(
      to: file, options: [.atomic, .completeFileProtectionUnlessOpen])
  }
}
