import Foundation

/// 画面に出す文字（日本語がキー。英語は文字列カタログで追加する）
enum L10n {
    static var oink: String { String(localized: "ぷひっ") }
    static var grr: String { String(localized: "ガオー！") }
    static var busted: String { String(localized: "バレた！") }
    static var uhOh: String { String(localized: "ギクッ") }
    static var safe: String { String(localized: "セーフ！") }
    static var plop: String { String(localized: "ぽてっ") }
    static var ouch: String { String(localized: "いてて…") }
    static var thud: String { String(localized: "ごとっ") }
    static var rolling: String { String(localized: "ころころ〜") }
    static var combo: String { String(localized: "コンボ！") }
    static var spotted: String { String(localized: "見破り！") }
    static var shieldOn: String { String(localized: "レンガで守る！") }
    static var appleUp: String { String(localized: "りんご +1") }

    static func points(_ value: Int) -> String {
        value >= 0 ? "+\(value)" : "−\(-value)"
    }

    static func introTitle(_ kind: ItemKind) -> String {
        switch kind {
        case .golden: String(localized: "金のこぶたは10点！")
        case .disguise: String(localized: "着ぐるみのおおかみに注意！")
        case .brick: String(localized: "レンガで守ろう")
        case .apple: String(localized: "りんごでひと休み")
        default: ""
        }
    }

    static func introBody(_ kind: ItemKind) -> String {
        switch kind {
        case .golden: String(localized: "たまにしか出ないごほうび")
        case .disguise: String(localized: "こぶたにそっくり。つり目としっぽをよく見て")
        case .brick: String(localized: "タップすると5秒間、おおかみを押しても平気")
        case .apple: String(localized: "チャレンジではりんごが1つ増える")
        default: ""
        }
    }

    static func name(_ kind: ItemKind) -> String {
        switch kind {
        case .piglet: String(localized: "こぶた")
        case .golden: String(localized: "金のこぶた")
        case .wolf: String(localized: "おおかみ")
        case .disguise: String(localized: "着ぐるみのおおかみ")
        case .brick: String(localized: "レンガ")
        case .apple: String(localized: "りんご")
        }
    }
}
