import SwiftUI

struct ChatListView: View {
    @EnvironmentObject var store: TGStore
    @EnvironmentObject var ghost: GhostSettings
    @State private var query = ""

    private var chats: [ChatItem] {
        let all = store.sortedChats
        guard !query.isEmpty else { return all }
        return all.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List(chats) { chat in
                NavigationLink(value: chat.id) {
                    ChatRow(chat: chat, typing: store.typing[chat.id])
                }
                .swipeActions(edge: .leading) {
                    Button { store.markChatRead(chat.id) } label: {
                        Label("Прочитать", systemImage: "checkmark.message")
                    }.tint(.blue)
                }
                .contextMenu {
                    Button { store.markChatRead(chat.id) } label: {
                        Label("Отметить прочитанным", systemImage: "eye")
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, prompt: "Поиск")
            .navigationTitle(store.connection.isEmpty ? "Чаты" : store.connection)
            .navigationDestination(for: Int64.self) { ChatView(chatId: $0) }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        ghost.enabled.toggle()
                    } label: {
                        Image(systemName: ghost.enabled ? "eye.slash.fill" : "eye")
                    }
                }
            }
            .overlay {
                if store.sortedChats.isEmpty { ProgressView() }
            }
        }
    }
}

struct ChatRow: View {
    @EnvironmentObject var theme: ThemeStore
    let chat: ChatItem
    let typing: String?

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(id: chat.id, title: chat.title, fileId: chat.photoFileId)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    if chat.isChannel { Image(systemName: "megaphone.fill").font(.caption) }
                    else if chat.isGroup { Image(systemName: "person.2.fill").font(.caption) }
                    Text(chat.title).font(.headline).lineLimit(1)
                    Spacer()
                    if chat.lastOutgoing {
                        Text(chat.lastMessageId <= chat.lastReadOutbox ? "✓✓" : "✓")
                            .font(.caption).foregroundColor(theme.accent)
                    }
                    Text(formatTime(chat.lastDate)).font(.caption).foregroundColor(.secondary)
                }
                HStack(alignment: .top) {
                    if let typing {
                        Text(typing).foregroundColor(theme.accent).lineLimit(1)
                    } else {
                        Text(chat.lastText).foregroundColor(.secondary).lineLimit(2)
                    }
                    Spacer()
                    if chat.unread > 0 {
                        Text("\(chat.unread)")
                            .font(.caption.bold()).foregroundColor(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Capsule().fill(theme.accent))
                    }
                }
                .font(.subheadline)
            }
        }
        .padding(.vertical, 4)
    }
}
