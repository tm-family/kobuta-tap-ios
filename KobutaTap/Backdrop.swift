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
            let unit = geo.size.height / 624
            ZStack(alignment: .bottom) {
                LinearGradient(colors: [Color(hex: 0x7CC6F2), Color(hex: 0xDDF2FC)], startPoint: .top, endPoint: .bottom)
                Image("sky_cloud")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100 * unit)
                    .position(x: geo.size.width / 2 - 90 * unit, y: 180 * unit)
                Image("sky_cloud")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 84 * unit)
                    .position(x: geo.size.width / 2 + 90 * unit, y: 300 * unit)
                Image("ground_day")
                    .resizable()
                    .frame(width: max(640 * unit, geo.size.width), height: 204 * unit)
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
            ForEach(0..<8, id: \.self) { index in
                let angle = Double(index) / 8 * 2 * .pi
                base.foregroundStyle(.white).offset(x: cos(angle) * outline, y: sin(angle) * outline)
            }
            base.foregroundStyle(color)
        }
    }
}

/// タイトルロゴ（案01-A：先頭の文字に葉っぱの傘）。
/// デザイン資料の logo_ja.svg / logo_en.svg をそのまま使い、アセットカタログが端末の言語で切り替える。
struct LogoView: View {
    /// 文字の大きさ（pt）
    var size: CGFloat = 46

    /// SVG の高さ（viewBox）と、SVG の中の文字の大きさ。文字が size になるように縮める
    private static let svgHeight: CGFloat = 150
    private static let svgFontSize: CGFloat = 60

    var body: some View {
        Image("logo")
            .resizable()
            .scaledToFit()
            .frame(maxHeight: Self.svgHeight * size / Self.svgFontSize)
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
        Button {
            SoundPlayer.shared.play(.button)
            action()
        } label: {
            Text(title)
                .font(.kRounded(18, .bold))
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(fill, in: Capsule())
                .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
    }
}

/// 画面の左上の「‹ 戻る」ボタン（白いカプセルにうすい影）。押せる大きさは 44pt 四方より小さくしない
struct BackButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            SoundPlayer.shared.play(.button)
            action()
        } label: {
            Text("‹ 戻る")
                .font(.kRounded(15, .bold))
                .foregroundStyle(Color.ink)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(.white, in: Capsule())
                .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 白い丸に記号を描いたボタン（タイトルの右上の設定など）。押せる大きさは 44pt 四方
struct IconButton: View {
    let systemName: String
    /// 読み上げと UI テストで使う名前
    let label: String
    let action: () -> Void

    var body: some View {
        Button {
            SoundPlayer.shared.play(.button)
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.ink)
                .frame(width: 44, height: 44)
                .background(.white, in: Circle())
                .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

/// 傘の上を支点に、ゆらゆら揺れるキャラクター。
/// 撮影モード（ScreenshotDemo）では揺らさず、揺れの真ん中で止める（揺れ続けると画面が落ち着かず、撮影が止まる）
struct SwayingCharacter: View {
    let image: String
    var width: CGFloat = 170
    /// 揺れの位置。-1 が左の端、1 が右の端
    @State private var sway: Double = ScreenshotDemo.isEnabled ? 0 : -1

    var body: some View {
        Image(image)
            .resizable()
            .scaledToFit()
            .frame(width: width)
            .rotationEffect(.degrees(6 * sway), anchor: UnitPoint(x: 0.62, y: 0.18))
            .offset(x: 8 * sway)
            .onAppear {
                guard !ScreenshotDemo.isEnabled else {
                    return
                }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { sway = 1 }
            }
    }
}
