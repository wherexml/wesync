import GreenBubblesHistory
import SwiftUI

struct HistoryMergedRecordView: View {
  let record: HistoryMergedRecord
  @State private var opened = false

  var body: some View {
    Button {
      opened = true
    } label: {
      VStack(alignment: .leading, spacing: 8) {
        Text(record.title).font(.headline).lineLimit(2)
        ForEach(Array(record.entries.prefix(3).enumerated()), id: \.offset) { _, entry in
          Text("\(entry.sender)：\(entry.text)").font(.callout).foregroundStyle(.secondary)
            .lineLimit(1)
        }
        if record.entries.isEmpty {
          Text("记录内容暂不可用").font(.callout).foregroundStyle(.secondary)
        }
        Divider()
        HStack {
          Label("聊天记录", systemImage: "text.bubble")
          Spacer()
          Image(systemName: "chevron.right")
        }.font(.caption).foregroundStyle(.secondary)
      }.frame(width: 260, alignment: .leading).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("打开聊天记录：\(record.title)")
    .sheet(isPresented: $opened) {
      VStack(spacing: 0) {
        HStack {
          Text(record.title).font(.headline)
          Spacer()
          Button("完成") { opened = false }.keyboardShortcut(.cancelAction)
        }.padding(20)
        Divider()
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 18) {
            ForEach(Array(record.entries.enumerated()), id: \.offset) { _, entry in
              VStack(alignment: .leading, spacing: 6) {
                HStack {
                  Text(entry.sender).fontWeight(.semibold)
                  Spacer()
                  Text(entry.time).font(.caption).foregroundStyle(.secondary)
                }
                Text(HistoryEmojiText.render(entry.text)).textSelection(.enabled)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }.padding(12).background(
                .primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            }
            if record.incomplete {
              Text("部分记录未能读取，来源内容可能缺失或超出预览范围。")
                .font(.callout).foregroundStyle(.secondary)
            }
            Text("图片、语音等附件当前仅显示类型说明。")
              .font(.caption).foregroundStyle(.secondary)
          }.padding(20)
        }
      }.frame(width: 620, height: 560)
    }
  }
}
