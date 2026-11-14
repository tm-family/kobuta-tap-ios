import SwiftUI

/// 画面の切り替え（タイトル → モード選択 → プレイ → 結果。タイトルから遊び方・設定へ）
struct ContentView: View {
    enum Screen: Equatable { case title, modeSelect, howTo, settings, licenses, game(GameMode) }

    @State private var screen: Screen = .title
    @State private var round = 0
    @Bindable private var gameCenter = GameCenter.shared

    var body: some View {
        ZStack {
            switch screen {
            case .title:
                TitleView(onStart: { screen = .modeSelect },
                          onHowTo: { screen = .howTo },
                          onSettings: { screen = .settings })
            case .modeSelect:
                ModeSelectView(onSelect: { screen = .game($0) }, onBack: { screen = .title })
            case .howTo:
                HowToView(onBack: { screen = .title })
            case .settings:
                SettingsView(onBack: { screen = .title }, onLicenses: { screen = .licenses })
            case .licenses:
                LicensesView(onBack: { screen = .settings })
            case .game(let mode):
                GameView(mode: mode,
                         onRestart: { round += 1 },
                         onExit: { screen = .modeSelect })
                    .id(round)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: screen)
        .onAppear {
            updateBGM()
            GameCenter.shared.signInIfOpenedBefore()
        }
        .alert(
            gameCenter.signInHelp?.title ?? "",
            isPresented: Binding(get: { gameCenter.signInHelp != nil }, set: { if !$0 { gameCenter.signInHelp = nil } }),
            presenting: gameCenter.signInHelp
        ) { _ in
            Button("OK") {}
        } message: { help in
            Text(help.message)
        }
        .onChange(of: screen) { updateBGM() }
        // 広告の同意（EEA・英国など）→ トラッキングの許可 → 広告の読み込み
        .task { await Ads.shared.setUp() }
    }

    /// メニューの画面ではタイトルの BGM を流す（プレイ中と結果の BGM は GameView が切り替える）
    private func updateBGM() {
        if case .game = screen { return }
        SoundPlayer.shared.playBGM(.title)
    }
}
