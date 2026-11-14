import GameKit
import UIKit

/// Game Center のランキング（チャレンジの自己ベスト）。
///
/// サインインは起動時には求めず、初めてランキングを開いたときに求める。
/// 一度ランキングを開いたことがあれば、次の起動からは裏でサインインを済ませ、チャレンジの点数を送れるようにする
/// （このときサインインの画面が要っても出さず、ランキングを開いたときに出す）。
@MainActor
@Observable
final class GameCenter {
    static let shared = GameCenter()

    /// App Store Connect のリーダーボードの ID（AppStore/game_center.json の vendorIdentifier）
    static let leaderboardID = "challenge_best"
    /// ランキングを開いたことがあるか
    private static let openedKey = "gamecenter_opened"

    /// サインインを待つ時間。GameKit が返事をしないときに、押しても何も起きないままにしない
    static let authenticationTimeout: Duration = .seconds(15)
    /// 一度サインインに失敗したあとに試し直すときの待ち時間。
    /// 断られたあとなどは、handler を設定し直しても GameKit が返事をしないので、前回の理由で早めに案内する
    static let retryTimeout: Duration = .seconds(3)

    /// ランキングを押してもサインインできなかったときの案内。nil のときは出さない
    var signInHelp: SignInHelp?

    private var isAuthenticating = false
    /// 何回目のサインインか（古いサインインの待ち時間切れを無視する）
    private var authenticationAttempt = 0
    /// サインインが済んだら、ランキングを開く
    private var opensAfterSignIn = false
    /// Game Center のサインインの画面を出しているか（入力に時間がかかっても、待ち時間切れにしない）
    private var isShowingSignIn = false
    /// Game Center が出したサインインの画面。ランキングを開くときまで出さずに持っておく
    private var signInViewController: UIViewController?
    /// 前回サインインに失敗したときのエラー（案内の書き分けに使う）。一度も失敗していなければ nil
    private var lastFailure: (any Error)?
    /// サインインに失敗したことがあるか（エラーが無い失敗もあるので、lastFailure とは別に持つ）
    private var hasFailed = false

    /// サインインできなかったときの案内の種類
    enum SignInHelp: Equatable {
        /// 端末で Game Center にサインインしていない・サインインの画面を閉じた。「設定」アプリでのサインインを案内する
        case settings
        /// 通信などでつながらなかった。GameKit のエラーの説明を添える
        case failed(String)

        var title: String {
            switch self {
            case .settings: String(localized: "Game Center にサインインしてください")
            case .failed: String(localized: "Game Center につながりませんでした")
            }
        }

        var message: String {
            switch self {
            case .settings:
                String(localized: """
                「設定」アプリを開き、「Game Center」で Apple アカウントにサインインしてください。サインインしたら、このアプリに戻ってもう一度ランキングを押すと開きます。

                Game Center のサインインの画面を何度か閉じると、アプリからはサインインの画面を出せなくなります。\
                すでにサインインしているのにこの案内が出るときは、「設定」アプリの「Game Center」で一度サインアウトし、サインインし直してください。
                """)
            case .failed(let reason):
                String(localized: "通信できるところで、もう一度ランキングを押してください。\n（\(reason)）")
            }
        }
    }

    private init() {}

    /// 起動時に呼ぶ。ランキングを開いたことがあるときだけ、裏でサインインを済ませる
    func signInIfOpenedBefore() {
        guard UserDefaults.standard.bool(forKey: Self.openedKey),
              GKLocalPlayer.local.authenticateHandler == nil else { return }
        authenticate()
    }

    /// ランキングを開く。サインインしていなければ、先にサインインを求める。
    /// 起動時の裏のサインインがうまくいかなかったときも、ここでサインインを試し直す
    func showLeaderboard() {
        UserDefaults.standard.set(true, forKey: Self.openedKey)
        signInHelp = nil
        if GKLocalPlayer.local.isAuthenticated {
            present()
            return
        }
        opensAfterSignIn = true
        if let signInViewController {
            self.signInViewController = nil
            showSignIn(signInViewController)
        } else if !isAuthenticating {
            authenticate()
        }
    }

