import CoreGraphics
import Foundation

/// ゲームモード（5 つの難易度）
enum GameMode: String, CaseIterable, Identifiable {
    /// 時間制限なし・りんごなし
    case relaxed
    /// 60秒・りんご3つ（最大5つ）。りんごが尽きたら、広告を見て1回だけ続けられる
    case easy
    case normal
    case hard
    /// エンドレス（だんだん速くなる）・りんご3つ（最大9つ）。りんごが尽きたら終わり。ランキングあり
    case challenge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .relaxed: String(localized: "のんびり")
        case .easy: String(localized: "かんたん")
        case .normal: String(localized: "ふつう")
        case .hard: String(localized: "むずかしい")
        case .challenge: String(localized: "ちゃれんじ")
        }
    }

    var subtitle: String {
        switch self {
        case .relaxed: String(localized: "時間制限なし")
        case .easy, .normal, .hard: String(localized: "60秒・りんご3つ")
        case .challenge: String(localized: "りんごがなくなるまで・ランキング")
        }
    }

    /// 60 秒で遊ぶモード（かんたん・ふつう・むずかしい）
    var isTimed: Bool { timeLimit != nil }

    var timeLimit: TimeInterval? {
        switch self {
        case .easy, .normal, .hard: Tuning.timedDuration
        case .relaxed, .challenge: nil
        }
    }

    var startingApples: Int? { self == .relaxed ? nil : Tuning.startingApples }

    var maxApples: Int { self == .challenge ? Tuning.challengeMaxApples : Tuning.maxApples }

    /// りんごが尽きたとき、広告を見て 1 回だけ続けられるか（ちゃれんじは終わり）
    var canContinue: Bool { isTimed }

    /// Game Center のランキングがあるか
    var hasLeaderboard: Bool { self == .challenge }

    /// 次に取るりんごを、広告を見て取るか。ちゃれんじで広告を外す購入をしていない人の、取れた数で 1・4・7・10…個目のりんご。
    /// 見送ったりんごは数えないので、1 個目を見送ると次のりんごがまた 1 個目になる。
    /// 広告の準備ができていないとき（在庫が無いなど）は、広告なしで取れるようにする
    func needsAdForApple(applesGained: Int, adsRemoved: Bool, adReady: Bool) -> Bool {
        self == .challenge && !adsRemoved && adReady && Tuning.isAdApple(number: applesGained + 1)
    }

    /// 速さ・出てくる間隔・おおかみの多さ。のんびりは一定なので nil
    var difficulty: Difficulty? {
        switch self {
        case .relaxed: nil
        case .easy: Tuning.easy
        case .normal: Tuning.normal
        case .hard: Tuning.hard
        case .challenge: Tuning.challenge
        }
    }
}

/// 時間帯（のんびり以外は 20 秒ごとに昼 → 夕焼け → 夜。ちゃれんじは夜のまま続く）
enum Phase: Int, Comparable {
    case day, evening, night

    static func < (lhs: Phase, rhs: Phase) -> Bool { lhs.rawValue < rhs.rawValue }

    static func forElapsed(_ elapsed: TimeInterval) -> Phase {
        if elapsed < Tuning.eveningStarts { return .day }
        if elapsed < Tuning.nightStarts { return .evening }
        return .night
    }
}

/// 難易度ごとの速さ。始めの値から、ramp 秒かけて終わりの値まで速くし、それ以降は終わりの値のまま
struct Difficulty {
    /// 画面の上から下まで落ちる秒数（始め・終わり）
    let fallStart: TimeInterval
    let fallEnd: TimeInterval
    /// 次が出てくるまでの間隔（始め・終わり）
    let spawnStart: TimeInterval
    let spawnEnd: TimeInterval
    /// 始めから終わりの値になるまでの秒数
    let ramp: TimeInterval
    /// おおかみ・着ぐるみのおおかみの出やすさ（ふつうを 1 とした倍率。こぶたで埋めて合計を 100 にする）
    let wolfFactor: Double

