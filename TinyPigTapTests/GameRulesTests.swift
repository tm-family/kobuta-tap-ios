//
//  GameRulesTests.swift
//  TinyPigTapTests
//
//  仕様書の「ゲームルール」「難易度設計」「背景」の決まりが、コードの値と合っているかを確かめる。
//

import Foundation
import Testing
@testable import TinyPigTap

struct PhaseTests {
    /// チャレンジは 20 秒ごとに昼 → 夕焼け → 夜へ切り替わる
    @Test(arguments: [
        (0.0, Phase.day), (19.9, .day),
        (20.0, .evening), (39.9, .evening),
        (40.0, .night), (60.0, .night)
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
    @Test(arguments: [
        (GameMode.challenge, Phase.day), (.challenge, .evening), (.challenge, .night), (.relaxed, .day)
    ])
    func weightsSumToHundred(mode: GameMode, phase: Phase) {
        let total = ItemKind.allCases.reduce(0) { $0 + $1.weight(mode: mode, phase: phase) }
        #expect(total == 100)
    }

    /// のんびりは時間帯で出現率を変えない
    @Test
    func relaxedWeightsDoNotDependOnPhase() {
        for kind in ItemKind.allCases {
            let weights = [Phase.day, .evening, .night].map { kind.weight(mode: .relaxed, phase: $0) }
            #expect(Set(weights).count == 1, "\(kind)")
        }
    }

    /// 着ぐるみのおおかみは、チャレンジの昼には出ない（夕焼けで初登場）
    @Test
    func disguiseNeverAppearsInChallengeDay() {
        #expect(ItemKind.disguise.weight(mode: .challenge, phase: .day) == 0)
        for _ in 0..<500 {
            #expect(ItemKind.random(mode: .challenge, phase: .day) != .disguise)
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
    /// チャレンジは 60 秒・りんご 3 つ、のんびりは時間もりんごもなし
    @Test
    func initialValuesByMode() {
        let challenge = GameState(mode: .challenge)
        #expect(challenge.timeRemaining == 60)
        #expect(challenge.apples == 3)

        let relaxed = GameState(mode: .relaxed)
        #expect(relaxed.timeRemaining == nil)
        #expect(relaxed.apples == nil)
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

struct L10nTests {
    @Test
    func pointsUseSignedNumbers() {
        #expect(L10n.points(3) == "+3")
        #expect(L10n.points(0) == "+0")
        #expect(L10n.points(-1) == "−1")
    }
}