    /// GameKit のエラーから、どの案内を出すかを決める。
    /// サインインを閉じた・断った（何度か閉じると、Game Center はアプリからサインインの画面を出さなくなる）ときは「設定」アプリへ
    static func help(for error: (any Error)?) -> SignInHelp {
        guard let error else { return .settings }
        guard let gameKitError = error as? GKError else { return .failed(error.localizedDescription) }
        switch gameKitError.code {
        case .cancelled, .userDenied, .notAuthenticated, .invalidCredentials:
            return .settings
        default:
            return .failed(gameKitError.localizedDescription)
        }
    }

    /// チャレンジの点数を送る。サインインしていなければ何もしない。失敗してもプレイは止めない
    func submit(score: Int) {
        guard GKLocalPlayer.local.isAuthenticated, score > 0 else { return }
        Task {
            try? await GKLeaderboard.submitScore(
                score, context: 0, player: GKLocalPlayer.local, leaderboardIDs: [Self.leaderboardID]
            )
        }
    }

    /// サインインを始める。handler を設定し直すと GameKit がもう一度試すことがあるが、
    /// サインインを断られたあとなどは返事をしないので、待ち時間を過ぎたら案内を出す
    private func authenticate() {
        isAuthenticating = true
        authenticationAttempt += 1
        let attempt = authenticationAttempt
        let timeout = hasFailed ? Self.retryTimeout : Self.authenticationTimeout
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            MainActor.assumeIsolated {
                self?.handleAuthentication(viewController, error: error)
            }
        }
        Task { [weak self] in
            try? await Task.sleep(for: timeout)
            self?.timeOut(attempt)
        }
    }

    /// ランキングを押したのに GameKit が返事をしないとき。前に失敗していればその理由で、なければつながらなかったと案内する
    private func timeOut(_ attempt: Int) {
        guard attempt == authenticationAttempt, isAuthenticating, opensAfterSignIn, !isShowingSignIn else { return }
        isAuthenticating = false
        opensAfterSignIn = false
        signInHelp = hasFailed
            ? Self.help(for: lastFailure)
            : .failed(String(localized: "Game Center から応答がありませんでした"))
    }

    private func showSignIn(_ viewController: UIViewController) {
        isShowingSignIn = true
        Self.presentOnTop(viewController)
    }

    private func handleAuthentication(_ viewController: UIViewController?, error: (any Error)?) {
        if let viewController {
            if opensAfterSignIn {
                showSignIn(viewController)
            } else {
                signInViewController = viewController
            }
            return
        }
        isAuthenticating = false
        isShowingSignIn = false
        let opens = opensAfterSignIn
        opensAfterSignIn = false
        guard GKLocalPlayer.local.isAuthenticated else {
            hasFailed = true
            lastFailure = error
            if opens { signInHelp = Self.help(for: error) }
            return
        }
        hasFailed = false
        lastFailure = nil
        // サインインする前に出した自己ベストも、ランキングに載せる
        submit(score: UserDefaults.standard.integer(forKey: "best_\(GameMode.challenge.rawValue)"))
        if opens { present() }
    }

    private func present() {
        if #available(iOS 18.0, *) {
            GKAccessPoint.shared.trigger(leaderboardID: Self.leaderboardID, playerScope: .global, timeScope: .allTime) {}
        } else {
            let viewController = GKGameCenterViewController(
                leaderboardID: Self.leaderboardID, playerScope: .global, timeScope: .allTime
            )
            viewController.gameCenterDelegate = LeaderboardDismisser.shared
            Self.presentOnTop(viewController)
        }
    }

    /// いちばん手前の画面の上に出す
    private static func presentOnTop(_ viewController: UIViewController) {
        UIApplication.shared.topViewController?.present(viewController, animated: true)
    }
}

/// iOS 17 のランキング画面（GKGameCenterViewController）の「完了」で閉じる
private final class LeaderboardDismisser: NSObject, GKGameCenterControllerDelegate {
    static let shared = LeaderboardDismisser()

    func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        gameCenterViewController.dismiss(animated: true)
    }
}
