import AppTrackingTransparency
import Foundation
import GoogleMobileAds
import StoreKit
import UIKit
import UserMessagingPlatform

/// リワード広告を出した結果
enum RewardedAdResult: Equatable {
    /// 最後まで見た
    case rewarded
    /// 途中で閉じた
    case closedEarly
    /// 広告を用意できなかった（読み込めていない・古くなっていた・出せなかった）
    case unavailable

    /// ごほうび（りんご・続き）を渡すか。途中で閉じたときだけ渡さない。
    /// 広告を用意できなかったとき（オフラインなど）は、読み込めていないときと同じく広告なしで渡す
    var grantsReward: Bool { self != .closedEarly }
}

/// AdMob のリワード広告と、広告の同意（UMP）・トラッキングの許可（ATT）。
/// 起動したら、同意の確認 → トラッキングの許可 → 広告の読み込みの順に進める
@MainActor
@Observable
final class Ads {
    static let shared = Ads()

    enum UnitID {
        /// AdMob で作ったリワード広告のユニット
        static let rewarded = "ca-app-pub-7683522872696760/1331753686"
        /// Google のテスト用のリワード広告のユニット。開発中と TestFlight ではこちらを使い、本番の広告をタップしないようにする
        static let testRewarded = "ca-app-pub-3940256099942544/1712485313"
    }

    /// 読み込んだ広告を使える時間。AdMob の広告は 1 時間で使えなくなるので、少し早めに読み込み直す
    static let adLifetime: TimeInterval = 55 * 60

    /// 設定画面に「広告のプライバシー設定」を出すか（EEA・英国など、同意をあとから変えられるようにする必要がある地域）
    private(set) var isPrivacyOptionsRequired = false

    private var hasSetUp = false
    private var isStarted = false
    private var usesTestAds = true
    private var rewardedAd: RewardedAd?
    private var loadedAt: Date?
    private var isLoading = false
    private var failedLoads = 0
    private var presentation: Presentation?
    private let events = AdEvents()

    /// 出している広告。閉じたら continuation に結果を返す
    private struct Presentation {
        let continuation: CheckedContinuation<RewardedAdResult, Never>
        var earned = false
    }

    private init() {
        events.onDismiss = { [weak self] in self?.finishPresentation(presented: true) }
        events.onFailToPresent = { [weak self] in self?.finishPresentation(presented: false) }
    }

    /// テストと撮影モードでは、同意の画面もトラッキングの許可も出さず、広告も読み込まない
    static var isDisabled: Bool {
        let process = ProcessInfo.processInfo
        return ScreenshotDemo.isEnabled
            || process.arguments.contains("-disable-ads")
            || process.environment["XCTestConfigurationFilePath"] != nil
    }

    /// 本番の広告は App Store から入れたアプリだけで出す。開発中（Debug・Xcode から入れたもの）と TestFlight はテスト用の広告にする。
    /// どこから入れたか分からないとき（App Store に問い合わせられなかったなど）は、本番の広告にする
    nonisolated static func usesTestAds(isDebugBuild: Bool, environment: AppStore.Environment?) -> Bool {
        if isDebugBuild { return true }
        guard let environment else { return false }
        return environment != .production
    }

    /// 広告を見られる状態か（読み込み済みで、古くなっていない）
    var isReady: Bool { rewardedAd != nil && !isExpired }

    private var isExpired: Bool {
        guard let loadedAt else { return true }
        return Date.now.timeIntervalSince(loadedAt) > Self.adLifetime
    }

    /// 起動して画面が出たあとに 1 回呼ぶ
    func setUp() async {
        guard !Self.isDisabled, !hasSetUp, !Monetization.adsRemoved else { return }
        hasSetUp = true
        usesTestAds = await Self.detectTestAds()

        // 1. 広告の同意。EEA・英国などでは、同意の画面を出す（ほかの地域では何も出さない）
        let consent = ConsentInformation.shared
        do {
            try await consent.requestConsentInfoUpdate(with: Self.requestParameters())
            try await ConsentForm.loadAndPresentIfRequired(from: UIApplication.shared.topViewController)
        } catch {
            // 問い合わせに失敗したら、前回の同意のまま進める（canRequestAds が前回の結果を返す）
        }
        isPrivacyOptionsRequired = consent.privacyOptionsRequirementStatus == .required

        // 2. トラッキングの許可。許可しなくても、興味に合わせない広告が出る
        if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
            _ = await ATTrackingManager.requestTrackingAuthorization()
        }

