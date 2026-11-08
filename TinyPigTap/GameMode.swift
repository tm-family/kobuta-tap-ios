import CoreGraphics
import Foundation

/// ゲームモード
enum GameMode: String, CaseIterable, Identifiable {
    case challenge   // 60秒・りんごのライフあり
    case relaxed     // 時間制限なし

    var id: String { rawValue }

    var title: String {
        switch self {
        case .challenge: String(localized: "チャレンジ")
        case .relaxed:   String(localized: "のんびり")
        }
    }

    var subtitle: String {
        switch self {
        case .challenge: String(localized: "60秒・りんご3つ")
        case .relaxed:   String(localized: "時間制限なし")
        }
    }

    var timeLimit: TimeInterval? { self == .challenge ? Tuning.challengeDuration : nil }
    var startingApples: Int? { self == .challenge ? Tuning.startingApples : nil }
}

/// チャレンジの時間帯（20秒ごとに切り替え）
enum Phase: Int, Comparable {
    case day, evening, night

    static func < (a: Phase, b: Phase) -> Bool { a.rawValue < b.rawValue }

    static func forElapsed(_ t: TimeInterval) -> Phase {
        if t < Tuning.eveningStarts { return .day }
        if t < Tuning.nightStarts { return .evening }
        return .night
    }
}

/// 調整用の数値はすべてここに集める（仕様書「難易度設計」の初期値）
enum Tuning {
    // チャレンジ
    static let challengeDuration: TimeInterval = 60
    static let eveningStarts: TimeInterval = 20
    static let nightStarts: TimeInterval = 40
    static let startingApples = 3
    static let maxApples = 5
    /// 画面の上から下まで落ちる秒数（終盤 ... 開始時）
    static let challengeFallDuration: ClosedRange<TimeInterval> = 1.6...4.0
    /// 次が出てくるまでの間隔（終盤 ... 開始時）
    static let challengeSpawnInterval: ClosedRange<TimeInterval> = 0.35...0.9

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

    // 画面
    /// 遊ぶ範囲の縦横比（iPhoneの比率に固定。iPadでは中央に置く）
    static let playAspect: CGFloat = 288.0 / 624.0
    /// 画面の下から地面（着地する高さ）までの割合
    static let groundRatio: CGFloat = 84.0 / 624.0
    /// キャラクターの幅（遊ぶ範囲の幅に対する割合）
    static let itemWidthRatio: CGFloat = 0.31
}
