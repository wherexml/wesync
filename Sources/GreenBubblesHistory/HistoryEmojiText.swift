import Foundation

/// Presentation-only aliases. Stored message text and explicit Copy remain lossless.
public enum HistoryEmojiText {
  private static let aliases: [String: String] = [
    "微笑": "🙂", "撇嘴": "😒", "色": "😍", "发呆": "😳", "得意": "😎", "流泪": "😢",
    "害羞": "😊", "闭嘴": "🤐", "睡": "😴", "大哭": "😭", "尴尬": "😅", "发怒": "😡",
    "调皮": "😜", "呲牙": "😁", "惊讶": "😮", "难过": "😞", "酷": "😎", "冷汗": "😰",
    "抓狂": "😫", "吐": "🤮", "偷笑": "🤭", "愉快": "😊", "白眼": "🙄", "傲慢": "😏",
    "困": "🥱", "惊恐": "😱", "憨笑": "😄", "悠闲": "😌", "咒骂": "🤬", "疑问": "❓",
    "嘘": "🤫", "晕": "😵", "衰": "😞", "敲打": "🔨", "再见": "👋", "擦汗": "😓",
    "抠鼻": "👃", "鼓掌": "👏", "坏笑": "😏", "左哼哼": "😤", "右哼哼": "😤", "哈欠": "🥱",
    "鄙视": "😒", "委屈": "🥺", "快哭了": "🥺", "阴险": "😈", "亲亲": "😘", "可怜": "🥺",
    "笑脸": "😄", "生病": "🤒", "脸红": "😳", "破涕为笑": "😂", "恐惧": "😨", "失望": "😔",
    "无语": "😑", "嘿哈": "😄", "捂脸": "🤦", "奸笑": "😏", "机智": "😎", "皱眉": "🙁",
    "耶": "✌️", "吃瓜": "🍉", "加油": "💪", "汗": "😓", "天啊": "😱", "Emm": "🤔",
    "社会社会": "🤝", "旺柴": "🐶", "好的": "👌", "打脸": "🤦", "哇": "🤩", "翻白眼": "🙄",
    "666": "👍", "让我看看": "🧐", "叹气": "😮‍💨", "苦涩": "🥲", "裂开": "🫠",
    "爱心": "❤️", "心碎": "💔", "拥抱": "🤗", "强": "👍", "弱": "👎", "握手": "🤝",
    "胜利": "✌️", "抱拳": "🙏", "勾引": "🫴", "拳头": "✊", "OK": "👌", "合十": "🙏",
    "玫瑰": "🌹", "凋谢": "🥀", "嘴唇": "💋", "礼物": "🎁", "红包": "🧧", "發": "🀅",
    "福": "🧧", "庆祝": "🎉", "爆竹": "🧨", "烟花": "🎆", "炸弹": "💣", "便便": "💩",
    "太阳": "☀️", "月亮": "🌙", "蛋糕": "🎂", "咖啡": "☕️", "啤酒": "🍺", "西瓜": "🍉",
    "Tears": "😢", "Cry": "😭", "Smile": "🙂", "Grin": "😁", "Chuckle": "🤭", "Sob": "😭",
    "Joyful": "😊", "Facepalm": "🤦", "ThumbsUp": "👍", "Heart": "❤️", "Salute": "🫡",
  ]
  private static let tokens = try! NSRegularExpression(
    pattern: #"(?:https?://|www\.)[^\s]+|\[[^\[\]\r\n]{1,20}\]"#)
  public static func render(_ text: String) -> String {
    let source = text as NSString
    var output = ""
    var offset = 0
    for match in tokens.matches(in: text, range: NSRange(location: 0, length: source.length)) {
      output += source.substring(
        with: NSRange(location: offset, length: match.range.location - offset))
      let token = source.substring(with: match.range)
      if token.hasPrefix("["), let emoji = aliases[String(token.dropFirst().dropLast())] {
        output += emoji
      } else {
        output += token
      }
      offset = match.range.location + match.range.length
    }
    output += source.substring(from: offset)
    return output
  }
}
