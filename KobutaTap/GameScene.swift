import SpriteKit
import UIKit

/// 降りてくる1つ1つ
final class ItemNode: SKSpriteNode {
    let kind: ItemKind
    /// タップされた、または着地して結果が確定したら true。以降はタップに反応しない
    var isResolved = false

    init(kind: ItemKind, textureName: String, width: CGFloat) {
        self.kind = kind
        let texture = SKTexture(imageNamed: textureName)
        let size = CGSize(width: width * kind.sizeFactor, height: width * kind.sizeFactor * kind.aspect)
        super.init(texture: texture, color: .clear, size: size)
        // 動物は傘の上を支点に揺らす（README参照）
        anchorPoint = kind.isAnimal ? CGPoint(x: 0.62, y: 0.82) : CGPoint(x: 0.5, y: 0.5)
        zPosition = 10
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

@MainActor
final class GameScene: SKScene {
    private let mode: GameMode
    private let state: GameState

    private var elapsed: TimeInterval = 0
    private var lastUpdate: TimeInterval?
    private var spawnTimer: TimeInterval = 0
    private let background: BackgroundNode
    private var clockCheckTimer: TimeInterval = 0
    private var countdownTask: Task<Void, Never>?

    init(size: CGSize, mode: GameMode, state: GameState) {
        self.mode = mode
        self.state = state
        let scenery: Scenery = mode == .relaxed ? .now() : .challenge(.day)
        state.phase = scenery.phase
        background = BackgroundNode(scenery: scenery)
        super.init(size: size)
        scaleMode = .resizeFill
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMove(to view: SKView) {
        Haptics.prepare()
        backgroundColor = .black
        if background.parent == nil { addChild(background) }
        background.layout(size: size)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        background.layout(size: size)
    }

    // MARK: - 遊ぶ範囲（iPhoneの比率に固定し、iPadでは中央に置く）

    var playRect: CGRect {
        let width = min(size.width, size.height * Tuning.playAspect)
        return CGRect(x: (size.width - width) / 2, y: 0, width: width, height: size.height)
    }
    var groundY: CGFloat { size.height * Tuning.groundRatio }
    private var baseWidth: CGFloat { playRect.width * Tuning.itemWidthRatio }

    // MARK: - 難易度

    private var fallDuration: TimeInterval {
        mode.difficulty?.fallDuration(at: elapsed) ?? Tuning.relaxedFallDuration
    }

    private var spawnInterval: TimeInterval {
        mode.difficulty?.spawnInterval(at: elapsed) ?? Tuning.relaxedSpawnInterval
    }

    // MARK: - ループ

    override func update(_ currentTime: TimeInterval) {
        defer { lastUpdate = currentTime }
        // プレイ中でなければ止めておく。アプリに戻ったときに SpriteKit が動かし始めても、ここで止め直す
        guard state.status == .playing else {
            isPaused = true
            return
        }
        let delta = min(lastUpdate.map { currentTime - $0 } ?? 0, 0.1)

        elapsed += delta
        spawnTimer += delta

        if mode != .relaxed {
            background.updateSkyBodies(elapsed: elapsed)
            let phase = Phase.forElapsed(elapsed)
            if phase != state.phase {
                state.phase = phase
                background.transition(to: .challenge(phase), size: size)
            }
        } else {
            // のんびりは端末の時計と日付に合わせる（30秒ごとに確認）
            clockCheckTimer += delta
            if clockCheckTimer >= 30 {
                clockCheckTimer = 0
                let scenery = Scenery.now()
                if scenery != background.scenery {
                    state.phase = scenery.phase
                    background.transition(to: scenery, size: size)
                }
            }
        }

        if state.shieldRemaining > 0 {
            state.shieldRemaining = max(0, state.shieldRemaining - delta)
        }

        if let timeRemaining = state.timeRemaining {
            let remaining = max(0, timeRemaining - delta)
            state.timeRemaining = remaining
            if remaining == 0 { endGame(); return }
        }

        if spawnTimer >= spawnInterval {
            spawnTimer = 0
            spawn()
        }
    }

    // MARK: - 出現

    private func spawn() {
        let kind = ItemKind.random(mode: mode, phase: state.phase)
        let hard = mode != .relaxed && state.phase == .night
        let node = ItemNode(kind: kind, textureName: kind.textureName(.normal, hard: hard), width: baseWidth)

        let margin = node.size.width * 0.5
        let rect = playRect
        node.position = CGPoint(x: .random(in: (rect.minX + margin)...(rect.maxX - margin)),
                                y: size.height + node.size.height)
        addChild(node)

        if kind.isAnimal { startSway(node) }

        // 足もと（アイテムは中心）が地面に着く高さまで落とす
        let targetY = kind.isAnimal
            ? groundY + node.size.height * (node.anchorPoint.y - 0.03)
            : groundY + node.size.height * 0.5
        let fall = SKAction.moveTo(y: targetY, duration: fallDuration)
        let landed = SKAction.run { [weak self, weak node] in
            MainActor.assumeIsolated {
                guard let self, let node else { return }
                self.land(node)
            }
        }
        node.run(.sequence([fall, landed]), withKey: "fall")

        if kind.hasIntro && !GameState.hasSeenIntro(kind) {
            showIntro(kind)
        }
    }

    /// 傘のてっぺんを支点に、振り子のように揺れながら降りる
    private func startSway(_ node: ItemNode) {
        let relaxed = mode == .relaxed
        let dx: CGFloat = relaxed ? 24 : 14
        let angle: CGFloat = relaxed ? 0.2 : 0.12
        let duration: TimeInterval = relaxed ? 1.2 : 0.7
        let right = SKAction.group([.moveBy(x: dx, y: 0, duration: duration), .rotate(toAngle: -angle, duration: duration)])
        let left = SKAction.group([.moveBy(x: -dx, y: 0, duration: duration), .rotate(toAngle: angle, duration: duration)])
        right.timingMode = .easeInEaseOut
        left.timingMode = .easeInEaseOut
        node.run(.repeatForever(.sequence([right, left])), withKey: "sway")
    }

    // MARK: - 初登場のお知らせ

    private func showIntro(_ kind: ItemKind) {
        GameState.markIntroSeen(kind)
        state.introKind = kind
        state.status = .intro
        isPaused = true
    }

    func resumeFromIntro() {
        state.introKind = nil
        state.status = .playing
        isPaused = false
        lastUpdate = nil
    }

    // MARK: - ひと休み（アプリが裏に回ったとき）

    /// App Switcher・コントロールセンター・電話などでアプリが裏に回ったとき。すぐに止めて盤面を隠し、「続ける」を待つ。
    /// 止めているあいだに盤面を見て考えられないよう、再開のカウントダウンが終わるまで隠したままにする
    func suspend() {
        guard state.status == .playing || state.status == .countdown else { return }
        countdownTask?.cancel()
        state.status = .suspended
        state.hidesBoard = true
        isPaused = true
    }

    /// ひと休みの画面で「続ける」を押したとき
    func resumeFromSuspension() {
        guard state.status == .suspended else { return }
        resumeWithCountdown()
    }

    // MARK: - タップ

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard state.status == .playing else { return }
        for touch in touches {
            // りんごの広告の確認などで止めたら、同時に触れたほかの指は無視する
            guard state.status == .playing else { return }
            let point = touch.location(in: self)
            let hits = children
                .compactMap { $0 as? ItemNode }
                .filter { !$0.isResolved && $0.frame.insetBy(dx: -10, dy: -10).contains(point) }
            if let node = hits.min(by: { distance($0, point) < distance($1, point) }) {
                handleTap(node)
            }
        }
    }

    private func distance(_ node: ItemNode, _ point: CGPoint) -> CGFloat {
        hypot(node.frame.midX - point.x, node.frame.midY - point.y)
    }

    private func handleTap(_ node: ItemNode) {
        node.isResolved = true
        node.removeAction(forKey: "fall")
        node.removeAction(forKey: "sway")
        let at = CGPoint(x: node.frame.midX, y: node.frame.maxY)

        switch node.kind {
        case .piglet, .golden: tapPiglet(node, at: at)
        case .wolf, .disguise: tapWolf(node, at: at)
        case .brick: tapBrick(node, at: at)
        case .apple: tapApple(node, at: at)
        }
    }
}

// MARK: - タップしたときの反応

private extension GameScene {
    func tapPiglet(_ node: ItemNode, at: CGPoint) {
        SoundPlayer.shared.play(node.kind == .golden ? .tapGolden : .tapPiglet)
        let points = node.kind == .golden ? 10 : 1
        state.addScore(points)
        state.tappedCount[node.kind, default: 0] += 1
        state.combo += 1
        node.texture = SKTexture(imageNamed: node.kind.textureName(.tapped))
        popup(L10n.points(points), at: at, color: .systemPink)
        popup(L10n.oink, at: CGPoint(x: at.x, y: at.y + 26), size: 16)
        if state.combo.isMultiple(of: Tuning.comboStep) {
            state.addScore(Tuning.comboBonus)
            state.comboCount += 1
            SoundPlayer.shared.play(.combo)
            popup(
                "\(L10n.combo) \(L10n.points(Tuning.comboBonus))",
                at: CGPoint(x: size.width / 2, y: size.height * 0.6),
                size: 26,
                color: .systemOrange
            )
        }
        vanishAfterReaction(node)
    }

    func tapWolf(_ node: ItemNode, at: CGPoint) {
        if state.shieldRemaining > 0 {
            Haptics.wolfBlocked()
            SoundPlayer.shared.play(.wolfBlocked)
            popup(L10n.safe, at: at, color: .brown)
            node.run(.sequence([.fadeOut(withDuration: 0.25), .removeFromParent()]))
            return
        }
        Haptics.wolf()
        SoundPlayer.shared.play(.wolf)
        state.combo = 0
        state.missCount += 1
        node.texture = SKTexture(imageNamed: node.kind.textureName(.tapped))
        popup(node.kind == .wolf ? L10n.grr : L10n.busted, at: at, color: .systemRed)
        if mode != .relaxed {
            loseApple()
        } else {
            state.addScore(-Tuning.relaxedWolfPenalty)
            popup(L10n.points(-Tuning.relaxedWolfPenalty), at: CGPoint(x: at.x, y: at.y + 26), size: 16, color: .systemRed)
        }
        vanishAfterReaction(node)
    }

    func tapBrick(_ node: ItemNode, at: CGPoint) {
        Haptics.brick()
        SoundPlayer.shared.play(.brick)
        state.shieldRemaining = Tuning.shieldDuration
        popup(L10n.shieldOn, at: at, color: .brown)
        node.run(.sequence([.scale(to: 1.2, duration: 0.1), .fadeOut(withDuration: 0.2), .removeFromParent()]))
    }

    func tapApple(_ node: ItemNode, at: CGPoint) {
        if let apples = state.apples {
            if apples >= mode.maxApples {
                popup(L10n.applesFull, at: at, color: .systemRed)
            } else if needsAdForApple {
                // 広告を見て取るか選ぶあいだ、止めておく
                node.run(.sequence([.fadeOut(withDuration: 0.2), .removeFromParent()]))
                state.status = .appleOffer
                isPaused = true
                return
            } else {
                SoundPlayer.shared.play(.appleGet)
                state.apples = apples + 1
                state.applesGained += 1
                popup(L10n.appleUp, at: at, color: .systemRed)
            }
        } else {
            SoundPlayer.shared.play(.appleGet)
            state.addScore(Tuning.relaxedApplePoints)
            state.appleCount += 1
            popup(L10n.points(Tuning.relaxedApplePoints), at: at, color: .systemRed)
        }
        node.run(.sequence([.scale(to: 1.2, duration: 0.1), .fadeOut(withDuration: 0.2), .removeFromParent()]))
    }

    /// 反応の顔を少し見せてから消す
    func vanishAfterReaction(_ node: ItemNode) {
        node.run(.sequence([
            .scale(to: 1.12, duration: 0.08), .scale(to: 1.0, duration: 0.08),
            .wait(forDuration: 0.3),
            .fadeOut(withDuration: 0.2), .removeFromParent()
        ]))
    }
}

// MARK: - 着地（着いた瞬間に結果を確定し、以降はタップできない）

private extension GameScene {
    func land(_ node: ItemNode) {
        guard !node.isResolved else { return }
        node.isResolved = true
        node.removeAction(forKey: "sway")

        switch node.kind {
        case .piglet, .golden:
            state.combo = 0
            if mode != .relaxed { loseApple() }
            animalLanding(node, reaction: L10n.ouch)
        case .wolf:
            animalLanding(node, reaction: L10n.ouch)
        case .disguise:
            state.addScore(Tuning.disguiseBonus)
            state.spottedCount += 1
            SoundPlayer.shared.play(.spotted)
            popup(
                "\(L10n.spotted) \(L10n.points(Tuning.disguiseBonus))",
                at: CGPoint(x: node.frame.midX, y: groundY + node.size.height * 1.1),
                color: .systemGreen
            )
            animalLanding(node, reaction: L10n.uhOh)
        case .brick:
            brickLanding(node)
        case .apple:
            appleLanding(node)
        }
    }
}

// MARK: - りんごと終了

extension GameScene {
    private func loseApple() {
        guard let apples = state.apples else { return }
        Haptics.appleLost()
        SoundPlayer.shared.play(.appleLost)
        state.apples = max(apples - 1, 0)
        if apples - 1 <= 0 { outOfApples() }
    }

    private var needsAdForApple: Bool {
        mode.needsAdForApple(
            applesGained: state.applesGained,
            adsRemoved: Monetization.adsRemoved
        )
    }

    private func outOfApples() {
        if mode.canContinue && !state.continueUsed {
            state.status = .askContinue
            isPaused = true
        } else {
            endGame()
        }
    }

    /// 続ける画面で「続ける」を選んだとき（広告を最後まで見たあとに呼ぶ）。カウントダウンしてから再開する
    func continueGame() {
        state.continueUsed = true
        state.apples = 1
        resumeWithCountdown()
    }

    /// ちゃれんじで、広告を見てりんごを取るか選んだあと。最後まで見たら rewarded が true。
    /// 見送ったときも、止めていたのでカウントダウンしてから再開する
    func finishAppleOffer(rewarded: Bool) {
        if rewarded, let apples = state.apples {
            SoundPlayer.shared.play(.appleGet)
            state.apples = min(apples + 1, mode.maxApples)
            state.applesGained += 1
        }
        resumeWithCountdown()
    }

    /// 3, 2, 1 と数えてから再開する（止めたまま数え、0 になったら盤面を出して動かす）
    private func resumeWithCountdown() {
        state.status = .countdown
        isPaused = true
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            for number in stride(from: Tuning.countdownFrom, through: 1, by: -1) {
                self?.state.countdown = number
                SoundPlayer.shared.play(.button)
                try? await Task.sleep(for: .seconds(Tuning.countdownStep))
                if Task.isCancelled { return }
            }
            guard let self, self.state.status == .countdown else { return }
            SoundPlayer.shared.play(.start)
            self.state.status = .playing
            self.state.hidesBoard = false
            self.isPaused = false
            self.lastUpdate = nil
        }
    }

    /// のんびりの「おしまい」、時間切れ、続けない場合
    func endGame() {
        guard state.status != .finished else { return }
        state.status = .finished
        state.finalizeBest()
        isPaused = true
    }
}
