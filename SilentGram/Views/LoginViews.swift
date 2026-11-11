import SwiftUI

private struct LoginScaffold<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content
    @EnvironmentObject var store: TGStore

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text(title).font(.title.bold())
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            content
            if let err = store.lastError {
                Text(err).font(.footnote).foregroundColor(.red)
            }
            Spacer()
            Spacer()
        }
        .padding(24)
    }
}

private struct FieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }
}

private struct MainButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).bold().frame(maxWidth: .infinity).padding(14)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 12))
    }
}

struct PhoneLoginView: View {
    @EnvironmentObject var store: TGStore
    @State private var phone = "+7"

    var body: some View {
        LoginScaffold(icon: "paperplane.circle.fill", title: "Silent Gram",
                      subtitle: "Введи номер телефона от своего аккаунта Telegram") {
            TextField("Номер телефона", text: $phone)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .modifier(FieldStyle())
            MainButton(title: "Далее") { store.submitPhone(phone) }
        }
    }
}

struct CodeLoginView: View {
    @EnvironmentObject var store: TGStore
    let phone: String
    @State private var code = ""

    var body: some View {
        LoginScaffold(icon: "message.circle.fill", title: "Код",
                      subtitle: "Код отправлен в Telegram на другом устройстве (+\(phone))") {
            TextField("Код", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .modifier(FieldStyle())
            MainButton(title: "Войти") { store.submitCode(code) }
        }
    }
}

struct PasswordLoginView: View {
    @EnvironmentObject var store: TGStore
    let hint: String
    @State private var password = ""

    var body: some View {
        LoginScaffold(icon: "lock.circle.fill", title: "Облачный пароль",
                      subtitle: hint.isEmpty ? "У аккаунта включена двухэтапная проверка" : "Подсказка: \(hint)") {
            SecureField("Пароль", text: $password).modifier(FieldStyle())
            MainButton(title: "Войти") { store.submitPassword(password) }
        }
    }
}
