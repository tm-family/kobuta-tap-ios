import SwiftUI

/// 遊び方（キャラクター／ルールの2つのタブ）
struct HowToView: View {
    let onBack: () -> Void
    @State private var tab = 0

    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 14) {
                ZStack {
                    Text("遊び方").font(.kRounded(18)).foregroundStyle(Color.ink)
                    HStack {
                        BackButton(action: onBack)
                        Spacer()
                    }
                }
                HStack(spacing: 8) {
                    tabButton(String(localized: "キャラクター"), index: 0)
                    tabButton(String(localized: "ルール"), index: 1)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if tab == 0 { characters } else { rules }
                    }
                    .padding(18)
                    .background(.white, in: .rect(cornerRadius: 24))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .frame(maxWidth: 420)
        }
    }

    private func tabButton(_ title: String, index: Int) -> some View {
        Button { tab = index } label: {
            Text(title)
                .font(.kRounded(14, .bold))
                .foregroundStyle(tab == index ? .white : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(tab == index ? Color.kGreen : .white, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: キャラクター

    /// 点数のバッジの色
    private struct Chip {
        let text: String
        let fill: Color
        let textColor: Color

        static func plus(_ text: String, golden: Bool = false) -> Chip {
            golden
                ? Chip(text: text, fill: Color(hex: 0xF9E29A), textColor: Color(hex: 0x8A5E12))
                : Chip(text: text, fill: Color(hex: 0xF9C3CF), textColor: Color(hex: 0xB8566F))
        }

        static var miss: Chip {
            Chip(text: String(localized: "ミス"), fill: Color(hex: 0xD9DEE8), textColor: Color(hex: 0x3D4A66))
        }
    }

    private var characters: some View {
        VStack(spacing: 0) {
            row("piglet_normal", L10n.name(.piglet), String(localized: "タップして集めよう"), chip: .plus("+1"))
            Divider()
            row("golden_normal", L10n.name(.golden), String(localized: "たまに出るごほうび"), chip: .plus("+10", golden: true))
            Divider()
            row("wolf_normal", L10n.name(.wolf), String(localized: "タップしちゃダメ！"), chip: .miss)
            Divider()
            row("disguise_normal", L10n.name(.disguise), String(localized: "よく見て見破ろう"), chip: .miss)
            Divider()
            row("item_brick", L10n.name(.brick), String(localized: "タップすると5秒間、おおかみを押しても平気"), chip: nil)
            Divider()
            row("item_apple", L10n.name(.apple), String(localized: "りんごが1つ増える"), chip: nil)
        }
    }

    private func row(_ image: String, _ name: String, _ desc: String, chip: Chip?) -> some View {
        HStack(spacing: 12) {
            Image(image).resizable().scaledToFit().frame(width: 52, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.kRounded(15)).foregroundStyle(Color.ink)
                Text(desc).font(.kRounded(12, .medium)).foregroundStyle(.secondary)
            }
            Spacer()
            if let chip {
                Text(chip.text)
                    .font(.kRounded(13))
                    .foregroundStyle(chip.textColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(chip.fill, in: Capsule())
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: ルール

    private var rules: some View {
        VStack(alignment: .leading, spacing: 14) {
            section(String(localized: "チャレンジ"), color: Color(hex: 0xF9C3CF), text: Color(hex: 0xB8566F), lines: [
                String(localized: "60秒でたくさん集めよう"),
                String(localized: "りんごがなくなったら終了"),
                String(localized: "こぶたを見逃す・おおかみをタップ → りんご −1")
            ])
            Divider()
            section(String(localized: "のんびり"), color: Color(hex: 0xBFE3B4), text: Color(hex: 0x3E7A33), lines: [
                String(localized: "時間制限なし"),
                String(localized: "おおかみをタップ → −1点"),
                String(localized: "りんご → +3点")
            ])
            Divider()
            section(String(localized: "ボーナス"), color: Color(hex: 0xF9E29A), text: Color(hex: 0x8A5E12), lines: [
                String(localized: "見破り ＋2：着ぐるみのおおかみを、タップせず見送る"),
                String(localized: "コンボ ＋1：こぶたを5匹続けてタップ")
            ])
        }
    }

    private func section(_ title: String, color: Color, text: Color, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.kRounded(13))
                .foregroundStyle(text)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(color, in: Capsule())
            ForEach(lines, id: \.self) { line in
                Text(line).font(.kRounded(13, .medium)).foregroundStyle(Color.ink)
            }
        }
    }
}
