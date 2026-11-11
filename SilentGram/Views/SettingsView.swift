import SwiftUI
import PhotosUI

struct SettingsView: View {
    @EnvironmentObject var store: TGStore
    @EnvironmentObject var ghost: GhostSettings
    @State private var confirmLogout = false
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        AvatarView(id: 1, title: store.myName, fileId: nil, size: 60)
                        VStack(alignment: .leading) {
                            Text(store.myName).font(.title3.bold())
                            Text(store.myPhone).foregroundColor(.secondary)
                        }
                    }
                }

                Section {
                    Toggle(isOn: $ghost.enabled) {
                        Label("Режим призрака", systemImage: "eye.slash.fill")
                    }
                    Group {
                        Toggle("Скрывать «в сети»", isOn: $ghost.hideOnline)
                        Toggle("Не отправлять «прочитано»", isOn: $ghost.hideRead)
                        Toggle("Скрывать «печатает…»", isOn: $ghost.hideTyping)
                        Toggle("Уходить в офлайн после отправки", isOn: $ghost.offlineAfterSend)
                        Toggle("Читать чат, когда отвечаю", isOn: $ghost.readOnSend)
                    }
                    .disabled(!ghost.enabled)
                } header: {
                    Text("Призрак")
                } footer: {
                    Text("Прочитать чат вручную: свайп вправо по чату или долгое нажатие → «Отметить прочитанным».")
                }

                Section {
                    Toggle("Сохранять удалённые сообщения", isOn: $ghost.saveDeleted)
                    Toggle("Сохранять историю правок", isOn: $ghost.saveEdits)
                    Button("Очистить сохранённое (\(store.archive.deletedCount))", role: .destructive) {
                        confirmClear = true
                    }
                } header: {
                    Text("Как в AyuGram")
                } footer: {
                    Text("Удалённые сообщения сохраняются, только если приложение успело их увидеть.")
                }

                Section("Оформление") {
                    NavigationLink {
                        AppearanceView()
                    } label: {
                        Label("Темы, цвета и фон", systemImage: "paintbrush.fill")
                    }
                }

                Section {
                    Button("Выйти из аккаунта", role: .destructive) { confirmLogout = true }
                }
            }
            .navigationTitle("Настройки")
            .confirmationDialog("Выйти из аккаунта?", isPresented: $confirmLogout, titleVisibility: .visible) {
                Button("Выйти", role: .destructive) { store.logout() }
            }
            .confirmationDialog("Удалить все сохранённые сообщения и правки?", isPresented: $confirmClear,
                                titleVisibility: .visible) {
                Button("Очистить", role: .destructive) { store.archive.clear() }
            }
        }
    }
}

struct AppearanceView: View {
    @EnvironmentObject var theme: ThemeStore
    @State private var photo: PhotosPickerItem?

    private func colorBinding(_ kp: ReferenceWritableKeyPath<ThemeStore, String>) -> Binding<Color> {
        Binding(get: { Color(hex: theme[keyPath: kp]) }, set: { theme[keyPath: kp] = $0.hex })
    }

    var body: some View {
        Form {
            Section {
                preview.listRowInsets(EdgeInsets())
            }

            Section("Готовые темы") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(ThemeStore.presets) { p in
                            Button { theme.apply(p) } label: {
                                VStack(spacing: 6) {
                                    ZStack {
                                        LinearGradient(colors: [Color(hex: p.bg1), Color(hex: p.bg2)],
                                                       startPoint: .top, endPoint: .bottom)
                                        VStack(spacing: 4) {
                                            Capsule().fill(Color(hex: p.inc)).frame(width: 34, height: 10)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            Capsule().fill(Color(hex: p.out)).frame(width: 34, height: 10)
                                                .frame(maxWidth: .infinity, alignment: .trailing)
                                        }.padding(8)
                                    }
                                    .frame(width: 70, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10)
                                        .stroke(theme.accentHex == p.accent ? Color(hex: p.accent) : .clear, lineWidth: 2))
                                    Text(p.id).font(.caption).foregroundColor(.primary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Цвета") {
                ColorPicker("Акцент", selection: colorBinding(\.accentHex), supportsOpacity: false)
                ColorPicker("Мои сообщения", selection: colorBinding(\.outHex), supportsOpacity: false)
                ColorPicker("Входящие", selection: colorBinding(\.inHex), supportsOpacity: false)
                Picker("Тема", selection: $theme.scheme) {
                    Text("Системная").tag(0)
                    Text("Светлая").tag(1)
                    Text("Тёмная").tag(2)
                }
            }

            Section("Фон чата") {
                Picker("Тип", selection: $theme.bgMode) {
                    Text("Градиент").tag(0)
                    Text("Цвет").tag(1)
                    Text("Фото").tag(2)
                }
                .pickerStyle(.segmented)
                if theme.bgMode != 2 {
                    ColorPicker(theme.bgMode == 0 ? "Цвет 1" : "Цвет", selection: colorBinding(\.bg1Hex),
                                supportsOpacity: false)
                }
                if theme.bgMode == 0 {
                    ColorPicker("Цвет 2", selection: colorBinding(\.bg2Hex), supportsOpacity: false)
                }
                PhotosPicker(selection: $photo, matching: .images) {
                    Label("Выбрать фото из галереи", systemImage: "photo")
                }
            }

            Section("Пузыри и текст") {
                VStack(alignment: .leading) {
                    Text("Скругление: \(Int(theme.radius))")
                    Slider(value: $theme.radius, in: 2...26, step: 1)
                }
                VStack(alignment: .leading) {
                    Text("Размер текста: \(Int(theme.fontSize))")
                    Slider(value: $theme.fontSize, in: 12...24, step: 1)
                }
            }
        }
        .navigationTitle("Оформление")
        .onChange(of: photo) { item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self) {
                    await MainActor.run { theme.setBackground(data) }
                }
            }
        }
    }

    private var preview: some View {
        VStack(spacing: 6) {
            MessageBubble(message: .init(id: 1, chatId: 0, isOutgoing: false, date: Int(Date().timeIntervalSince1970),
                                         text: "Привет! Ты в сети? 👀"), showSender: false, isRead: false)
            MessageBubble(message: .init(id: 2, chatId: 0, isOutgoing: true, date: Int(Date().timeIntervalSince1970),
                                         text: "Не, я призрак 👻"), showSender: false, isRead: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(ChatBackground())
        .clipped()
    }
}
