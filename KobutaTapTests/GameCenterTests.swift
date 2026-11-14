import Foundation
import GameKit
@testable import KobutaTap
import Testing

/// ランキングを押してもサインインできなかったときの案内
@MainActor
struct GameCenterTests {
    /// サインインを閉じた・断った・端末でサインインしていないときは、「設定」アプリでのサインインを案内する
    @Test(arguments: [GKError.Code.cancelled, .userDenied, .notAuthenticated, .invalidCredentials])
    func signInProblemsLeadToSettings(code: GKError.Code) {
        #expect(GameCenter.help(for: GKError(code)) == .settings)
    }

    /// エラーが無いのにサインインできていないときも、「設定」アプリでのサインインを案内する
    @Test
    func missingErrorLeadsToSettings() {
        #expect(GameCenter.help(for: nil) == .settings)
    }

    /// 通信などでつながらなかったときは、理由を添えて、もう一度押してもらう
    @Test
    func otherErrorsShowTheReason() {
        let error = GKError(.communicationsFailure)
        #expect(GameCenter.help(for: error) == .failed(error.localizedDescription))
        let offline = URLError(.notConnectedToInternet)
        #expect(GameCenter.help(for: offline) == .failed(offline.localizedDescription))
    }

    /// 案内の見出しと本文が、どちらの場合も空でない
    @Test
    func helpHasTitleAndMessage() {
        for help in [GameCenter.SignInHelp.settings, .failed("理由")] {
            #expect(!help.title.isEmpty)
            #expect(!help.message.isEmpty)
        }
        #expect(GameCenter.SignInHelp.failed("理由").message.contains("理由"))
    }
}
