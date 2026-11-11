import Foundation
import UIKit

enum AuthState: Equatable {
    case loading
    case phone
    case code(String)
    case password(String)
    case ready
    case unsupported(String)
}

/// Всё состояние Телеграма. Изменяется только на главном потоке.
final class TGStore: ObservableObject {
    static let shared = TGStore()

    @Published var auth: AuthState = .loading
    @Published var chats: [Int64: ChatItem] = [:]
    @Published var messages: [Int64: [MessageItem]] = [:]
    @Published var typing: [Int64: String] = [:]
    @Published var lastError: String?
    @Published var myName = ""
    @Published var myPhone = ""

    private var users: [Int64: String] = [:]
    private var selfDeleted = Set<String>()
    var openChatId: Int64?
    var appActive = true

    let client = TDClient.shared
    let ghost = GhostSettings.shared
    let archive = MessageArchive.shared

    private init() {
        client.onUpdate = { [weak self] u in
            DispatchQueue.main.async { self?.handle(u) }
        }
        ghost.onChange = { [weak self] in self?.applyOnline() }
        client.send(["@type": "getOption", "name": "version"])
    }

    var sortedChats: [ChatItem] {
        chats.values.filter { $0.order != 0 }.sorted { $0.order > $1.order }
    }

    // MARK: - Updates

    private func handle(_ u: JSON) {
        switch u.type {
        case "updateAuthorizationState":
            handleAuth(u.obj("authorization_state") ?? [:])

        case "updateUser":
            if let user = u.obj("user"), let id = user.int64("id") {
                users[id] = [user.str("first_name"), user.str("last_name")]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            }

        case "updateNewChat":
            if let c = u.obj("chat") { addChat(c) }

        case "updateChatTitle":
            if let id = u.int64("chat_id") { chats[id]?.title = u.str("title") ?? "" }

        case "updateChatPhoto":
            if let id = u.int64("chat_id") { chats[id]?.photoFileId = u.obj("photo")?.obj("small")?.int("id") }

        case "updateChatPosition":
            if let id = u.int64("chat_id"), let pos = u.obj("position"), pos.obj("list")?.type == "chatListMain" {
                chats[id]?.order = pos.int64("order") ?? 0
            }

        case "updateChatLastMessage":
            if let id = u.int64("chat_id") {
                applyLastMessage(id, u.obj("last_message"))
                applyPositions(id, u.arr("positions"))
            }

        case "updateChatReadInbox":
            if let id = u.int64("chat_id") { chats[id]?.unread = u.int("unread_count") ?? 0 }

        case "updateChatReadOutbox":
            if let id = u.int64("chat_id") { chats[id]?.lastReadOutbox = u.int64("last_read_outbox_message_id") ?? 0 }

        case "updateNewMessage":
            if let m = u.obj("message") { onNewMessage(m) }

        case "updateMessageSendSucceeded":
            if let m = u.obj("message"), let oldId = u.int64("old_message_id") {
                let item = makeMessage(m)
                if let idx = messages[item.chatId]?.firstIndex(where: { $0.id == oldId }) {
                    messages[item.chatId]?[idx] = item
                }
                archive.remember(item)
            }

        case "updateMessageContent":
            onContentChanged(u)

        case "updateMessageEdited":
            if let c = u.int64("chat_id"), let id = u.int64("message_id"),
               let idx = messages[c]?.firstIndex(where: { $0.id == id }) {
                messages[c]?[idx].isEdited = true
            }

        case "updateDeleteMessages":
            onDelete(u)

        case "updateChatAction":
            onChatAction(u)

        default:
            break
        }
    }

    private func handleAuth(_ s: JSON) {
        switch s.type {
        case "authorizationStateWaitTdlibParameters":
            sendParameters()
        case "authorizationStateWaitPhoneNumber":
            auth = .phone
        case "authorizationStateWaitCode":
            auth = .code(s.obj("code_info")?.str("phone_number") ?? "")
        case "authorizationStateWaitPassword":
            auth = .password(s.str("password_hint") ?? "")
        case "authorizationStateReady":
            auth = .ready
            onReady()
        case "authorizationStateClosed":
            chats = [:]; messages = [:]; users = [:]
            auth = .loading
            client.recreate()
        case "authorizationStateLoggingOut", "authorizationStateClosing":
            auth = .loading
        default:
            auth = .unsupported("Сначала заверши регистрацию или вход в официальном Telegram, потом попробуй снова.")
        }
    }

