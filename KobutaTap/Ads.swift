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
    /// 広告を出せなかった（その場で読み込んでも用意できなかった・出すのに失敗した）
    case unavailable(AdUnavailableReason)

    /// ごほうび（りんご・続き）を渡すか。広告を最後まで見たときだけ渡す（広告を出せなかったときも渡さない）
    var grantsReward: Bool { self == .rewarded }
}

/// 広告を出せなかった理由。ダイアログの文言を書き分ける
enum AdUnavailableReason: Equatable {
    /// 通信できない・通信に失敗した
    case network
    /// 広告の在庫がない・SDK の準備ができていないなど
    case other

    var title: String { String(localized: "広告を表示できませんでした") }

    var message: String {
        switch self {
        case .network: String(localized: "ネットワークを見直してみてね")
        case .other: String(localized: "いまは広告を用意できなかったよ。少し待ってから、もう一度ためしてね")
        }
    }

    /// 広告の SDK・通信のエラーから理由を決める。通信のエラーが下の理由に入っているときも、通信できないとみなす
    nonisolated static func from(_ error: (any Error)?) -> AdUnavailableReason {
        guard let error else { return .other }
        if let adError = error as? GoogleMobileAds.RequestError, [.networkError, .timeout].contains(adError.code) {
            return .network
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain { return .network }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? any Error {
            return from(underlying)
        }
        return .other
    }
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
    /// 広告を見るボタンを押したときに、広告が無ければその場で読み込んで待つ時間
    static let loadOnDemandTimeout: Duration = .seconds(8)

    /// 設定画面に「広告のプライバシー設定」を出すか（EEA・英国など、同意をあとから変えられるようにする必要がある地域）
    private(set) var isPrivacyOptionsRequired = false

    private var hasSetUp = false
    private var isStarted = false
    private var usesTestAds = true
    private var rewardedAd: RewardedAd?
    private var loadedAt: Date?
    private var isLoading = false
    private var failedLoads = 0
    /// 最後に読み込みに失敗したときのエラー（広告を出せなかった理由に使う）
    private var lastLoadError: (any Error)?
    private var presentation: Presentation?
    private let events = AdEvents()

    /// 出している広告。閉じたら continuation に結果を返す
    private struct Presentation {
        let continuation: CheckedContinuation<RewardedAdResult, Never>
        var earned = false
    }

    private init() {
        events.onDismiss = { [weak self] in self?.finishPresentation(failure: nil) }
        events.onFailToPresent = { [weak self] error in self?.finishPresentation(failure: error) }
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

    /// リワード広告を出し、閉じるまで待つ。広告のあいだは BGM を止めておく。
    /// 広告が無いときは、その場で読み込んで少し待つ。それでも出せなければ、理由を付けて .unavailable を返す
    func show() async -> RewardedAdResult {
        if !isReady { await loadNow() }
        guard let ad = rewardedAd, !isExpired, let root = UIApplication.shared.topViewController else {
            return .unavailable(.from(lastLoadError))
        }
        do {
            try ad.canPresent(from: root)
        } catch {
            rewardedAd = nil
            loadedAt = nil
            Task { await load() }
            return .unavailable(.from(error))
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

    /// 広告を閉じた（failure が nil）・出すのに失敗したとき
    private func finishPresentation(failure: (any Error)?) {
        guard let presentation else { return }
        self.presentation = nil
        let result: RewardedAdResult = if presentation.earned {
            .rewarded
        } else if let failure {
            .unavailable(.from(failure))
        } else {
            .closedEarly
        }
        presentation.continuation.resume(returning: result)
    }

    /// 広告が無い・古くなっていたら、読み込み直しを待たずにその場で読み込む。
    /// 読み込めたら、または失敗したら、または待ち時間を過ぎたら戻る
    private func loadNow() async {
        guard isStarted else { return }
        if rewardedAd != nil {
            rewardedAd = nil
            loadedAt = nil
        }
        if !isLoading { Task { await load() } }
        let deadline = ContinuousClock.now + Self.loadOnDemandTimeout
        while !isReady, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(200))
            if !isLoading { break }
        }
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
            lastLoadError = nil
        } catch {
            lastLoadError = error
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
    var onFailToPresent: (any Error) -> Void = { _ in }

    func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        onDismiss()
    }

    func ad(_ ad: any FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: any Error) {
        onFailToPresent(error)
    }
}
