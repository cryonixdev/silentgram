import SwiftUI

struct ChatView: View {
    let chatId: Int64
    @EnvironmentObject var store: TGStore
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var ghost: GhostSettings
    @State private var text = ""
    @State private var historyFor: MessageItem?

    private var chat: ChatItem? { store.chats[chatId] }
    private var msgs: [MessageItem] { store.messages[chatId] ?? [] }

    private var subtitle: String {
        if let t = store.typing[chatId] { return t }
        if ghost.enabled { return "👻 режим призрака" }
        if chat?.isChannel == true { return "канал" }
        if chat?.isGroup == true { return "группа" }
        return ""
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(msgs) { m in
                            MessageBubble(message: m,
                                          showSender: chat?.isGroup == true,
                                          isRead: m.id <= (chat?.lastReadOutbox ?? 0))
                                .id(m.id)
                                .contextMenu { menu(for: m) }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: msgs.last?.id) { id in
                    guard let id else { return }
                    withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                }
                .onAppear {
                    if let id = msgs.last?.id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            if chat?.isChannel != true { inputBar }
        }
        .background(ChatBackground())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(chat?.title ?? "").font(.headline).lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.caption)
                            .foregroundColor(store.typing[chatId] != nil ? theme.accent : .secondary)
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { store.markChatRead(chatId) } label: {
                        Label("Отметить прочитанным", systemImage: "checkmark.message")
                    }
                } label: {
                    AvatarView(id: chatId, title: chat?.title ?? "", fileId: chat?.photoFileId, size: 34)
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .task {
            store.openChat(chatId)
            await store.loadHistory(chatId)
            store.autoReadOnOpen(chatId)
        }
        .onDisappear { store.closeChat(chatId) }
        .sheet(item: $historyFor) { EditHistoryView(message: $0) }
    }

    @ViewBuilder
    private func menu(for m: MessageItem) -> some View {
        Button { UIPasteboard.general.string = m.text } label: {
            Label("Копировать", systemImage: "doc.on.doc")
        }
        if !m.editHistory.isEmpty {
            Button { historyFor = m } label: {
                Label("История правок", systemImage: "clock.arrow.circlepath")
            }
        }
        if m.isOutgoing || m.isDeleted {
            Button(role: .destructive) { store.delete(m) } label: {
                Label(m.isDeleted ? "Убрать из сохранённых" : "Удалить у всех", systemImage: "trash")
            }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Сообщение", text: $text, axis: .vertical)
                .lineLimit(1...6)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Capsule().fill(Color(.systemBackground)))
                .overlay(Capsule().stroke(Color.gray.opacity(0.25)))
                .onChange(of: text) { t in if !t.isEmpty { store.userIsTyping(chatId) } }
            Button {
                let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty else { return }
                store.sendText(chatId, t)
                text = ""
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 34))
            }
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(.bar)
    }
}

struct MessageBubble: View {
    @EnvironmentObject var theme: ThemeStore
    let message: MessageItem
    let showSender: Bool
    let isRead: Bool

    private var out: Bool { message.isOutgoing }
    private var fg: Color { out ? theme.outText : theme.inText }

    var body: some View {
        HStack {
            if out { Spacer(minLength: 50) }
            VStack(alignment: .leading, spacing: 4) {
                if showSender && !out, let name = message.senderName {
                    Text(name).font(.caption.bold()).foregroundColor(theme.accent)
                }
                if let photo = message.photoFileId {
                    TDImage(fileId: photo)
                        .frame(width: 240, height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: max(theme.radius - 4, 4)))
                }
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.system(size: theme.fontSize))
                        .foregroundColor(fg)
                        .textSelection(.enabled)
                }
                HStack(spacing: 4) {
                    Spacer(minLength: 0)
                    if message.isDeleted {
                        Image(systemName: "trash.fill").foregroundColor(.red)
                        Text("удалено").foregroundColor(.red)
                    }
                    if message.isEdited || !message.editHistory.isEmpty { Text("изм.") }
                    Text(formatTime(message.date, short: true))
                    if out { Text(isRead ? "✓✓" : "✓") }
                }
                .font(.caption2)
                .foregroundColor(fg.opacity(0.6))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: theme.radius).fill(out ? theme.outColor : theme.inColor))
            .overlay(RoundedRectangle(cornerRadius: theme.radius)
                .stroke(message.isDeleted ? Color.red.opacity(0.7) : .clear, lineWidth: 1.5))
            .opacity(message.isDeleted ? 0.8 : 1)
            if !out { Spacer(minLength: 50) }
        }
    }
}

struct EditHistoryView: View {
    let message: MessageItem

    var body: some View {
        NavigationStack {
            List {
                Section("Сейчас") { Text(message.text) }
                Section("Раньше было") {
                    ForEach(Array(message.editHistory.enumerated().reversed()), id: \.offset) { _, old in
                        Text(old)
                    }
                }
            }
            .navigationTitle("История правок")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}
