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

    /// サインインできなかったときに、「設定」アプリでのサインインを案内する
    var showsSignInHelp = false

    private var isAuthenticating = false
    /// サインインが済んだら、ランキングを開く
    private var opensAfterSignIn = false
    /// Game Center が出したサインインの画面。ランキングを開くときまで出さずに持っておく
    private var signInViewController: UIViewController?

    private init() {}

    /// 起動時に呼ぶ。ランキングを開いたことがあるときだけ、裏でサインインを済ませる
    func signInIfOpenedBefore() {
        guard UserDefaults.standard.bool(forKey: Self.openedKey),
              GKLocalPlayer.local.authenticateHandler == nil else { return }
        authenticate()
    }

    /// ランキングを開く。サインインしていなければ、先にサインインを求める
    func showLeaderboard() {
        UserDefaults.standard.set(true, forKey: Self.openedKey)
        if GKLocalPlayer.local.isAuthenticated {
            present()
        } else if let signInViewController {
            self.signInViewController = nil
            opensAfterSignIn = true
            Self.presentOnTop(signInViewController)
        } else if isAuthenticating {
            opensAfterSignIn = true
        } else if GKLocalPlayer.local.authenticateHandler == nil {
            opensAfterSignIn = true
            authenticate()
        } else {
            // 一度サインインを断ると、Game Center はもうサインインの画面を出さない
            showsSignInHelp = true
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

    private func authenticate() {
        isAuthenticating = true
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, _ in
            MainActor.assumeIsolated {
                self?.handleAuthentication(viewController)
            }
        }
    }

    private func handleAuthentication(_ viewController: UIViewController?) {
        if let viewController {
            if opensAfterSignIn {
                Self.presentOnTop(viewController)
            } else {
                signInViewController = viewController
            }
            return
        }
        isAuthenticating = false
        let opens = opensAfterSignIn
        opensAfterSignIn = false
        guard GKLocalPlayer.local.isAuthenticated else {
            if opens { showsSignInHelp = true }
            return
        }
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
        var top = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?
            .rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        top?.present(viewController, animated: true)
    }
}

/// iOS 17 のランキング画面（GKGameCenterViewController）の「完了」で閉じる
private final class LeaderboardDismisser: NSObject, GKGameCenterControllerDelegate {
    static let shared = LeaderboardDismisser()

    func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        gameCenterViewController.dismiss(animated: true)
    }
}
