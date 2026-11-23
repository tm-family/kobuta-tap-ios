import Foundation
import StoreKit

/// アプリ内課金「広告なし＋傘のきせかえ」（StoreKit 2。非消耗型の 1 商品）。
/// 購入すると、広告を見ずに続ける・りんごを取れ、傘のきせかえが使える。
/// 購入済みかは購入の権利（Transaction.currentEntitlements）で決め、起動直後や通信できないときのために前回の結果も覚えておく
@MainActor
@Observable
final class Store {
    static let shared = Store()

    /// App Store Connect の商品 ID（AppStore/in_app_purchases.json の productId）
    static let premiumProductID = "jp.shilokuma.TinyPigTap.premium"
    /// 購入済みかを覚えておくキー
    static let purchasedKey = "premium_purchased"

    /// 購入の結果
    enum PurchaseOutcome: Equatable {
        case purchased
        case cancelled
        /// 保護者の承認待ち（承認されたら Transaction.updates で届く）
        case pending
        case failed(String)
    }

    /// 購入を復元した結果
    enum RestoreOutcome: Equatable {
        case restored
        case notFound
        case cancelled
        case failed(String)
    }

    /// App Store の商品（値段の表示に使う）。読み込めていなければ nil
    private(set) var product: Product?
    private(set) var isPurchased: Bool

    private let defaults: UserDefaults
    private var updatesTask: Task<Void, Never>?
    /// 開発中に、購入済みの見た目を確かめるための上書き（Debug ビルドで `-debug_premium YES`）
    private let isOverridden: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        #if DEBUG
        isOverridden = defaults.bool(forKey: "debug_premium")
        #else
        isOverridden = false
        #endif
        isPurchased = isOverridden || defaults.bool(forKey: Self.purchasedKey)
    }

    /// 起動時に 1 回呼ぶ。ほかの端末での購入・返金・保護者の承認を受け取れるよう、Transaction.updates を見張る。
    /// 単体テストの実行中は動かさない（テストの購入で、アプリの購入済みの記録が書き換わらないように）。撮影モードでも動かさない
    func start() {
        guard updatesTask == nil,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              !ScreenshotDemo.isEnabled else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
        Task {
            await refresh()
            await loadProduct()
        }
    }

    /// 商品を読み込む（値段の表示用）
    func loadProduct() async {
        // 撮影モードでは読まない（ストアの国で値段の表示が変わり、撮るたびに画面がそろわないため）
        guard product == nil, !ScreenshotDemo.isEnabled else { return }
        product = try? await Product.products(for: [Self.premiumProductID]).first
    }

    /// 購入の権利から、購入済みかを決め直す（返金されたものは権利に入らない）
    func refresh() async {
        var purchased = false
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement,
               transaction.productID == Self.premiumProductID,
               transaction.revocationDate == nil {
                purchased = true
            }
        }
        setPurchased(purchased)
    }

    /// 購入ボタン（SwiftUI の purchase アクション）の結果を受け取る
    func handle(_ result: Product.PurchaseResult) async -> PurchaseOutcome {
        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                return .failed(String(localized: "購入を確かめられませんでした"))
            }
            await transaction.finish()
            if transaction.productID == Self.premiumProductID {
                setPurchased(true)
            }
            return .purchased
        case .userCancelled:
            return .cancelled
        case .pending:
            return .pending
        @unknown default:
            return .failed(String(localized: "購入できませんでした"))
        }
    }

    /// 購入を復元する（App Store と同期し、購入の権利を読み直す）。Apple アカウントのサインインを求められることがある
    func restore() async -> RestoreOutcome {
        do {
            try await AppStore.sync()
        } catch StoreKitError.userCancelled {
            return .cancelled
        } catch {
            return .failed(error.localizedDescription)
        }
        await refresh()
        return isPurchased ? .restored : .notFound
    }

    private func handle(_ update: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = update else { return }
        if transaction.productID == Self.premiumProductID {
            setPurchased(transaction.revocationDate == nil)
        }
        await transaction.finish()
    }

    private func setPurchased(_ purchased: Bool) {
        guard !isOverridden else { return }
        isPurchased = purchased
        defaults.set(purchased, forKey: Self.purchasedKey)
    }
}
