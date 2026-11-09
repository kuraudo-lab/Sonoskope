import Foundation
import SonoskopeCore
import UserNotifications

@MainActor final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
  var openIncident: ((UUID) -> Void)?
  private let center = UNUserNotificationCenter.current()
  override init() {
    super.init()
    center.delegate = self
  }
  func authorize() async -> String {
    do {
      let granted = try await center.requestAuthorization(options: [.alert])
      return granted ? "已允许无声通知；仍遵循系统专注模式。" : "通知未授权，仍可从菜单栏查看问题。"
    } catch { return "通知权限不可用：" + error.localizedDescription }
  }
  func post(_ incident: Incident) {
    let content = UNMutableNotificationContent()
    content.title = incident.title
    content.body =
      incident.direction.label + " · "
      + (incident.confidence == .suspected ? "疑似异常，原因待确认" : "点击查看证据与下一步")
    content.userInfo = ["incident": incident.id.uuidString]
    content.threadIdentifier = "Sonoskope.diagnostics"
    // No sound, critical interruption, Focus bypass, or automatically opened windows.
    center.add(.init(identifier: incident.id.uuidString, content: content, trigger: nil))
  }
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let id = (response.notification.request.content.userInfo["incident"] as? String).flatMap(
      UUID.init(uuidString:))
    Task { @MainActor in if let id { self.openIncident?(id) } }
    completionHandler()
  }
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .list])
  }
}
