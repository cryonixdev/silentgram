import SwiftUI

@main
struct SilentGramApp: App {
    @StateObject private var store = TGStore.shared
    @StateObject private var theme = ThemeStore.shared
    @StateObject private var ghost = GhostSettings.shared
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(theme)
                .environmentObject(ghost)
                .tint(theme.accent)
                .preferredColorScheme(theme.colorScheme)
        }
        .onChange(of: phase) { p in
            store.appActive = (p == .active)
            store.applyOnline()
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: TGStore

    var body: some View {
        switch store.auth {
        case .loading:
            ProgressView("Подключение…")
        case .phone:
            PhoneLoginView()
        case .code(let phone):
            CodeLoginView(phone: phone)
        case .password(let hint):
            PasswordLoginView(hint: hint)
        case .ready:
            MainTabView()
        case .unsupported(let text):
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 44))
                Text(text).multilineTextAlignment(.center)
            }.padding()
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            ChatListView()
                .tabItem { Label("Чаты", systemImage: "bubble.left.and.bubble.right.fill") }
            SettingsView()
                .tabItem { Label("Настройки", systemImage: "gearshape.fill") }
        }
    }
}
