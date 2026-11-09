import AppKit
import SonoskopeCore

@MainActor enum BrandAssets {
  static let applicationIcon: NSImage = {
    if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
      let image = NSImage(contentsOf: url)
    {
      return image
    }
    return NSImage(named: NSImage.applicationIconName)
      ?? NSImage(size: NSSize(width: 32, height: 32))
  }()

  static var menuBarIcon: NSImage {
    let image = applicationIcon.copy() as! NSImage
    image.size = NSSize(width: 18, height: 18)
    image.isTemplate = false
    image.accessibilityDescription = L10n.tr("Sonoskope 音频诊断")
    return image
  }
}
