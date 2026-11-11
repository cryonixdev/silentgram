import Foundation

/// Локальное хранилище: кэш недавних сообщений, удалённые сообщения и история правок.
/// Используется только на главном потоке.
final class MessageArchive {
    static let shared = MessageArchive()

    private struct Snapshot: Codable {
        var cache: [String: MessageItem] = [:]
        var deleted: [String: MessageItem] = [:]
        var edits: [String: [String]] = [:]
    }

    private var s = Snapshot()
    private var saveWork: DispatchWorkItem?
    private let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("archive.json")

    private init() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: url), let snap = try? JSONDecoder().decode(Snapshot.self, from: data) {
            s = snap
        }
    }

    func remember(_ m: MessageItem) {
        s.cache[m.key] = m
        if s.cache.count > 6000 {
            let oldest = s.cache.values.sorted { $0.date < $1.date }.prefix(1500)
            oldest.forEach { s.cache.removeValue(forKey: $0.key) }
        }
        scheduleSave()
    }

    func cached(_ key: String) -> MessageItem? { s.cache[key] }

    func addDeleted(_ m: MessageItem) {
        var item = m
        item.isDeleted = true
        s.deleted[m.key] = item
        scheduleSave()
    }

    func deleted(in chatId: Int64) -> [MessageItem] {
        s.deleted.values.filter { $0.chatId == chatId }
    }

    func addEdit(_ key: String, old: String) {
        s.edits[key, default: []].append(old)
        scheduleSave()
    }

    func edits(_ key: String) -> [String] { s.edits[key] ?? [] }

    func clear() {
        s = Snapshot()
        scheduleSave()
    }

    var deletedCount: Int { s.deleted.count }

    private func scheduleSave() {
        saveWork?.cancel()
        let snap = s
        let url = url
        let work = DispatchWorkItem {
            DispatchQueue.global(qos: .utility).async {
                if let data = try? JSONEncoder().encode(snap) { try? data.write(to: url, options: .atomic) }
            }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }
}
