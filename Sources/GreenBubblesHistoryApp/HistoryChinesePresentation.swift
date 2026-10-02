import Foundation
import GreenBubblesHistory

/// Human-readable UI only. Source identifiers and stored protocol values stay unchanged.
func historyChineseStatus(_ value: String) -> String {
  let labels = [
    "complete": "完整", "partial": "部分可用", "unavailable": "暂不可用", "unknown": "未知",
    "fresh": "最新", "preservedStale": "此前保留", "mixed": "包含历史保留记录",
    "text": "文字", "image": "图片", "animatedImage": "动图", "video": "视频", "voice": "语音",
    "audio": "音频", "document": "文档", "file": "文件", "emoji": "表情", "sticker": "表情",
    "app": "分享内容", "richMedia": "图文内容", "system": "系统通知", "quote": "引用回复",
    "incoming": "收到", "outgoing": "发出", "sent": "已发送", "received": "已接收",
    "self": "本人", "accountHolder": "本人", "member": "成员", "owner": "群主", "admin": "管理员",
    "friend": "好友", "contact": "联系人", "participant": "参与者", "sender": "发送者",
    "group": "群聊", "personal": "个人", "other": "其他", "local": "本机",
    "downloaded": "已下载", "notDownloaded": "尚未下载", "available": "可用", "missing": "未找到",
    "pending": "等待处理", "failed": "失败", "ready": "已就绪", "verified": "已验证",
    "decoded": "已解析", "unsupported": "暂不支持", "truncated": "内容已截短",
    "materializedFromDatabase": "从数据库读取", "referenced": "附件引用", "redacted": "已隐藏",
    "perDatabaseReadTransaction": "每个数据库独立读取", "perDatabaseSnapshot": "每个数据库独立快照",
    "bestEffort": "尽力保持一致", "decrypted": "已解密", "liveEncrypted": "本机加密记录",
    "conversations": "会话", "contacts": "联系人", "messages": "消息", "media": "附件",
  ]
  if let label = labels[value] { return label }
  if value.range(of: #"[\u4e00-\u9fff]"#, options: .regularExpression) != nil { return value }
  return value.isEmpty ? "未知" : "其他状态"
}

func historyUserError(_ error: Error) -> String {
  if let error = error as? HistoryDirectQueryError {
    switch error {
    case .invalidConfiguration: return "无法连接。请检查读取工具、记录文件夹和所选解锁方式。"
    case .invalidKey: return "密钥格式不正确，请使用 32 字节或 64 位十六进制密钥。"
    case .invalidQuery: return "请输入搜索内容，并将长度控制在 16 千字节以内。"
    case .timedOut: return "读取超时，请稍后重试。"
    case .responseTooLarge: return "返回的数据过多，请缩小查询范围后重试。"
    case .commandFailed(_, _, let retryable):
      return retryable
        ? "暂时无法读取，请稍后重试。" : "读取失败，请检查记录来源是否可访问，以及解锁凭据是否正确。"
    case .invalidResponse: return "读取工具返回的数据无法识别，请检查工具版本后重试。"
    }
  }
  if let error = error as? HistoryBundleError {
    switch error {
    case .invalidBundle: return "这不是完整的导出记录文件夹，请选择包含清单及记录文件的文件夹。"
    case .unsafePermissions: return "记录文件权限不符合要求，请使用仅本人可访问的私有文件夹。"
    case .integrityFailure: return "文件完整性检查未通过，记录可能已损坏或被修改。请重新导出后打开。"
    case .unsupportedSchema: return "暂不支持这份记录的格式，请使用兼容版本重新导出。"
    case .indexFailure: return "无法建立本机搜索索引，请检查磁盘空间和访问权限后重试。"
    }
  }
  if let error = error as? HistoryLiveMediaError {
    switch error {
    case .invalidConfiguration: return "请检查读取工具、记录副本、访问规则和操作记录文件位置。"
    case .invalidReplicaKey: return "副本密钥必须为 64 位十六进制字符。"
    case .unauthorized: return "当前访问规则不允许读取此附件。"
    case .sourceChanged: return "读取期间附件发生变化，请重试。"
    case .insufficientSpace: return "磁盘空间不足，无法创建预览副本。"
    case .requestTimedOut: return "附件读取超时，请重试。"
    case .invalidResponse, .artifactMismatch: return "附件校验未通过，请重新读取。"
    case .requestFailed, .previewFailed: return "暂时无法预览此附件，请检查文件是否可用后重试。"
    }
  }
  let text = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
  if text.range(of: #"[\u4e00-\u9fff]"#, options: .regularExpression) != nil { return text }
  return "操作未完成，请检查文件是否可访问，然后重试。"
}

func historyChineseWarning(_ warning: HistoryDirectWarning) -> String {
  if warning.message.range(of: #"[\u4e00-\u9fff]"#, options: .regularExpression) != nil {
    return warning.message
  }
  let code = warning.code.lowercased()
  if code.contains("truncat") || code.contains("limit") { return "部分内容较长，本次仅显示其中一部分。" }
  if code.contains("decode") || code.contains("unsupported") { return "部分消息暂时无法解析，已保留其他可读取内容。" }
  if code.contains("unavailable") || code.contains("missing") { return "部分记录来源暂不可用，当前结果可能不完整。" }
  if code.contains("consisten") || code.contains("atomic") { return "记录来自多个数据库，各部分可能不是同一时刻的数据。" }
  return "本次读取存在限制，结果可能不完整。可刷新后重试。"
}
