import Foundation
import Observation

/// SpriteKitのシーンとSwiftUIで共有するゲームの状態
@MainActor
@Observable
final class GameState {
    enum Status { case playing, intro, askContinue, finished }

    let mode: GameMode
    var status: Status = .playing
    var score = 0
    var apples: Int?
    var timeRemaining: TimeInterval?
    var shieldRemaining: TimeInterval = 0
    var combo = 0
    var phase: Phase = .day
    var continueUsed = false
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

    static func hasSeenIntro(_ kind: ItemKind) -> Bool {
        UserDefaults.standard.bool(forKey: "intro_\(kind.rawValue)")
    }

    static func markIntroSeen(_ kind: ItemKind) {
        UserDefaults.standard.set(true, forKey: "intro_\(kind.rawValue)")
    }
}
