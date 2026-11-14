import Foundation
@testable import KobutaTap
import SpriteKit
import Testing

/// アプリが裏に回ったときのひと休み（盤面を隠して止め、続けたらカウントダウンしてから再開する）
@MainActor
struct SuspendTests {
    private func makeScene(_ mode: GameMode = .normal) -> (GameScene, GameState) {
        let state = GameState(mode: mode)
        let scene = GameScene(size: CGSize(width: 390, height: 844), mode: mode, state: state)
        return (scene, state)
    }

    /// 止めたら盤面を隠し、続けてもカウントダウンが終わるまでは隠したまま。0 になったら盤面を出して動かす
    @Test
    func boardStaysHiddenUntilCountdownEnds() async throws {
        let (scene, state) = makeScene()
        scene.suspend()
        #expect(state.status == .suspended)
        #expect(state.hidesBoard)
        #expect(scene.isPaused)

        scene.resumeFromSuspension()
        #expect(state.status == .countdown)
        #expect(state.hidesBoard)
        #expect(scene.isPaused)

        let countdown = Tuning.countdownStep * Double(Tuning.countdownFrom)
        try await Task.sleep(for: .seconds(countdown + 0.6))
        #expect(state.status == .playing)
        #expect(!state.hidesBoard)
        #expect(!scene.isPaused)
    }

    /// カウントダウン中に裏に回ったら、カウントダウンをやめてひと休みに戻る（そのまま動き出さない）
    @Test
    func suspendDuringCountdownCancelsIt() async throws {
        let (scene, state) = makeScene()
        scene.suspend()
        scene.resumeFromSuspension()
        scene.suspend()
        #expect(state.status == .suspended)

        let countdown = Tuning.countdownStep * Double(Tuning.countdownFrom)
        try await Task.sleep(for: .seconds(countdown + 0.6))
        #expect(state.status == .suspended)
        #expect(state.hidesBoard)
        #expect(scene.isPaused)
    }

    /// 結果画面・続ける画面・お知らせなど、プレイ中でないときは何もしない
    @Test(arguments: [GameState.Status.finished, .askContinue, .appleOffer, .intro])
    func suspendIsIgnoredWhenNotPlaying(status: GameState.Status) {
        let (scene, state) = makeScene()
        state.status = status
        scene.suspend()
        #expect(state.status == status)
        #expect(!state.hidesBoard)
        scene.resumeFromSuspension()
        #expect(state.status == status)
    }
}
