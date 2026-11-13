import Foundation
import Observation

/// SpriteKitのシーンとSwiftUIで共有するゲームの状態
@MainActor
@Observable
final class GameState {
    enum Status {
        case playing
        /// 初登場のお知らせ
        case intro
        /// りんごが尽きた（60秒のモード）。広告を見て続けるか選ぶ
        case askContinue
        /// ちゃれんじで、広告を見てりんごを取るか選ぶ
        case appleOffer
        /// 広告から戻り、カウントダウンしてから再開する
        case countdown
        case finished
    }

    let mode: GameMode
    var status: Status = .playing
    var score = 0
    var apples: Int?
    var timeRemaining: TimeInterval?
    var shieldRemaining: TimeInterval = 0
    var combo = 0
    var phase: Phase = .day
    var continueUsed = false
    /// このプレイでタップしたりんごの数（ちゃれんじで、広告を見て取るりんごを決める）
    var appleTapCount = 0
    /// カウントダウンの数字（3, 2, 1）
    var countdown = 0
    /// いま表示中の初登場のお知らせ
    var introKind: ItemKind?
    /// 結果画面の内訳（タップしたこぶた・金のこぶた、ミス、見破り）
    var tappedCount: [ItemKind: Int] = [:]
    var missCount = 0
    var spottedCount = 0
    var comboCount = 0
    var appleCount = 0
    var isNewBest = false

    init(mode: GameMode) {
        self.mode = mode
        apples = mode.startingApples
        timeRemaining = mode.timeLimit
    }

    func addScore(_ points: Int) { score = max(0, score + points) }

    // MARK: 端末に保存するもの

    var bestScore: Int {
        UserDefaults.standard.integer(forKey: "best_\(mode.rawValue)")
    }

    /// 終了時に呼ぶ。自己ベストを更新したら true
    func finalizeBest() {
        if score > bestScore {
            UserDefaults.standard.set(score, forKey: "best_\(mode.rawValue)")
            isNewBest = true
        }
    }

    /// 起動時に 1 回呼ぶ。モードが 5 つになる前のチャレンジ（60秒・りんご3つ）の自己ベストを、同じ速さの「ふつう」に移す。
    /// 今のちゃれんじはエンドレスで点数の意味が違うので、そのまま引き継がない
    static func migrateBestScores(_ defaults: UserDefaults = .standard) {
        let migratedKey = "migrated_five_modes"
        guard !defaults.bool(forKey: migratedKey) else { return }
        let oldKey = "best_\(GameMode.challenge.rawValue)"
        let old = defaults.integer(forKey: oldKey)
        let normalKey = "best_\(GameMode.normal.rawValue)"
        if old > defaults.integer(forKey: normalKey) {
            defaults.set(old, forKey: normalKey)
        }
        defaults.removeObject(forKey: oldKey)
        defaults.set(true, forKey: migratedKey)
    }

    static func hasSeenIntro(_ kind: ItemKind) -> Bool {
        UserDefaults.standard.bool(forKey: "intro_\(kind.rawValue)")
    }

    static func markIntroSeen(_ kind: ItemKind) {
        UserDefaults.standard.set(true, forKey: "intro_\(kind.rawValue)")
    }
}
