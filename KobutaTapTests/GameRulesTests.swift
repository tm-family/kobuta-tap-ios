//
//  GameRulesTests.swift
//  KobutaTapTests
//
//  仕様書の「ゲームルール」「難易度設計」「背景」の決まりが、コードの値と合っているかを確かめる。
//

import Foundation
@testable import KobutaTap
import Testing

struct PhaseTests {
    /// のんびり以外は 20 秒ごとに昼 → 夕焼け → 夜へ切り替わり、ちゃれんじは夜のまま続く
    @Test(arguments: [
        (0.0, Phase.day), (19.9, .day),
        (20.0, .evening), (39.9, .evening),
        (40.0, .night), (60.0, .night), (600.0, .night)
    ])
    func phaseForElapsed(elapsed: TimeInterval, expected: Phase) {
        #expect(Phase.forElapsed(elapsed) == expected)
    }

    /// のんびりの空は端末の時刻で決まる（5〜16 時は昼、16〜19 時は夕焼け、19〜5 時は夜）
    @Test(arguments: [
        (4, 59, Phase.night), (5, 0, .day), (15, 59, .day),
        (16, 0, .evening), (18, 59, .evening), (19, 0, .night), (0, 0, .night)
    ])
    func phaseForClock(hour: Int, minute: Int, expected: Phase) throws {
        let date = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 1, hour: hour, minute: minute)))
        #expect(Phase.forClock(date) == expected)
    }

    @Test
    func phasesAreOrdered() {
        #expect(Phase.day < .evening)
        #expect(Phase.evening < .night)
    }
}

struct SeasonTests {
    /// 3〜5 月は春、6〜8 月は夏、9〜11 月は秋、12〜2 月は冬
    @Test(arguments: [
        (1, Season.winter), (2, .winter), (3, .spring), (5, .spring), (6, .summer), (8, .summer),
        (9, .autumn), (11, .autumn), (12, .winter)
    ])
    func seasonForMonth(month: Int, expected: Season) throws {
        let date = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: month, day: 15, hour: 12)))
        #expect(Season.current(date) == expected)
    }
}

struct ItemKindTests {
    /// 出現の重みは、どの時間帯・モードでも合計 100（仕様書 3.2 の表を割合として読める）
    @Test(arguments: GameMode.allCases)
    func weightsSumToHundred(mode: GameMode) {
        for phase in [Phase.day, .evening, .night] {
            let total = ItemKind.allCases.reduce(0) { $0 + $1.weight(mode: mode, phase: phase) }
            #expect(total == 100, "\(mode) \(phase)")
        }
    }

    /// ふつうの出現の重みは、仕様書 3.2 の表（昼・夕焼け・夜）のまま
    @Test
    func normalWeightsMatchSpec() {
        let expected: [ItemKind: [Int]] = [
            .piglet: [71, 63, 54], .golden: [5, 5, 5], .wolf: [18, 18, 16],
            .disguise: [0, 8, 18], .brick: [3, 3, 4], .apple: [3, 3, 3]
        ]
        for (kind, weights) in expected {
            #expect([Phase.day, .evening, .night].map { kind.weight(mode: .normal, phase: $0) } == weights, "\(kind)")
        }
    }

    /// むずかしいほど、おおかみと着ぐるみのおおかみが多い
    @Test(arguments: [Phase.day, .evening, .night])
    func harderModesHaveMoreWolves(phase: Phase) {
        func wolves(_ mode: GameMode) -> Int {
            ItemKind.wolf.weight(mode: mode, phase: phase) + ItemKind.disguise.weight(mode: mode, phase: phase)
        }
        #expect(wolves(.easy) < wolves(.normal))
        #expect(wolves(.normal) < wolves(.hard))
    }

    /// のんびりは時間帯で出現率を変えない
    @Test
    func relaxedWeightsDoNotDependOnPhase() {
        for kind in ItemKind.allCases {
            let weights = [Phase.day, .evening, .night].map { kind.weight(mode: .relaxed, phase: $0) }
            #expect(Set(weights).count == 1, "\(kind)")
        }
    }

