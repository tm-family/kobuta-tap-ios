import SwiftUI

/// 画面の切り替え（タイトル → モード選択 → プレイ → 結果。タイトルから遊び方へ）
struct ContentView: View {
    enum Screen: Equatable { case title, modeSelect, howTo, game(GameMode) }

    @State private var screen: Screen = .title
    @State private var round = 0

    var body: some View {
        ZStack {
            switch screen {
            case .title:
                TitleView(onStart: { screen = .modeSelect }, onHowTo: { screen = .howTo })
            case .modeSelect:
                ModeSelectView(onSelect: { screen = .game($0) }, onBack: { screen = .title })
            case .howTo:
                HowToView(onBack: { screen = .title })
            case .game(let mode):
                GameView(mode: mode,
                         onRestart: { round += 1 },
                         onExit: { screen = .modeSelect })
                    .id(round)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: screen)
        .onAppear { updateBGM() }
        .onChange(of: screen) { updateBGM() }
    }

    /// メニューの画面ではタイトルの BGM を流す（プレイ中と結果の BGM は GameView が切り替える）
    private func updateBGM() {
        if case .game = screen { return }
        SoundPlayer.shared.playBGM(.title)
    }
}
