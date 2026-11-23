//
//  ScreenshotDemo.swift
//  KobutaTap
//
//  App Store 用スクリーンショットの撮影モード。
//  Tools/capture_screenshots.sh が次の起動引数でアプリを起動し、目的の画面をデモデータで開かせる。
//
//    -screenshot-demo -screenshot-scene <Scene の rawValue> -AppleLanguages (<言語>) -AppleLocale <ロケール>
//
//  画面を足すときは、Scene に case を足し、KobutaTap.swift の rootView で開く画面を返し、
//  AppStore/screenshots.json の scenes に同じ rawValue を足す（突き合わせは Tools/app_store_config.py が行う）。
//  デモデータは実データと混ざらないよう、撮影モードのときだけメモリ上やインメモリのストアに用意する。
//

import UIKit

enum ScreenshotDemo {
    /// 撮る画面。rawValue が AppStore/screenshots.json の scene と対応する
    enum Scene: String {
        case home
        case playDay = "play_day"
        case playNight = "play_night"
        case modes
        case relaxed
        case dressUp = "dress_up"
        case result
        case howTo = "how_to"
    }

    /// 撮影モードで起動しているか
    static let isEnabled = ProcessInfo.processInfo.arguments.contains("-screenshot-demo")

    /// 撮影モードで開く画面。撮影モードでないときと、知らない値を渡されたときは nil
    static let scene: Scene? = {
        guard isEnabled else {
            return nil
        }
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-screenshot-scene"), arguments.indices.contains(index + 1) else {
            return nil
        }
        return Scene(rawValue: arguments[index + 1])
    }()

    /// ゲームの画面を撮るときの盤面。撮影モードでないときと、ゲームの画面でないときは nil
    static var board: Board? {
        switch scene {
        case .playDay: .day
        case .playNight: .night
        case .relaxed: .relaxed
        case .result: .result
        default: nil
        }
    }
}

// MARK: - ゲームの盤面

extension ScreenshotDemo {
    /// プレイの途中で止めた盤面。並べたものは動かさず、点数やりんごもこの値のまま出す
    struct Board {
        let mode: GameMode
        let scenery: Scenery
        /// プレイを始めてからの秒数（太陽と月の位置と、60 秒のモードの残り時間に使う）
        let elapsed: TimeInterval
        let score: Int
        /// りんごの数。nil ならモードの初めの数（のんびりは無し）
        var apples: Int?
        var skin: UmbrellaSkin = .leaf
        let items: [Item]
        var popups: [Popup] = []
        /// 結果の画面を重ねるときの内訳
        var result: Result?

        /// 盤面に合わせた状態（端末の自己ベストには書き込まない）
        @MainActor
        func makeState() -> GameState {
            let state = GameState(mode: mode)
            state.score = score
            if let apples { state.apples = apples }
            if let limit = mode.timeLimit { state.timeRemaining = max(0, limit - elapsed) }
            if let result {
                state.status = .finished
                state.tappedCount = [.piglet: result.piglets, .golden: result.golden]
                state.spottedCount = result.spotted
                state.comboCount = result.combos
                state.missCount = result.misses
                state.isNewBest = true
            }
            return state
        }
    }

    /// 並べるもの。x は遊ぶ範囲の幅、y は画面の高さに対する割合（こぶたとおおかみは傘のてっぺん、ほかは中心）
    struct Item {
        let kind: ItemKind
        let x: CGFloat
        let y: CGFloat
        var angle: CGFloat = 0
        /// タップしたあとの絵にする
        var tapped = false
    }

    /// 浮かせる文字。位置は Item と同じ割合
    struct Popup {
        let text: String
        let x: CGFloat
        let y: CGFloat
        var size: CGFloat = 22
        var color: UIColor = GameScene.popupInk
    }

    /// 結果の画面の内訳
    struct Result {
        let piglets: Int
        let golden: Int
        let spotted: Int
        let combos: Int
        let misses: Int
    }
}

private extension ScreenshotDemo.Board {
    /// 昼の「ふつう」。こぶたをタップしたところ
    static var day: Self {
        Self(
            mode: .normal,
            scenery: .challenge(.day),
            elapsed: 14,
            score: 23,
            items: [
                .init(kind: .piglet, x: 0.26, y: 0.80, angle: 0.1),
                .init(kind: .golden, x: 0.74, y: 0.68, angle: -0.1),
                .init(kind: .wolf, x: 0.3, y: 0.5, angle: -0.06),
                .init(kind: .piglet, x: 0.72, y: 0.36, tapped: true),
                .init(kind: .apple, x: 0.2, y: 0.26)
            ],
            popups: [
                .init(text: L10n.points(1), x: 0.72, y: 0.365, color: .systemPink),
                .init(text: L10n.oink, x: 0.72, y: 0.39, size: 16)
            ]
        )
    }

    /// 夜の「むずかしい」。着ぐるみのおおかみが混じる
    static var night: Self {
        Self(
            mode: .hard,
            scenery: .challenge(.night),
            elapsed: 46,
            score: 41,
            apples: 2,
            items: [
                .init(kind: .disguise, x: 0.25, y: 0.8, angle: 0.08),
                .init(kind: .piglet, x: 0.72, y: 0.74, angle: -0.1),
                .init(kind: .disguise, x: 0.7, y: 0.46, angle: 0.1),
                .init(kind: .wolf, x: 0.28, y: 0.44, angle: -0.08)
            ],
            popups: [
                .init(text: "\(L10n.spotted) \(L10n.points(Tuning.disguiseBonus))", x: 0.5, y: 0.22, color: .systemGreen)
            ]
        )
    }

    /// 春の「のんびり」。桜の傘
    static var relaxed: Self {
        Self(
            mode: .relaxed,
            scenery: Scenery(phase: .day, season: .spring),
            elapsed: 0,
            score: 37,
            skin: .sakura,
            items: [
                .init(kind: .piglet, x: 0.28, y: 0.8, angle: 0.18),
                .init(kind: .piglet, x: 0.72, y: 0.66, angle: -0.16),
                .init(kind: .golden, x: 0.3, y: 0.46, angle: -0.12),
                .init(kind: .piglet, x: 0.7, y: 0.34, angle: 0.15)
            ]
        )
    }

    /// ちゃれんじの結果（自己ベスト更新）。点数は内訳の合計にそろえる
    static var result: Self {
        let result = ScreenshotDemo.Result(piglets: 128, golden: 3, spotted: 9, combos: 10, misses: 9)
        let score = result.piglets + result.golden * 10 + result.spotted * Tuning.disguiseBonus
            + result.combos * Tuning.comboBonus
        return Self(
            mode: .challenge,
            scenery: .challenge(.night),
            elapsed: 140,
            score: score,
            apples: 0,
            // 結果のカードの後ろは暗くなり、並べても端がのぞくだけなので何も置かない
            items: [],
            result: result
        )
    }
}