        // 3. 広告の読み込み
        startIfAllowed()
    }

    /// プレイを始めるときに呼ぶ。広告が無い・古くなっていたら読み込み直す
    func prepare() {
        guard isStarted, !isReady else { return }
        rewardedAd = nil
        failedLoads = 0
        Task { await load() }
    }

    /// 設定画面の「広告のプライバシー設定」。同意をあとから変える画面を出す
    func presentPrivacyOptions() async {
        try? await ConsentForm.presentPrivacyOptionsForm(from: UIApplication.shared.topViewController)
        startIfAllowed()
    }

    /// リワード広告を出し、閉じるまで待つ。広告のあいだは BGM を止めておく
    func show() async -> RewardedAdResult {
        guard let ad = rewardedAd, !isExpired,
              let root = UIApplication.shared.topViewController,
              (try? ad.canPresent(from: root)) != nil else {
            prepare()
            return .unavailable
        }
        rewardedAd = nil
        loadedAt = nil
        SoundPlayer.shared.suspend()
        let result = await withCheckedContinuation { continuation in
            presentation = Presentation(continuation: continuation)
            ad.present(from: root) { [weak self] in
                self?.presentation?.earned = true
            }
        }
        SoundPlayer.shared.endSuspension()
        Task { await load() }
        return result
    }

    private func finishPresentation(presented: Bool) {
        guard let presentation else { return }
        self.presentation = nil
        let result: RewardedAdResult = if presentation.earned {
            .rewarded
        } else {
            presented ? .closedEarly : .unavailable
        }
        presentation.continuation.resume(returning: result)
    }

    private func startIfAllowed() {
        guard ConsentInformation.shared.canRequestAds else { return }
        if !isStarted {
            isStarted = true
            MobileAds.shared.start(completionHandler: nil)
        }
        Task { await load() }
    }

    /// 次に見せる広告を読み込んでおく。失敗したら、間隔を延ばしながら読み込み直す（30 秒・1 分・2 分…最長 10 分）
    private func load() async {
        guard isStarted, rewardedAd == nil, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let unitID = usesTestAds ? UnitID.testRewarded : UnitID.rewarded
        do {
            let ad = try await RewardedAd.load(with: unitID, request: Request())
            ad.fullScreenContentDelegate = events
            rewardedAd = ad
            loadedAt = .now
            failedLoads = 0
        } catch {
            failedLoads += 1
            let delay = min(30 * pow(2, Double(failedLoads - 1)), 600)
            Task {
                try? await Task.sleep(for: .seconds(delay))
                await load()
            }
        }
    }

    private static func detectTestAds() async -> Bool {
        #if DEBUG
        return true
        #else
        let environment = try? await AppTransaction.shared.unsafePayloadValue.environment
        return usesTestAds(isDebugBuild: false, environment: environment)
        #endif
    }

    private static func requestParameters() -> RequestParameters {
        let parameters = RequestParameters()
        #if DEBUG
        // 開発中に同意の画面を確かめるときは、起動引数で地域を変える（-ump_debug_geography 1 で EEA）
        let geography = UserDefaults.standard.integer(forKey: "ump_debug_geography")
        if let value = DebugGeography(rawValue: geography), value != .disabled {
            let debugSettings = DebugSettings()
            debugSettings.geography = value
            parameters.debugSettings = debugSettings
        }
        #endif
        return parameters
    }
}

/// 広告を閉じた・出せなかったことを受け取る（RewardedAd の delegate は弱参照なので、Ads が持っておく）
private final class AdEvents: NSObject, FullScreenContentDelegate {
    var onDismiss: () -> Void = {}
    var onFailToPresent: () -> Void = {}

    func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        onDismiss()
    }

    func ad(_ ad: any FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: any Error) {
        onFailToPresent()
    }
}
