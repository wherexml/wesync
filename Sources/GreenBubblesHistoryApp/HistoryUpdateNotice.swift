import SwiftUI

struct HistoryUpdateNotice: View {
  @ObservedObject var updater: HistoryUpdater

  private var title: String {
    switch updater.phase {
    case .ready: "更新已就绪"
    case .checking: "正在检查更新"
    case .downloading: "正在下载更新"
    case .verifying: "正在验证更新"
    case .installing: "正在重启"
    case .current: "已是最新版本"
    case .localBuild: "本机开发版"
    case .permissionRequired: "需手动更新"
    case .failed: "更新未完成"
    case .idle: "软件更新"
    }
  }

  var body: some View {
    if updater.noticeVisible {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: "arrow.down.circle")
          .font(.system(size: 23, weight: .regular))
          .foregroundStyle(HistoryDesign.accent)
          .padding(.top, 1)
        VStack(alignment: .leading, spacing: 10) {
          VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 14, weight: .semibold))
            if !updater.availableVersion.isEmpty {
              Text("v\(updater.availableVersion)")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            }
          }
          if updater.phase == .downloading {
            if let progress = updater.progress {
              ProgressView(value: progress).tint(HistoryDesign.accent)
            } else {
              ProgressView().controlSize(.small)
            }
          }
          switch updater.phase {
          case .ready:
            Button("重启更新") { updater.install() }
              .buttonStyle(.borderedProminent).tint(HistoryDesign.accent)
              .accessibilityIdentifier("update-restart")
          case .checking, .downloading:
            if updater.canCancel {
              Button("取消") { updater.cancel() }.buttonStyle(.bordered)
            }
          case .localBuild, .permissionRequired:
            Button("查看版本") { updater.openReleases() }.buttonStyle(.bordered)
          case .failed:
            Button("重试") { updater.check() }.buttonStyle(.bordered)
          case .verifying, .installing:
            ProgressView().controlSize(.small)
          case .current, .idle:
            EmptyView()
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Button {
          updater.closeNotice()
        } label: {
          Image(systemName: "xmark").font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary).frame(width: 20, height: 20)
        }
        .buttonStyle(.plain).disabled(updater.phase == .installing)
        .accessibilityLabel("关闭更新提醒")
      }
      .controlSize(.small)
      .padding(16)
      .frame(width: 320)
      .background(HistoryDesign.card, in: RoundedRectangle(cornerRadius: 16))
      .overlay {
        RoundedRectangle(cornerRadius: 16).strokeBorder(HistoryDesign.border, lineWidth: 0.5)
      }
      .shadow(color: .black.opacity(0.14), radius: 18, x: 0, y: 6)
      .accessibilityElement(children: .contain)
      .accessibilityLabel("软件更新")
      .accessibilityIdentifier("update-notice")
    }
  }
}
