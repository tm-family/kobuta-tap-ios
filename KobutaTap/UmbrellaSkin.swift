import Foundation

/// こぶたと着ぐるみのおおかみがさす傘（きせかえ）。葉っぱの傘は無料で、ほかは課金「広告なし＋傘のきせかえ」で使える。
/// 金のこぶたとおおかみの傘は、きせかえの対象外。
/// 絵は Tools/generate_umbrella_skins.py が、葉っぱの傘の絵から書き出す（KobutaAssets.xcassets/UmbrellaSkins）
enum UmbrellaSkin: String, CaseIterable, Identifiable {
    case leaf, sakura, sunflower, momiji, snow, polkadot

    /// 選んだ傘を覚えておくキー
    static let selectedKey = "umbrella_skin"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leaf: String(localized: "葉っぱ")
        case .sakura: String(localized: "桜")
        case .sunflower: String(localized: "ひまわり")
        case .momiji: String(localized: "紅葉")
        case .snow: String(localized: "雪の結晶")
        case .polkadot: String(localized: "水玉")
        }
    }

    /// 購入しなくても使えるか
    var isFree: Bool { self == .leaf }

    /// キャラクターの絵の名前の後ろに付ける（葉っぱはこれまでの絵のまま）
    var textureSuffix: String { isFree ? "" : "_\(rawValue)" }

    /// 着地して落とす傘と、きせかえ画面の見本の絵
    var umbrellaTexture: String { "umbrella_\(rawValue)" }

    /// いま使う傘。購入していなければ、選んでいても葉っぱの傘にする
    static func current(purchased: Bool, defaults: UserDefaults = .standard) -> UmbrellaSkin {
        guard purchased,
              let raw = defaults.string(forKey: selectedKey),
              let skin = UmbrellaSkin(rawValue: raw) else { return .leaf }
        return skin
    }

    /// 傘を選ぶ（購入しているかどうかは、きせかえ画面が確かめる）
    static func select(_ skin: UmbrellaSkin, defaults: UserDefaults = .standard) {
        defaults.set(skin.rawValue, forKey: selectedKey)
    }
}