    func fallDuration(at elapsed: TimeInterval) -> TimeInterval {
        fallStart + (fallEnd - fallStart) * progress(elapsed)
    }

    func spawnInterval(at elapsed: TimeInterval) -> TimeInterval {
        spawnStart + (spawnEnd - spawnStart) * progress(elapsed)
    }

    private func progress(_ elapsed: TimeInterval) -> Double {
        min(max(elapsed / ramp, 0), 1)
    }
}

/// 調整用の数値はすべてここに集める（仕様書「難易度設計」の初期値。実機で遊んで決める）
enum Tuning {
    // 60秒のモード（かんたん・ふつう・むずかしい）
    static let timedDuration: TimeInterval = 60
    static let eveningStarts: TimeInterval = 20
    static let nightStarts: TimeInterval = 40
    /// 夕方になる何秒前から太陽が沈み始めるか（日中は太陽を動かさない）と、地平線まで沈んで夕日に替わるまでの秒数
    static let sunsetLead: TimeInterval = 4
    static let sunsetDuration: TimeInterval = 6
    /// 夜になる何秒前から夕日が地平線の下へ沈み始めるか（夜になるときに沈みきる）
    static let duskLead: TimeInterval = 4
    /// 夜になってから月が昇りきるまでの秒数
    static let moonriseDuration: TimeInterval = 6
    static let startingApples = 3
    static let maxApples = 5

    // ちゃれんじ
    static let challengeMaxApples = 9
    /// 広告を外す購入をしていない人は、1 回のプレイで 1・4・7・10…個目のりんごを、広告を見て取る
    static let adAppleInterval = 3

    /// 広告から戻るときのカウントダウン（3, 2, 1）
    static let countdownFrom = 3
    static let countdownStep: TimeInterval = 0.7

    // 難易度（ふつうは仕様書の初期値。かんたんは「最初の 10 秒は初めての人でもりんごを失いにくい」を目安にする）
    static let easy = Difficulty(fallStart: 4.6, fallEnd: 2.4, spawnStart: 1.05, spawnEnd: 0.55, ramp: 60, wolfFactor: 0.7)
    static let normal = Difficulty(fallStart: 4.0, fallEnd: 1.6, spawnStart: 0.9, spawnEnd: 0.35, ramp: 60, wolfFactor: 1)
    static let hard = Difficulty(fallStart: 3.2, fallEnd: 1.25, spawnStart: 0.7, spawnEnd: 0.28, ramp: 60, wolfFactor: 1.3)
    /// ちゃれんじは、ふつうと同じ速さから 3 分かけて、むずかしいより速くなる
    static let challenge = Difficulty(fallStart: 4.0, fallEnd: 1.1, spawnStart: 0.9, spawnEnd: 0.25, ramp: 180, wolfFactor: 1)

    // のんびり
    static let relaxedFallDuration: TimeInterval = 7.0
    static let relaxedSpawnInterval: TimeInterval = 1.4

    // ルール
    static let shieldDuration: TimeInterval = 5
    static let comboStep = 5
    static let comboBonus = 1
    static let disguiseBonus = 2
    static let relaxedApplePoints = 3
    static let relaxedWolfPenalty = 1

    /// 1 回のプレイで取れた数で number 個目のりんごが、広告を見て取るりんごか（1・4・7・10…個目）
    static func isAdApple(number: Int) -> Bool {
        number >= 1 && (number - 1).isMultiple(of: adAppleInterval)
    }

    // 画面
    /// 遊ぶ範囲の縦横比（iPhoneの比率に固定。iPadでは中央に置く）
    static let playAspect: CGFloat = 288.0 / 624.0
    /// 画面の下から地面（着地する高さ）までの割合
    static let groundRatio: CGFloat = 84.0 / 624.0
    /// キャラクターの幅（遊ぶ範囲の幅に対する割合）
    static let itemWidthRatio: CGFloat = 0.31
}
