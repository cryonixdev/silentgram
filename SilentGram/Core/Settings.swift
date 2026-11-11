import SwiftUI
import UIKit

// MARK: - Режим призрака и функции «как в AyuGram»

final class GhostSettings: ObservableObject {
    static let shared = GhostSettings()
    private let d = UserDefaults.standard
    var onChange: (() -> Void)?

    @Published var enabled: Bool { didSet { save("g.enabled", enabled) } }
    @Published var hideOnline: Bool { didSet { save("g.online", hideOnline) } }
    @Published var hideRead: Bool { didSet { save("g.read", hideRead) } }
    @Published var hideTyping: Bool { didSet { save("g.typing", hideTyping) } }
    @Published var offlineAfterSend: Bool { didSet { save("g.offSend", offlineAfterSend) } }
    @Published var readOnSend: Bool { didSet { save("g.readSend", readOnSend) } }
    @Published var saveDeleted: Bool { didSet { save("a.deleted", saveDeleted) } }
    @Published var saveEdits: Bool { didSet { save("a.edits", saveEdits) } }

    private init() {
        func b(_ k: String, _ def: Bool) -> Bool { UserDefaults.standard.object(forKey: k) as? Bool ?? def }
        enabled = b("g.enabled", true)
        hideOnline = b("g.online", true)
        hideRead = b("g.read", true)
        hideTyping = b("g.typing", true)
        offlineAfterSend = b("g.offSend", true)
        readOnSend = b("g.readSend", true)
        saveDeleted = b("a.deleted", true)
        saveEdits = b("a.edits", true)
    }

    private func save(_ k: String, _ v: Bool) {
        d.set(v, forKey: k)
        DispatchQueue.main.async { self.onChange?() }
    }

    var noOnline: Bool { enabled && hideOnline }
    var noRead: Bool { enabled && hideRead }
    var noTyping: Bool { enabled && hideTyping }
}

// MARK: - Оформление

struct ThemePreset: Identifiable {
    let id: String
    let accent, out, inc, bg1, bg2: String
    let scheme: Int
}

final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()
    private let d = UserDefaults.standard

    @Published var accentHex: String { didSet { d.set(accentHex, forKey: "t.accent") } }
    @Published var outHex: String { didSet { d.set(outHex, forKey: "t.out") } }
    @Published var inHex: String { didSet { d.set(inHex, forKey: "t.in") } }
    @Published var bg1Hex: String { didSet { d.set(bg1Hex, forKey: "t.bg1") } }
    @Published var bg2Hex: String { didSet { d.set(bg2Hex, forKey: "t.bg2") } }
    /// 0 — градиент, 1 — цвет, 2 — своё фото
    @Published var bgMode: Int { didSet { d.set(bgMode, forKey: "t.bgMode") } }
    @Published var radius: Double { didSet { d.set(radius, forKey: "t.radius") } }
    @Published var fontSize: Double { didSet { d.set(fontSize, forKey: "t.font") } }
    /// 0 — как в системе, 1 — светлая, 2 — тёмная
    @Published var scheme: Int { didSet { d.set(scheme, forKey: "t.scheme") } }
    @Published var bgImage: UIImage?

    static let presets: [ThemePreset] = [
        .init(id: "Telegram", accent: "#2AABEE", out: "#EFFDDE", inc: "#FFFFFF", bg1: "#A8C990", bg2: "#D9DFA7", scheme: 0),
        .init(id: "Ночь", accent: "#5EB5F7", out: "#2B5278", inc: "#182533", bg1: "#0E1621", bg2: "#17212B", scheme: 2),
        .init(id: "AMOLED", accent: "#8E8EFF", out: "#3A3A8C", inc: "#1C1C1E", bg1: "#000000", bg2: "#000000", scheme: 2),
        .init(id: "Мята", accent: "#21B88A", out: "#C8F5E2", inc: "#FFFFFF", bg1: "#7FD8BE", bg2: "#E0F7EF", scheme: 1),
        .init(id: "Сакура", accent: "#E85D9A", out: "#FFD6E8", inc: "#FFFFFF", bg1: "#F6A6C8", bg2: "#FDE6F0", scheme: 1),
        .init(id: "Закат", accent: "#FF7A45", out: "#FFE1CC", inc: "#FFFFFF", bg1: "#FF9A8B", bg2: "#FAD0C4", scheme: 1),
    ]

    private static var imageURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("bg.jpg")
    }

    private init() {
        let d = UserDefaults.standard
        let p = Self.presets[0]
        accentHex = d.string(forKey: "t.accent") ?? p.accent
        outHex = d.string(forKey: "t.out") ?? p.out
        inHex = d.string(forKey: "t.in") ?? p.inc
        bg1Hex = d.string(forKey: "t.bg1") ?? p.bg1
        bg2Hex = d.string(forKey: "t.bg2") ?? p.bg2
        bgMode = d.object(forKey: "t.bgMode") as? Int ?? 0
        radius = d.object(forKey: "t.radius") as? Double ?? 16
        fontSize = d.object(forKey: "t.font") as? Double ?? 16
        scheme = d.object(forKey: "t.scheme") as? Int ?? 0
        bgImage = UIImage(contentsOfFile: Self.imageURL.path)
    }

    func apply(_ p: ThemePreset) {
        accentHex = p.accent; outHex = p.out; inHex = p.inc
        bg1Hex = p.bg1; bg2Hex = p.bg2; scheme = p.scheme
        if bgMode == 2 { bgMode = 0 }
    }

    func setBackground(_ data: Data) {
        guard let img = UIImage(data: data), let jpg = img.jpegData(compressionQuality: 0.85) else { return }
        try? jpg.write(to: Self.imageURL)
        bgImage = img
        bgMode = 2
    }

    var accent: Color { Color(hex: accentHex) }
    var outColor: Color { Color(hex: outHex) }
    var inColor: Color { Color(hex: inHex) }
    var outText: Color { isLight(outHex) ? .black : .white }
    var inText: Color { isLight(inHex) ? .black : .white }
    var colorScheme: ColorScheme? { scheme == 1 ? .light : scheme == 2 ? .dark : nil }
}

extension Color {
    init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }

    var hex: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        func c(_ x: CGFloat) -> Int { max(0, min(255, Int(x * 255))) }
        return String(format: "#%02X%02X%02X", c(r), c(g), c(b))
    }
}

func isLight(_ hex: String) -> Bool {
    var v: UInt64 = 0
    Scanner(string: hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)).scanHexInt64(&v)
    let r = Double((v >> 16) & 0xFF), g = Double((v >> 8) & 0xFF), b = Double(v & 0xFF)
    return (0.299 * r + 0.587 * g + 0.114 * b) > 150
}