    /// 着ぐるみのおおかみは、のんびり以外の昼には出ない（夕焼けで初登場）
    @Test(arguments: [GameMode.easy, .normal, .hard, .challenge])
    func disguiseNeverAppearsInDay(mode: GameMode) {
        #expect(ItemKind.disguise.weight(mode: mode, phase: .day) == 0)
        for _ in 0..<200 {
            #expect(ItemKind.random(mode: mode, phase: .day) != .disguise)
        }
    }

    /// 夜の着ぐるみのおおかみだけ、見分けポイントを減らした絵（disguise_hard）にする
    @Test
    func textureNames() {
        #expect(ItemKind.piglet.textureName(.tapped) == "piglet_tapped")
        #expect(ItemKind.disguise.textureName(.normal, hard: true) == "disguise_hard")
        #expect(ItemKind.disguise.textureName(.sit, hard: true) == "disguise_sit")
        #expect(ItemKind.brick.textureName(.tapped) == "item_brick")
        #expect(ItemKind.apple.textureName(.normal) == "item_apple")
    }

    /// 初登場のお知らせは、金のこぶた・着ぐるみのおおかみ・レンガ・りんごだけ
    @Test
    func introTargets() {
        let targets = ItemKind.allCases.filter(\.hasIntro)
        #expect(Set(targets) == [.golden, .disguise, .brick, .apple])
    }
}

struct GameStateTests {
    /// かんたん・ふつう・むずかしいは 60 秒・りんご 3 つ、ちゃれんじは時間制限なし・りんご 3 つ、のんびりは時間もりんごもなし
    @Test
    func initialValuesByMode() {
        for mode in [GameMode.easy, .normal, .hard] {
            let state = GameState(mode: mode)
            #expect(state.timeRemaining == 60)
            #expect(state.apples == 3)
        }

        let challenge = GameState(mode: .challenge)
        #expect(challenge.timeRemaining == nil)
        #expect(challenge.apples == 3)

        let relaxed = GameState(mode: .relaxed)
        #expect(relaxed.timeRemaining == nil)
        #expect(relaxed.apples == nil)
    }

    /// りんごは 60 秒のモードで最大 5 つ、ちゃれんじで最大 9 つ。広告で続けられるのは 60 秒のモードだけ。ランキングはちゃれんじだけ
    @Test
    func rulesByMode() {
        #expect([GameMode.easy, .normal, .hard].allSatisfy { $0.maxApples == 5 && $0.canContinue && !$0.hasLeaderboard })
        #expect(GameMode.challenge.maxApples == 9)
        #expect(!GameMode.challenge.canContinue)
        #expect(GameMode.challenge.hasLeaderboard)
        #expect(!GameMode.relaxed.canContinue)
        #expect(!GameMode.relaxed.hasLeaderboard)
    }

    /// 広告を外す購入をしていない人がちゃれんじで広告を見て取るのは、取れた数で 1・4・7・10…個目のりんご
    @Test(arguments: [(1, true), (2, false), (3, false), (4, true), (5, false), (6, false), (7, true), (10, true), (0, false)])
    func adApples(number: Int, expected: Bool) {
        #expect(Tuning.isAdApple(number: number) == expected)
    }

    /// 見送ったりんごは数えない。1 個目を見送ると次のりんごがまた 1 個目（広告）になり、取れたら 2・3 個目はそのまま、4 個目でまた広告
    @Test
    func declinedAppleIsNotCounted() {
        func needsAd(_ gained: Int) -> Bool {
            GameMode.challenge.needsAdForApple(applesGained: gained, adsRemoved: false)
        }
        var gained = 0
        #expect(needsAd(gained))   // 1 個目: 広告。見送る
        #expect(needsAd(gained))   // 見送ったので、次もまた 1 個目: 広告。見て取る
        gained += 1
        #expect(!needsAd(gained))  // 2 個目
        gained += 1
        #expect(!needsAd(gained))  // 3 個目
        gained += 1
        #expect(needsAd(gained))   // 4 個目: 広告
    }

