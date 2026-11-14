import Foundation
@testable import KobutaTap
import StoreKit
import StoreKitTest
import Testing

/// 課金「広告なし＋傘のきせかえ」。
/// 購入・返金は、コマンドラインのテスト実行では StoreKit のテスト環境が設定を書き込めず（SKInternalErrorDomain 3）、
/// 購入の確認待ちのまま止まるので、ここでは確かめない（TestFlight の Sandbox で確かめる）
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct StoreTests {
    private func makeSession() throws -> SKTestSession {
        let session = try SKTestSession(configurationFileNamed: "Products")
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        return session
    }

    private func makeDefaults(_ name: String) throws -> UserDefaults {
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// App Store Connect に登録した商品が読める（StoreKit の設定ファイルの商品 ID と合っている）
    @Test
    func productLoads() async throws {
        _ = try makeSession()
        let store = Store(defaults: try makeDefaults("StoreTests.product"))
        await store.loadProduct()
        let product = try #require(store.product)
        #expect(product.id == Store.premiumProductID)
        #expect(product.type == .nonConsumable)
    }

    /// 前回購入済みだったことは、起動直後（購入の権利を読む前）から使う
    @Test
    func rememberedPurchaseIsUsedAtLaunch() throws {
        let defaults = try makeDefaults("StoreTests.remembered")
        defaults.set(true, forKey: Store.purchasedKey)
        #expect(Store(defaults: defaults).isPurchased)
    }

    /// 復元の結果のダイアログ。やめたときは出さない
    @Test
    func restoreNotices() {
        #expect(DressUpView.notice(for: .restored)?.title == String(localized: "購入を復元しました"))
        #expect(DressUpView.notice(for: .notFound)?.title == String(localized: "復元できる購入がありません"))
        #expect(DressUpView.notice(for: .failed("理由"))?.message == "理由")
        #expect(DressUpView.notice(for: .cancelled) == nil)
    }
}
