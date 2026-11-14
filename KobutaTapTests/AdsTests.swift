import Foundation
@testable import KobutaTap
import StoreKit
import Testing

struct AdsTests {
    /// 途中で閉じたときだけ、りんご・続きを渡さない。広告を出せなかったときは広告なしで渡す
    @Test
    func rewardIsGrantedUnlessClosedEarly() {
        #expect(RewardedAdResult.rewarded.grantsReward)
        #expect(RewardedAdResult.unavailable.grantsReward)
        #expect(!RewardedAdResult.closedEarly.grantsReward)
    }

    /// 本番の広告は App Store から入れたアプリだけ。開発中と TestFlight（sandbox）はテスト用の広告
    @Test
    func testAdsOutsideAppStore() {
        #expect(Ads.usesTestAds(isDebugBuild: true, environment: .production))
        #expect(Ads.usesTestAds(isDebugBuild: false, environment: .sandbox))
        #expect(Ads.usesTestAds(isDebugBuild: false, environment: .xcode))
        #expect(!Ads.usesTestAds(isDebugBuild: false, environment: .production))
        // App Store に問い合わせられなかったときは、本番の広告にする
        #expect(!Ads.usesTestAds(isDebugBuild: false, environment: nil))
    }

    /// テスト中は、同意の画面・トラッキングの許可を出さず、広告も読み込まない
    @Test
    func adsAreDisabledWhileTesting() {
        #expect(Ads.isDisabled)
    }

    /// アプリ ID とユニット ID が同じ AdMob のアカウントのもので、テスト用のユニットは Google のもの
    @Test
    func unitIDsMatchAppID() throws {
        let appID = try #require(Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String)
        let publisher = try #require(appID.split(separator: "~").first)
        #expect(appID == "ca-app-pub-7683522872696760~5782134581")
        #expect(Ads.UnitID.rewarded.hasPrefix("\(publisher)/"))
        #expect(Ads.UnitID.testRewarded.hasPrefix("ca-app-pub-3940256099942544/"))
    }

    /// SKAdNetwork の ID に Google のものが入っていて、重複がない
    @Test
    func skAdNetworkItemsIncludeGoogle() throws {
        let items = try #require(Bundle.main.object(forInfoDictionaryKey: "SKAdNetworkItems") as? [[String: String]])
        let identifiers = items.compactMap { $0["SKAdNetworkIdentifier"] }
        #expect(identifiers.count == items.count)
        #expect(identifiers.contains("cstr6suwn9.skadnetwork"))
        #expect(Set(identifiers).count == identifiers.count)
        #expect(identifiers.allSatisfy { $0.hasSuffix(".skadnetwork") && $0 == $0.lowercased() })
    }

    /// トラッキングの許可を求めるときの説明が、英語（Info.plist）と日本語（InfoPlist.xcstrings）の両方にある
    @Test
    func trackingDescriptionIsLocalized() throws {
        let key = "NSUserTrackingUsageDescription"
        let english = try #require(Bundle.main.object(forInfoDictionaryKey: key) as? String)
        #expect(!english.isEmpty)
        let path = try #require(Bundle.main.path(forResource: "InfoPlist", ofType: "strings", inDirectory: nil, forLocalization: "ja"))
        let japanese = try #require(NSDictionary(contentsOfFile: path)?[key] as? String)
        #expect(japanese.contains("広告"))
    }
}
