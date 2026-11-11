import Foundation
import TDLibFramework

typealias JSON = [String: Any]

struct TDError: LocalizedError {
    let code: Int
    let message: String
    var errorDescription: String? { message }
}

/// Тонкая обёртка над JSON-интерфейсом TDLib (td_send / td_receive).
final class TDClient {
    static let shared = TDClient()

    private var clientId: Int32
    private var pending: [String: (JSON) -> Void] = [:]
    private let lock = NSLock()
    private var counter = 0

    /// Вызывается на фоновом потоке для каждого апдейта.
    var onUpdate: ((JSON) -> Void)?

    private init() {
        _ = td_execute(#"{"@type":"setLogVerbosityLevel","new_verbosity_level":1}"#)
        clientId = td_create_client_id()
        let thread = Thread { [weak self] in self?.receiveLoop() }
        thread.name = "tdlib-receive"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    /// Новый клиент (нужен после выхода из аккаунта).
    func recreate() {
        lock.lock(); clientId = td_create_client_id(); lock.unlock()
        send(["@type": "getOption", "name": "version"])
    }

    private func receiveLoop() {
        while true {
            guard let raw = td_receive(10) else { continue }
            let data = Data(String(cString: raw).utf8)
            guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? JSON else { continue }
            if let extra = obj["@extra"] as? String {
                lock.lock(); let cb = pending.removeValue(forKey: extra); lock.unlock()
                cb?(obj)
            } else {
                onUpdate?(obj)
            }
        }
    }

    func send(_ request: JSON, completion: ((JSON) -> Void)? = nil) {
        var req = request
        lock.lock()
        let id = clientId
        if let completion {
            counter += 1
            let extra = "r\(counter)"
            pending[extra] = completion
            req["@extra"] = extra
        }
        lock.unlock()
        guard let data = try? JSONSerialization.data(withJSONObject: req),
              let str = String(data: data, encoding: .utf8) else { return }
        td_send(id, str)
    }

    @discardableResult
    func call(_ request: JSON) async throws -> JSON {
        try await withCheckedThrowingContinuation { cont in
            send(request) { resp in
                if resp["@type"] as? String == "error" {
                    cont.resume(throwing: TDError(code: (resp["code"] as? NSNumber)?.intValue ?? 0,
                                                  message: resp["message"] as? String ?? "Ошибка"))
                } else {
                    cont.resume(returning: resp)
                }
            }
        }
    }
}

extension Dictionary where Key == String, Value == Any {
    var type: String { self["@type"] as? String ?? "" }
    func str(_ k: String) -> String? { self[k] as? String }
    func obj(_ k: String) -> JSON? { self[k] as? JSON }
    func arr(_ k: String) -> [JSON] { self[k] as? [JSON] ?? [] }
    func bool(_ k: String) -> Bool { self[k] as? Bool ?? false }
    func int(_ k: String) -> Int? {
        if let n = self[k] as? NSNumber { return n.intValue }
        if let s = self[k] as? String { return Int(s) }
        return nil
    }
    func int64(_ k: String) -> Int64? {
        if let n = self[k] as? NSNumber { return n.int64Value }
        if let s = self[k] as? String { return Int64(s) }
        return nil
    }
    func int64s(_ k: String) -> [Int64] {
        (self[k] as? [Any] ?? []).compactMap {
            if let n = $0 as? NSNumber { return n.int64Value }
            if let s = $0 as? String { return Int64(s) }
            return nil
        }
    }
}
