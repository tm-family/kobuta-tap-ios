import SwiftUI

/// 設定（音と振動のオン・オフ、購入の復元、広告のプライバシー設定、ライセンス）。タイトルの右上のボタンから開く
struct SettingsView: View {
    let onBack: () -> Void
    let onLicenses: () -> Void

    @AppStorage(AppSettings.soundKey) private var soundOn = true
    @AppStorage(AppSettings.hapticsKey) private var hapticsOn = true
    @State private var isRestoring = false
    @State private var restoreNotice: DressUpView.Notice?

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
                // 機種変更や再インストールのあとに、課金「広告なし＋傘のきせかえ」を取り戻す
                linkRow(icon: "arrow.clockwise", title: String(localized: "購入を復元")) {
                    guard !isRestoring else { return }
                    isRestoring = true
                    Task {
                        restoreNotice = DressUpView.notice(for: await Store.shared.restore())
                        isRestoring = false
                    }
                }
                .accessibilityIdentifier("settings_restore")
                // EEA・英国などでは、広告の同意をあとから変えられるようにする（ほかの地域では出さない）
                if Ads.shared.isPrivacyOptionsRequired {
                    linkRow(icon: "hand.raised.fill", title: String(localized: "広告のプライバシー設定")) {
                        Task { await Ads.shared.presentPrivacyOptions() }
                    }
                    .accessibilityIdentifier("settings_ad_privacy")
                }
                linkRow(icon: "doc.text.fill", title: String(localized: "ライセンス"), action: onLicenses)
                    .accessibilityIdentifier("settings_licenses")
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
        .noticeAlert($restoreNotice)
        .onChange(of: hapticsOn) {
            // オンにしたら、どんな振動かが分かるように 1 回振動させる
            if hapticsOn { Haptics.brick() }
        }
    }

    /// 押すと別の画面を開く行
    private func linkRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button {
            SoundPlayer.shared.play(.button)
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color(hex: 0x9A8F86), in: .rect(cornerRadius: 10))
                Text(title).font(.kRounded(16, .bold)).foregroundStyle(Color.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.white, in: .rect(cornerRadius: 24))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

/// ライセンス（音の素材のクレジットと、フォントのライセンス）
struct LicensesView: View {
    let onBack: () -> Void

    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 14) {
                ZStack {
                    Text("ライセンス").font(.kRounded(18)).foregroundStyle(Color.ink)
                    HStack {
                        BackButton(action: onBack)
                        Spacer()
                    }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        heading(String(localized: "BGM"))
                        ForEach(Credits.music) { entry($0) }
                        heading(String(localized: "効果音"))
                        ForEach(Credits.soundEffects) { entry($0) }
                        heading(String(localized: "フォント"))
                        Text(verbatim: "M PLUS Rounded 1c").font(.kRounded(14, .bold)).foregroundStyle(Color.ink)
                        Text(verbatim: Credits.fontLicense)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(.white, in: .rect(cornerRadius: 24))
                }
                .accessibilityIdentifier("licenses")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .frame(maxWidth: 420)
        }
    }

    private func heading(_ title: String) -> some View {
        Text(title)
            .font(.kRounded(15))
            .foregroundStyle(Color.kGreen)
            .padding(.top, 4)
    }

    private func entry(_ credit: Credit) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: credit.title).font(.kRounded(14, .bold)).foregroundStyle(Color.ink)
            Text(verbatim: credit.author).font(.kRounded(12, .medium)).foregroundStyle(.secondary)
            Text(verbatim: credit.license).font(.kRounded(12, .medium)).foregroundStyle(.secondary)
            Link(destination: credit.url) {
                Text(verbatim: credit.url.absoluteString).font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
            }
        }
    }
}
