import SwiftUI

/// 設定（音と振動のオン・オフ）。タイトルの右上のボタンから開く
struct SettingsView: View {
    let onBack: () -> Void

    @AppStorage(AppSettings.soundKey) private var soundOn = true
    @AppStorage(AppSettings.hapticsKey) private var hapticsOn = true

    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 14) {
                ZStack {
                    Text("設定").font(.kRounded(18)).foregroundStyle(Color.ink)
                    HStack {
                        BackButton(action: onBack)
                        Spacer()
                    }
                }
                VStack(spacing: 0) {
                    toggleRow(
                        icon: "speaker.wave.2.fill",
                        title: String(localized: "音"),
                        note: String(localized: "BGM と効果音"),
                        isOn: $soundOn
                    )
                    .accessibilityIdentifier("settings_sound")
                    Divider().padding(.leading, 60)
                    toggleRow(
                        icon: "iphone.radiowaves.left.and.right",
                        title: String(localized: "振動"),
                        note: String(localized: "おおかみ・りんご・レンガのとき"),
                        isOn: $hapticsOn
                    )
                    .accessibilityIdentifier("settings_haptics")
                }
                .background(.white, in: .rect(cornerRadius: 24))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .frame(maxWidth: 420)
        }
        .onChange(of: soundOn) {
            // オフにしたら BGM を止め、オンに戻したらタイトルの BGM を流す
            SoundPlayer.shared.resume()
            SoundPlayer.shared.play(.button)
        }
        .onChange(of: hapticsOn) {
            // オンにしたら、どんな振動かが分かるように 1 回振動させる
            if hapticsOn { Haptics.brick() }
        }
    }

    private func toggleRow(icon: String, title: String, note: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.kGreen, in: .rect(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.kRounded(16, .bold)).foregroundStyle(Color.ink)
                    Text(note).font(.kRounded(12, .medium)).foregroundStyle(.secondary)
                }
            }
        }
        .tint(.kGreen)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
