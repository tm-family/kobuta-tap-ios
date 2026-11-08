import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
    static let ink = Color(hex: 0x3D2B33)
    static let kPink = Color(hex: 0xD9577A)
    static let kGreen = Color(hex: 0x5FAE52)
    static let kBrick = Color(hex: 0xD7724A)
}

extension Font {
    /// アプリの文字（M PLUS Rounded 1c）。heavy/black → ExtraBold、bold/semibold → Bold、それ以外 → Medium
    static func kRounded(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
        .custom(AppFont.name(for: weight), fixedSize: size)
    }
}

/// メニュー画面の背景（昼の空と草原）
struct Backdrop: View {
    var body: some View {
        GeometryReader { geo in
            let u = geo.size.height / 624
            ZStack(alignment: .bottom) {
                LinearGradient(colors: [Color(hex: 0x7CC6F2), Color(hex: 0xDDF2FC)], startPoint: .top, endPoint: .bottom)
                Image("sky_cloud").resizable().scaledToFit().frame(width: 100 * u)
                    .position(x: geo.size.width / 2 - 90 * u, y: 180 * u)
                Image("sky_cloud").resizable().scaledToFit().frame(width: 84 * u)
                    .position(x: geo.size.width / 2 + 90 * u, y: 300 * u)
                Image("ground_day").resizable()
                    .frame(width: max(640 * u, geo.size.width), height: 204 * u)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
    }
}

/// 白いフチつきの文字
struct OutlinedText: View {
    let text: String
    let size: CGFloat
    let color: Color
    var outline: CGFloat = 5

    var body: some View {
        let base = Text(text).font(.kRounded(size))
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                let a = Double(i) / 8 * 2 * .pi
                base.foregroundStyle(.white).offset(x: cos(a) * outline, y: sin(a) * outline)
            }
            base.foregroundStyle(color)
        }
    }
}

/// タイトルロゴ（案01-A：先頭の文字に葉っぱの傘）
struct LogoView: View {
    var size: CGFloat = 46

    var body: some View {
        HStack(spacing: 0) {
            OutlinedText(text: String(localized: "logo_part1", defaultValue: "こぶた"), size: size, color: Color(hex: 0xF28CA8))
                .overlay(alignment: .topLeading) {
                    Image("umbrella_leaf").resizable().scaledToFit()
                        .frame(width: size * 0.95)
                        .rotationEffect(.degrees(-20))
                        .offset(x: -size * 0.2, y: -size * 0.85)
                        .shadow(color: .white, radius: 0, x: 2, y: 2)
                }
            OutlinedText(text: String(localized: "logo_part2", defaultValue: "タップ"), size: size, color: Color.kGreen)
        }
        .padding(.top, size * 0.8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("こぶたタップ"))
    }
}

/// 白い丸いボタン
struct PillButton: View {
    let title: String
    var fill: Color = .white
    var textColor: Color = .ink
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.kRounded(18, .bold)).foregroundStyle(textColor)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(fill, in: Capsule())
                .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
    }
}

/// 傘の上を支点に、ゆらゆら揺れるキャラクター
struct SwayingCharacter: View {
    let image: String
    var width: CGFloat = 170
    @State private var swing = false

    var body: some View {
        Image(image).resizable().scaledToFit().frame(width: width)
            .rotationEffect(.degrees(swing ? 6 : -6), anchor: UnitPoint(x: 0.62, y: 0.18))
            .offset(x: swing ? 8 : -8)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { swing = true }
            }
    }
}
