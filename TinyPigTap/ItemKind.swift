import CoreGraphics
import Foundation

/// 降りてくるもの
enum ItemKind: String, CaseIterable, Hashable {
    case piglet     // こぶた
    case golden     // 金のこぶた
    case wolf       // おおかみ
    case disguise   // 着ぐるみのおおかみ
    case brick      // レンガ
    case apple      // りんご

    enum Pose: String { case normal, tapped, sit, run }

    var isAnimal: Bool { self != .brick && self != .apple }
    var isPiglet: Bool { self == .piglet || self == .golden }
    var isWolfLike: Bool { self == .wolf || self == .disguise }
    /// 初めて出てきたときにお知らせを出すか
    var hasIntro: Bool { self == .golden || self == .disguise || self == .brick || self == .apple }

    /// アセットカタログの画像名（仕様書「種類_状態」）
    func textureName(_ pose: Pose, hard: Bool = false) -> String {
        switch self {
        case .brick: return "item_brick"
        case .apple: return "item_apple"
        case .disguise where pose == .normal && hard: return "disguise_hard"
        default: return "\(rawValue)_\(pose.rawValue)"
        }
    }

    var umbrellaTexture: String {
        switch self {
        case .golden: "umbrella_gold"
        case .wolf: "umbrella_wolf"
        default: "umbrella_leaf"
        }
    }

    /// 基準の幅に対する大きさ
    var sizeFactor: CGFloat {
        switch self {
        case .piglet, .wolf, .disguise: 1.0
        case .golden: 0.85
        case .brick: 0.62
        case .apple: 0.5
        }
    }

    /// 高さ ÷ 幅（SVGの枠に合わせる）
    var aspect: CGFloat {
        switch self {
        case .brick: 104.0 / 160.0
        case .apple: 146.0 / 140.0
        default: 220.0 / 200.0
        }
    }

    /// 出現の重み（着ぐるみのおおかみの値は仮。仕様書の未決事項）
    func weight(mode: GameMode, phase: Phase) -> Int {
        switch mode {
        case .challenge:
            switch (self, phase) {
            case (.piglet, .day): 71
            case (.piglet, .evening): 63
            case (.piglet, .night): 54
            case (.golden, _): 5
            case (.wolf, .night): 16
            case (.wolf, _): 18
            case (.disguise, .day): 0
            case (.disguise, .evening): 8
            case (.disguise, .night): 18
            case (.brick, .night): 4
            case (.brick, _): 3
            case (.apple, _): 3
            }
        case .relaxed:
            switch self {
            case .piglet: 68
            case .golden: 5
            case .wolf: 10
            case .disguise: 8
            case .brick: 3
            case .apple: 6
            }
        }
    }

    static func random(mode: GameMode, phase: Phase) -> ItemKind {
        let table = allCases.map { ($0, $0.weight(mode: mode, phase: phase)) }
        let total = table.reduce(0) { $0 + $1.1 }
        var r = Int.random(in: 0..<max(total, 1))
        for (kind, w) in table {
            if r < w { return kind }
            r -= w
        }
        return .piglet
    }
}
