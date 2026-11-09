import SonoskopeCore
import SwiftUI

struct SoftwareUpdateView: View {
  @Bindable var updater: SoftwareUpdater
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Label(L10n.tr("软件更新"), systemImage: "arrow.down.circle").font(.title2.bold())
      Text(updater.status).font(.headline)
      if !updater.availableVersion.isEmpty {
        Text("Sonoskope \(updater.availableVersion)").foregroundStyle(.secondary)
      }
      if [.checking, .downloading, .installing].contains(updater.phase) { ProgressView().controlSize(.small) }
      if !updater.detail.isEmpty { Text(updater.detail).font(.callout).textSelection(.enabled) }
      Text(L10n.tr("后台检查并下载更新。只有点击“安装并重启”后才会退出当前应用；普通退出不会安装更新。"))
        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      Toggle(L10n.tr("自动检查并下载更新"), isOn: Binding(get: { updater.automatic }, set: updater.setAutomatic))
      Spacer()
      HStack {
        Text("Sonoskope \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")").font(.caption).foregroundStyle(.secondary)
        Spacer()
        if updater.isReady {
          Button(L10n.tr("安装并重启"), action: updater.installAndRelaunch).buttonStyle(.borderedProminent)
        } else {
          Button(L10n.tr("检查更新"), action: updater.check).disabled(!updater.canCheck)
        }
      }
    }.padding(24).frame(minWidth: 460, idealWidth: 520, minHeight: 340, idealHeight: 400)
  }
}