    private func sendParameters() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("tdlib")
        client.send([
            "@type": "setTdlibParameters",
            "use_test_dc": false,
            "database_directory": dir.path,
            "files_directory": dir.appendingPathComponent("files").path,
            "database_encryption_key": "",
            "use_file_database": true,
            "use_chat_info_database": true,
            "use_message_database": true,
            "use_secret_chats": false,
            "api_id": Secrets.apiId,
            "api_hash": Secrets.apiHash,
            "system_language_code": "ru",
            "device_model": UIDevice.current.model,
            "system_version": UIDevice.current.systemVersion,
            "application_version": "0.1",
        ]) { [weak self] r in
            if r.type == "error" { DispatchQueue.main.async { self?.lastError = r.str("message") } }
        }
    }

    private func onReady() {
        applyOnline()
        client.send(["@type": "getMe"]) { [weak self] me in
            DispatchQueue.main.async {
                self?.myName = [me.str("first_name"), me.str("last_name")].compactMap { $0 }.joined(separator: " ")
                self?.myPhone = "+" + (me.str("phone_number") ?? "")
            }
        }
        Task {
            for _ in 0..<5 {
                do { try await client.call(["@type": "loadChats", "chat_list": ["@type": "chatListMain"], "limit": 100]) }
                catch { break } // 404 — все чаты загружены
            }
        }
    }

    // MARK: - Чаты

    private func addChat(_ c: JSON) {
        guard let id = c.int64("id") else { return }
        var chat = ChatItem(id: id, title: c.str("title") ?? "")
        chat.photoFileId = c.obj("photo")?.obj("small")?.int("id")
        chat.unread = c.int("unread_count") ?? 0
        chat.lastReadOutbox = c.int64("last_read_outbox_message_id") ?? 0
        if let t = c.obj("type") {
            switch t.type {
            case "chatTypeBasicGroup": chat.isGroup = true
            case "chatTypeSupergroup": if t.bool("is_channel") { chat.isChannel = true } else { chat.isGroup = true }
            default: break
            }
        }
        chats[id] = chat
        applyLastMessage(id, c.obj("last_message"))
        applyPositions(id, c.arr("positions"))
    }

    private func applyLastMessage(_ id: Int64, _ m: JSON?) {
        guard let m else { return }
        chats[id]?.lastText = MessageContent.preview(m.obj("content"))
        chats[id]?.lastDate = m.int("date") ?? 0
        chats[id]?.lastOutgoing = m.bool("is_outgoing")
        chats[id]?.lastMessageId = m.int64("id") ?? 0
    }

    private func applyPositions(_ id: Int64, _ positions: [JSON]) {
        for p in positions where p.obj("list")?.type == "chatListMain" {
            chats[id]?.order = p.int64("order") ?? 0
        }
    }

    // MARK: - Сообщения

    func makeMessage(_ m: JSON) -> MessageItem {
        let content = MessageContent.parse(m.obj("content"))
        var sender: String?
        if let s = m.obj("sender_id") {
            if let uid = s.int64("user_id") { sender = users[uid] }
            else if let cid = s.int64("chat_id") { sender = chats[cid]?.title }
        }
        var item = MessageItem(id: m.int64("id") ?? 0,
                               chatId: m.int64("chat_id") ?? 0,
                               isOutgoing: m.bool("is_outgoing"),
                               date: m.int("date") ?? 0,
                               text: content.text,
                               senderName: sender,
                               photoFileId: content.photo)
        item.isEdited = (m.int("edit_date") ?? 0) > 0
        item.editHistory = archive.edits(item.key)
        return item
    }

    private func onNewMessage(_ m: JSON) {
        let item = makeMessage(m)
        archive.remember(item)
        guard messages[item.chatId] != nil else { return }
        if !(messages[item.chatId]?.contains(where: { $0.id == item.id }) ?? false) {
            messages[item.chatId]?.append(item)
        }
        if item.chatId == openChatId, appActive, !item.isOutgoing, !ghost.noRead {
            markRead(item.chatId, ids: [item.id])
        }
    }

    private func onContentChanged(_ u: JSON) {
        guard let c = u.int64("chat_id"), let id = u.int64("message_id") else { return }
        let key = "\(c):\(id)"
        let new = MessageContent.parse(u.obj("new_content"))
        let idx = messages[c]?.firstIndex(where: { $0.id == id })
        let old = idx.map { messages[c]![$0].text } ?? archive.cached(key)?.text
        if ghost.saveEdits, let old, old != new.text, !old.isEmpty {
            archive.addEdit(key, old: old)
        }
        if let idx {
            messages[c]?[idx].text = new.text
            messages[c]?[idx].photoFileId = new.photo
            messages[c]?[idx].editHistory = archive.edits(key)
            if let item = messages[c]?[idx] { archive.remember(item) }
        } else if var cached = archive.cached(key) {
            cached.text = new.text
            archive.remember(cached)
        }
    }

    private func onDelete(_ u: JSON) {
        guard let c = u.int64("chat_id") else { return }
        // from_cache — TDLib просто чистит кэш, сообщение на самом деле не удалено
        guard u.bool("is_permanent"), !u.bool("from_cache") else { return }
        for id in u.int64s("message_ids") {
            let key = "\(c):\(id)"
            let idx = messages[c]?.firstIndex(where: { $0.id == id })
            if ghost.saveDeleted, !selfDeleted.contains(key),
               let item = idx.map({ messages[c]![$0] }) ?? archive.cached(key) {
                archive.addDeleted(item)
                if let idx { messages[c]?[idx].isDeleted = true }
            } else if let idx {
                messages[c]?.remove(at: idx)
            }
        }
    }

    private func onChatAction(_ u: JSON) {
        guard let c = u.int64("chat_id") else { return }
        if u.obj("action")?.type == "chatActionCancel" { typing[c] = nil; return }
        var who = ""
        if chats[c]?.isGroup == true, let uid = u.obj("sender_id")?.int64("user_id") {
            who = (users[uid]?.components(separatedBy: " ").first ?? "") + " "
        }
        let text: String
        switch u.obj("action")?.type {
        case "chatActionRecordingVoiceNote": text = "записывает голосовое…"
        case "chatActionRecordingVideoNote": text = "записывает кружок…"
        case "chatActionUploadingPhoto": text = "отправляет фото…"
        case "chatActionChoosingSticker": text = "выбирает стикер…"
        default: text = "печатает…"
        }
        typing[c] = who + text
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            if self?.typing[c] == who + text { self?.typing[c] = nil }
        }
    }

    func loadHistory(_ chatId: Int64) async {
        var raw: [JSON] = []
        var from: Int64 = 0
        for _ in 0..<6 {
            guard let r = try? await client.call([
                "@type": "getChatHistory", "chat_id": chatId,
                "from_message_id": from, "offset": 0, "limit": 50, "only_local": false,
            ]) else { break }
            let batch = r.arr("messages")
            guard let last = batch.last?.int64("id") else { break }
            raw.append(contentsOf: batch)
            from = last
            if raw.count >= 80 { break }
        }
        await MainActor.run {
            var items = raw.map(makeMessage)
            items.forEach(archive.remember)
            let minId = items.map(\.id).min() ?? 0
            let ids = Set(items.map(\.id))
            let restored = archive.deleted(in: chatId).filter { $0.id >= minId && !ids.contains($0.id) }
            items.append(contentsOf: restored)
            messages[chatId] = items.sorted { $0.id < $1.id }
        }
    }

    // MARK: - Действия

    func openChat(_ id: Int64) {
        openChatId = id
        client.send(["@type": "openChat", "chat_id": id])
    }

    func closeChat(_ id: Int64) {
        if openChatId == id { openChatId = nil }
        client.send(["@type": "closeChat", "chat_id": id])
    }

    /// Отметить прочитанным (всегда отправляет на сервер).
    func markRead(_ chatId: Int64, ids: [Int64]) {
        guard !ids.isEmpty else { return }
        client.send(["@type": "viewMessages", "chat_id": chatId, "message_ids": ids, "force_read": true])
    }

    func markChatRead(_ chatId: Int64) {
        if let last = chats[chatId]?.lastMessageId, last != 0 { markRead(chatId, ids: [last]) }
    }

    func autoReadOnOpen(_ chatId: Int64) {
        guard !ghost.noRead else { return }
        let ids = (messages[chatId] ?? []).filter { !$0.isOutgoing && !$0.isDeleted }.suffix(50).map(\.id)
        markRead(chatId, ids: ids)
    }

    func sendText(_ chatId: Int64, _ text: String) {
        client.send([
            "@type": "sendMessage", "chat_id": chatId,
            "input_message_content": ["@type": "inputMessageText",
                                      "text": ["@type": "formattedText", "text": text]],
        ]) { [weak self] r in
            DispatchQueue.main.async {
                if r.type == "error" { self?.lastError = r.str("message"); return }
                self?.afterSend(chatId)
            }
        }
    }

    private func afterSend(_ chatId: Int64) {
        if ghost.noRead && ghost.readOnSend { markChatRead(chatId) }
        if ghost.noOnline && ghost.offlineAfterSend {
            // Сервер помечает нас онлайн при отправке — сразу возвращаемся в офлайн.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.setOnline(true)
                self?.setOnline(false)
            }
        }
    }

    private var lastTypingSent = Date.distantPast
    func userIsTyping(_ chatId: Int64) {
        guard !ghost.noTyping, Date().timeIntervalSince(lastTypingSent) > 4 else { return }
        lastTypingSent = Date()
        client.send(["@type": "sendChatAction", "chat_id": chatId, "action": ["@type": "chatActionTyping"]])
    }

    func delete(_ m: MessageItem) {
        selfDeleted.insert(m.key)
        client.send(["@type": "deleteMessages", "chat_id": m.chatId, "message_ids": [m.id], "revoke": true])
        if m.isDeleted { messages[m.chatId]?.removeAll { $0.id == m.id } }
    }

    func applyOnline() {
        guard auth == .ready else { return }
        setOnline(appActive && !ghost.noOnline)
    }

    private func setOnline(_ v: Bool) {
        client.send(["@type": "setOption", "name": "online", "value": ["@type": "optionValueBoolean", "value": v]])
    }

    // MARK: - Вход

    func submitPhone(_ phone: String) { authCall(["@type": "setAuthenticationPhoneNumber", "phone_number": phone]) }
    func submitCode(_ code: String) { authCall(["@type": "checkAuthenticationCode", "code": code]) }
    func submitPassword(_ pass: String) { authCall(["@type": "checkAuthenticationPassword", "password": pass]) }
    func logout() { client.send(["@type": "logOut"]) }

    private func authCall(_ req: JSON) {
        lastError = nil
        client.send(req) { [weak self] r in
            if r.type == "error" { DispatchQueue.main.async { self?.lastError = r.str("message") } }
        }
    }
}

// MARK: - Загрузка картинок

enum ImageCache {
    private static let cache = NSCache<NSNumber, UIImage>()

    static func load(_ fileId: Int) async -> UIImage? {
        if let img = cache.object(forKey: fileId as NSNumber) { return img }
        guard let r = try? await TDClient.shared.call([
            "@type": "downloadFile", "file_id": fileId, "priority": 1,
            "offset": 0, "limit": 0, "synchronous": true,
        ]), let path = r.obj("local")?.str("path"), !path.isEmpty,
              let img = UIImage(contentsOfFile: path) else { return nil }
        cache.setObject(img, forKey: fileId as NSNumber)
        return img
    }
}
