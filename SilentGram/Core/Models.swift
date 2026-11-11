import Foundation

struct ChatItem: Identifiable, Equatable {
    let id: Int64
    var title: String
    var lastText = ""
    var lastDate = 0
    var lastOutgoing = false
    var lastMessageId: Int64 = 0
    var unread = 0
    var order: Int64 = 0
    var photoFileId: Int?
    var isChannel = false
    var isGroup = false
    var lastReadOutbox: Int64 = 0
}

struct MessageItem: Identifiable, Equatable, Codable {
    let id: Int64
    let chatId: Int64
    var isOutgoing: Bool
    var date: Int
    var text: String
    var senderName: String?
    var photoFileId: Int?
    var isDeleted = false
    var isEdited = false
    var editHistory: [String] = []

    var key: String { "\(chatId):\(id)" }
}

enum MessageContent {
    /// Текст сообщения и id фото (если есть).
    static func parse(_ c: JSON?) -> (text: String, photo: Int?) {
        guard let c else { return ("", nil) }
        let caption = c.obj("caption")?.str("text") ?? ""
        func with(_ label: String) -> String { caption.isEmpty ? label : "\(label)\n\(caption)" }
        switch c.type {
        case "messageText":
            return (c.obj("text")?.str("text") ?? "", nil)
        case "messagePhoto":
            let sizes = c.obj("photo")?.arr("sizes") ?? []
            return (caption, sizes.last?.obj("photo")?.int("id"))
        case "messageVideo": return (with("🎬 Видео"), nil)
        case "messageAnimation": return (with("GIF"), nil)
        case "messageVoiceNote": return (with("🎤 Голосовое сообщение"), nil)
        case "messageVideoNote": return ("⏺ Видеосообщение", nil)
        case "messageAudio":
            let a = c.obj("audio")
            return (with("🎵 \(a?.str("performer") ?? "") — \(a?.str("title") ?? "Аудио")"), nil)
        case "messageDocument":
            return (with("📎 \(c.obj("document")?.str("file_name") ?? "Файл")"), nil)
        case "messageSticker":
            return ("\(c.obj("sticker")?.str("emoji") ?? "") Стикер", nil)
        case "messageContact": return ("👤 Контакт", nil)
        case "messageLocation", "messageVenue": return ("📍 Геопозиция", nil)
        case "messageCall": return ("📞 Звонок", nil)
        case "messagePoll":
            let q = c.obj("poll")?.obj("question")?.str("text") ?? c.obj("poll")?.str("question") ?? ""
            return ("📊 \(q)", nil)
        case "messageChatAddMembers", "messageChatJoinByLink": return ("Вступил(а) в группу", nil)
        case "messagePinMessage": return ("📌 Закреплено сообщение", nil)
        default: return ("Сообщение", nil)
        }
    }

    static func preview(_ c: JSON?) -> String {
        let p = parse(c)
        if p.photo != nil { return p.text.isEmpty ? "🖼 Фото" : "🖼 \(p.text)" }
        return p.text.replacingOccurrences(of: "\n", with: " ")
    }
}

func formatTime(_ unix: Int, short: Bool = false) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(unix))
    let f = DateFormatter()
    f.locale = Locale(identifier: "ru_RU")
    if short || Calendar.current.isDateInToday(date) {
        f.dateFormat = "HH:mm"
    } else if Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 99 < 7 {
        f.dateFormat = "EE"
    } else {
        f.dateFormat = "dd.MM.yy"
    }
    return f.string(from: date)
}
