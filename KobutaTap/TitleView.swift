import SwiftUI

struct TitleView: View {
    let onStart: () -> Void
    let onHowTo: () -> Void

    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 20) {
                Spacer()
                LogoView(size: 46)
                SwayingCharacter(image: "piglet_normal", width: 170)
                Spacer()
                PillButton(title: String(localized: "タップしてスタート"), action: onStart)
                Button(action: onHowTo) {
                    Text("遊び方")
                        .font(.kRounded(16, .bold))
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.75), in: Capsule())
                }
                .buttonStyle(.plain)
                Spacer().frame(height: 60)
            }
            .padding(.horizontal, 44)
            .frame(maxWidth: 420)
        }
    }
}

struct ModeSelectView: View {
    let onSelect: (GameMode) -> Void
    let onBack: () -> Void

    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 18) {
                HStack {
                    BackButton(action: onBack)
                    Spacer()
                }
                OutlinedText(text: String(localized: "モードを選ぶ"), size: 26, color: .ink)
                    .padding(.bottom, 6)
                card(.challenge, color: .kPink, note: String(localized: "おおかみに注意！"), image: "wolf_normal")
                card(.relaxed, color: Color(hex: 0x4F9A43), note: String(localized: "ゆっくり集めよう"), image: "piglet_normal")
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .frame(maxWidth: 420)
        }
    }

    private func card(_ mode: GameMode, color: Color, note: String, image: String) -> some View {
        let best = UserDefaults.standard.integer(forKey: "best_\(mode.rawValue)")
        return Button { onSelect(mode) } label: {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(mode.title).font(.kRounded(26)).foregroundStyle(color)
                    Text(mode.subtitle).font(.kRounded(13, .medium)).foregroundStyle(.secondary)
                    Text(note).font(.kRounded(13, .medium)).foregroundStyle(.secondary)
                    if best > 0 {
                        Text("自己ベスト \(best)点").font(.kRounded(13, .bold)).foregroundStyle(Color.ink)
                    }
                }
                Spacer()
                Image(image).resizable().scaledToFit().frame(width: 72)
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 140)
            .background(.white, in: .rect(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("mode_\(mode.rawValue)")
    }
}
