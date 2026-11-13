import AppKit

struct FloatingPlacement {
  static let size = NSSize(width: 420, height: 350)
  static func origin(in visibleFrame: CGRect, size: CGSize = size, inset: CGFloat = 18) -> CGPoint {
    CGPoint(x: max(visibleFrame.minX, visibleFrame.maxX - size.width - inset),
      y: max(visibleFrame.minY, visibleFrame.maxY - size.height - inset))
  }
  static func appKitRect(_ bounds: CGRect, primaryTop: CGFloat) -> CGRect {
    CGRect(x: bounds.minX, y: primaryTop - bounds.maxY, width: bounds.width, height: bounds.height)
  }
  static func screenIndex(window: CGRect?, screens: [CGRect], pointer: CGPoint) -> Int? {
    if let window {
      let areas = screens.map { frame -> CGFloat in
        let overlap = frame.intersection(window)
        return overlap.isNull ? 0 : overlap.width * overlap.height
      }
      if let best = areas.indices.max(by: { areas[$0] < areas[$1] }), areas[best] > 0 { return best }
    }
    return screens.firstIndex(where: { $0.contains(pointer) }) ?? screens.indices.first
  }
}

/// Window geometry only, on a serial background executor. No screen images or AX permission.
actor ActiveWindowGeometry {
  func bounds(pid: pid_t) -> CGRect? {
    guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
      kCGNullWindowID) as? [[String: Any]] else { return nil }
    for window in windows {
      guard window[kCGWindowOwnerPID as String] as? Int == Int(pid),
        window[kCGWindowLayer as String] as? Int == 0,
        let bounds = window[kCGWindowBounds as String] as? [String: Any],
        let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
        rect.width > 0, rect.height > 0 else { continue }
      return rect
    }
    return nil
  }
}
