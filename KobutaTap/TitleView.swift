import SwiftUI

struct TitleView: View {
    let onStart: () -> Void
    let onHowTo: () -> Void
    let onSettings: () -> Void

    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 20) {
                Spacer()
                LogoView(size: 46)
                SwayingCharacter(image: "piglet_normal", width: 170)
                Spacer()
                PillButton(title: String(localized: "タップしてスタート"), action: onStart)
                Button {
                    SoundPlayer.shared.play(.button)
                    onHowTo()
                } label: {
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

            VStack {
                HStack {
                    Spacer()
                    IconButton(systemName: "gearshape.fill", label: String(localized: "設定"), action: onSettings)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }
}

struct ModeSelectView: View {
    let onSelect: (GameMode) -> Void
    let onBack: () -> Void

    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 12) {
                HStack {
                    BackButton(action: onBack)
                    Spacer()
                }
                OutlinedText(text: String(localized: "モードを選ぶ"), size: 26, color: .ink)
                    .padding(.bottom, 4)
                ScrollView {
                    VStack(spacing: 10) {
                        card(.relaxed, color: Color(hex: 0x4F9A43), note: String(localized: "ゆっくり集めよう"), image: "piglet_normal")
                        card(.easy, color: Color(hex: 0x3D9BD3), note: String(localized: "はじめての人に"), image: "piglet_tapped")
                        card(.normal, color: Color(hex: 0xE0892F), note: String(localized: "おおかみに注意！"), image: "golden_normal")
                        card(.hard, color: Color(hex: 0xD9533F), note: String(localized: "速くて、おおかみが多い"), image: "wolf_normal")
                        card(.challenge, color: .kPink, note: String(localized: "どんどん速くなる"), image: "disguise_hard")
                    }
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .frame(maxWidth: 420)
        }
    }

    private func card(_ mode: GameMode, color: Color, note: String, image: String) -> some View {
        let best = UserDefaults.standard.integer(forKey: "best_\(mode.rawValue)")
        return Button {
            SoundPlayer.shared.play(.button)
            onSelect(mode)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(mode.title).font(.kRounded(22)).foregroundStyle(color)
                    Text(mode.subtitle).font(.kRounded(12, .medium)).foregroundStyle(.secondary)
                    Text(note).font(.kRounded(12, .medium)).foregroundStyle(.secondary)
                    if best > 0 {
                        Text("自己ベスト \(best)点").font(.kRounded(12, .bold)).foregroundStyle(Color.ink)
                    }
                }
                Spacer()
                Image(image).resizable().scaledToFit().frame(width: 56)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 92)
            .background(.white, in: .rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("mode_\(mode.rawValue)")
    }
}
