import Foundation

/// 課金と広告は5番目の段階で組み込む。いまは画面の出し分けのための仮の値
enum Monetization {
    /// 広告を外す課金を購入済みか（StoreKitで置き換える）
    static var adsRemoved: Bool { UserDefaults.standard.bool(forKey: "adsRemoved") }
    /// リワード広告の準備ができているか（AdMobで置き換える）
    static var isRewardedAdReady: Bool { true }
}