    /// 広告を見て取るのは、ちゃれんじで広告を外す購入をしていない人だけ。広告を読み込めていないかどうかは関係しない
    @Test
    func adApplesOnlyInChallengeWithoutPurchase() {
        #expect(GameMode.challenge.needsAdForApple(applesGained: 0, adsRemoved: false))
        #expect(!GameMode.normal.needsAdForApple(applesGained: 0, adsRemoved: false))
        #expect(!GameMode.challenge.needsAdForApple(applesGained: 0, adsRemoved: true))
    }

    /// モードが 5 つになる前のチャレンジ（60 秒）の自己ベストは「ふつう」に移し、ちゃれんじには引き継がない
    @Test
    func migrateOldChallengeBestToNormal() throws {
        let defaults = try #require(UserDefaults(suiteName: "GameStateTests.migrate"))
        defaults.removePersistentDomain(forName: "GameStateTests.migrate")
        defaults.set(42, forKey: "best_challenge")

        GameState.migrateBestScores(defaults)
        #expect(defaults.integer(forKey: "best_normal") == 42)
        #expect(defaults.object(forKey: "best_challenge") == nil)

        // 2 回目以降は何もしない（ちゃれんじの新しい自己ベストを消さない）
        defaults.set(7, forKey: "best_challenge")
        GameState.migrateBestScores(defaults)
        #expect(defaults.integer(forKey: "best_challenge") == 7)
        defaults.removePersistentDomain(forName: "GameStateTests.migrate")
    }

    /// のんびりでおおかみをタップしても、点数は 0 点未満にならない
    @Test
    func scoreNeverGoesBelowZero() {
        let state = GameState(mode: .relaxed)
        state.addScore(-1)
        #expect(state.score == 0)
        state.addScore(3)
        state.addScore(-1)
        #expect(state.score == 2)
    }
}

struct DifficultyTests {
    /// 始めの値から ramp 秒かけて終わりの値になり、それ以降は終わりの値のまま
    @Test(arguments: [GameMode.easy, .normal, .hard, .challenge])
    func rampsFromStartToEnd(mode: GameMode) throws {
        let difficulty = try #require(mode.difficulty)
        #expect(difficulty.fallDuration(at: 0) == difficulty.fallStart)
        #expect(difficulty.fallDuration(at: difficulty.ramp) == difficulty.fallEnd)
        #expect(difficulty.fallDuration(at: difficulty.ramp * 3) == difficulty.fallEnd)
        #expect(difficulty.spawnInterval(at: 0) == difficulty.spawnStart)
        #expect(difficulty.spawnInterval(at: difficulty.ramp * 3) == difficulty.spawnEnd)
        #expect(difficulty.fallDuration(at: difficulty.ramp / 2) < difficulty.fallStart)
    }

    /// かんたん → ふつう → むずかしいの順に速い（始めも終わりも）
    @Test(arguments: [0.0, 30.0, 60.0])
    func harderModesAreFaster(elapsed: TimeInterval) throws {
        let modes = try [GameMode.easy, .normal, .hard].map { try #require($0.difficulty) }
        let falls = modes.map { $0.fallDuration(at: elapsed) }
        let spawns = modes.map { $0.spawnInterval(at: elapsed) }
        #expect(falls[0] > falls[1] && falls[1] > falls[2])
        #expect(spawns[0] > spawns[1] && spawns[1] > spawns[2])
    }

    /// ふつうは仕様書の初期値（落ちる 4.0 → 1.6 秒、間隔 0.9 → 0.35 秒）。ちゃれんじは、やがてむずかしいより速くなる
    @Test
    func normalMatchesSpecAndChallengeEndsFastest() throws {
        let normal = try #require(GameMode.normal.difficulty)
        #expect(normal.fallStart == 4.0 && normal.fallEnd == 1.6)
        #expect(normal.spawnStart == 0.9 && normal.spawnEnd == 0.35)
        let hard = try #require(GameMode.hard.difficulty)
        let challenge = try #require(GameMode.challenge.difficulty)
        #expect(challenge.fallEnd < hard.fallEnd)
        #expect(challenge.spawnEnd < hard.spawnEnd)
    }
}

struct L10nTests {
    @Test
    func pointsUseSignedNumbers() {
        #expect(L10n.points(3) == "+3")
        #expect(L10n.points(0) == "+0")
        #expect(L10n.points(-1) == "−1")
    }
}
