import SwiftUI

struct TDImage: View {
    let fileId: Int
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.gray.opacity(0.15)
            }
        }
        .task(id: fileId) { image = await ImageCache.load(fileId) }
    }
}

struct AvatarView: View {
    let id: Int64
    let title: String
    let fileId: Int?
    var size: CGFloat = 54

    private static let palettes: [[Color]] = [
        [.red, .orange], [.orange, .yellow], [.purple, .pink], [.green, .mint],
        [.cyan, .blue], [.blue, .indigo], [.pink, .red],
    ]

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: Self.palettes[Int(abs(id % 7))],
                                         startPoint: .top, endPoint: .bottom))
            Text(initials).font(.system(size: size * 0.38, weight: .semibold)).foregroundColor(.white)
            if let fileId { TDImage(fileId: fileId).clipShape(Circle()) }
        }
        .frame(width: size, height: size)
    }

    private var initials: String {
        title.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
    }
}

struct ChatBackground: View {
    @EnvironmentObject var theme: ThemeStore

    var body: some View {
        GeometryReader { geo in
            Group {
                switch theme.bgMode {
                case 1:
                    Color(hex: theme.bg1Hex)
                case 2:
                    if let img = theme.bgImage {
                        Image(uiImage: img).resizable().scaledToFill()
                    } else { gradient }
                default:
                    gradient
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .ignoresSafeArea()
    }

    private var gradient: some View {
        LinearGradient(colors: [Color(hex: theme.bg1Hex), Color(hex: theme.bg2Hex)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
