import Foundation

/// 課金と広告。広告は AdMob（Ads）。課金はいまは仮の値（StoreKit で置き換える）
enum Monetization {
    /// 広告を外す課金を購入済みか（StoreKitで置き換える）
    static var adsRemoved: Bool { UserDefaults.standard.bool(forKey: "adsRemoved") }
    /// リワード広告を出し、閉じるまで待つ
    static func showRewardedAd() async -> RewardedAdResult {
        await Ads.shared.show()
    }
}
