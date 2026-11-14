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

    /// アセットカタログの画像名（仕様書「種類_状態」）。こぶたと着ぐるみのおおかみは、傘のきせかえに合わせた絵にする
    func textureName(_ pose: Pose, hard: Bool = false, skin: UmbrellaSkin = .leaf) -> String {
        let base: String
        switch self {
        case .brick: return "item_brick"
        case .apple: return "item_apple"
        case .disguise where pose == .normal && hard: base = "disguise_hard"
        default: base = "\(rawValue)_\(pose.rawValue)"
        }
        // 座った絵は傘を落としているので、きせかえの絵は無い
        guard usesUmbrellaSkin, pose != .sit else { return base }
        return base + skin.textureSuffix
    }

    /// 傘のきせかえの対象か（金のこぶたとおおかみの傘は対象外）。
    /// 着ぐるみのおおかみも、こぶたと同じ傘をさす（違う傘だと、傘だけで見分けられてしまうため）
    var usesUmbrellaSkin: Bool { self == .piglet || self == .disguise }

    /// 着地して落とす傘の絵
    func umbrellaTexture(skin: UmbrellaSkin = .leaf) -> String {
        switch self {
        case .golden: "umbrella_gold"
        case .wolf: "umbrella_wolf"
        default: skin.umbrellaTexture
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

    /// 出現の重み（合計 100）。着ぐるみのおおかみの値は仮のまま（2026-11-14 に、仮の値で進めると決めた）
    ///
    /// のんびり以外は、ふつうの表（時間帯ごと）のおおかみ・着ぐるみのおおかみを難易度の倍率で増減し、
    /// 増減した分はこぶたで埋めて合計を 100 にそろえる
    func weight(mode: GameMode, phase: Phase) -> Int {
        guard let difficulty = mode.difficulty else { return relaxedWeight }
        if self == .piglet {
            let others = ItemKind.allCases.filter { $0 != .piglet }
            return 100 - others.reduce(0) { $0 + $1.weight(mode: mode, phase: phase) }
        }
        let base = playWeights[phase.rawValue]
        return isWolfLike ? Int((Double(base) * difficulty.wolfFactor).rounded()) : base
    }

    /// ふつうの出現の重み（昼・夕焼け・夜の順。仕様書 3.2 の表の行）
    private var playWeights: [Int] {
        switch self {
        case .piglet: [71, 63, 54]
        case .golden: [5, 5, 5]
        case .wolf: [18, 18, 16]
        case .disguise: [0, 8, 18]
        case .brick: [3, 3, 4]
        case .apple: [3, 3, 3]
        }
    }

    /// のんびりの出現の重み
    private var relaxedWeight: Int {
        switch self {
        case .piglet: 68
        case .golden: 5
        case .wolf: 10
        case .disguise: 8
        case .brick: 3
        case .apple: 6
        }
    }

    static func random(mode: GameMode, phase: Phase) -> ItemKind {
        let table = allCases.map { ($0, $0.weight(mode: mode, phase: phase)) }
        let total = table.reduce(0) { $0 + $1.1 }
        var roll = Int.random(in: 0..<max(total, 1))
        for (kind, weight) in table {
            if roll < weight { return kind }
            roll -= weight
        }
        return .piglet
    }
}
