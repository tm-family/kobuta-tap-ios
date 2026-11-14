import Foundation

/// 課金と広告の窓口。広告は AdMob（Ads）、課金は StoreKit（Store）
enum Monetization {
    /// 課金「広告なし＋傘のきせかえ」を購入済みか。購入済みなら、広告を見ずに続ける・りんごを取れる
    static var adsRemoved: Bool { Store.shared.isPurchased }
    /// リワード広告を出し、閉じるまで待つ
    static func showRewardedAd() async -> RewardedAdResult {
        await Ads.shared.show()
    }
}
