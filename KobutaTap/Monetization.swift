import Foundation

/// 課金と広告。いまは画面の出し分けのための仮の値（広告は #30 で AdMob、課金は StoreKit で置き換える）
enum Monetization {
    /// 広告を外す課金を購入済みか（StoreKitで置き換える）
    static var adsRemoved: Bool { UserDefaults.standard.bool(forKey: "adsRemoved") }
    /// リワード広告の準備ができているか（AdMobで置き換える）
    static var isRewardedAdReady: Bool { true }

    /// リワード広告を出し、最後まで見たら true を返す。途中で閉じたら false（AdMobで置き換える）。
    /// いまは広告が無いので、見たことにしてすぐ true を返す
    static func showRewardedAd() async -> Bool {
        true
    }
}
