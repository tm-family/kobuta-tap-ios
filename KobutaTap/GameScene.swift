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

    init(size: CGSize, mode: GameMode, state: GameState) {
        self.mode = mode
        self.state = state
        let scenery: Scenery = mode == .challenge ? .challenge(.day) : .now()
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
    private var groundY: CGFloat { size.height * Tuning.groundRatio }
    private var baseWidth: CGFloat { playRect.width * Tuning.itemWidthRatio }

    // MARK: - 難易度

    private var progress: Double { min(elapsed / Tuning.challengeDuration, 1) }

    private var fallDuration: TimeInterval {
        guard mode == .challenge else { return Tuning.relaxedFallDuration }
        let range = Tuning.challengeFallDuration
        return range.upperBound - (range.upperBound - range.lowerBound) * progress
    }

    private var spawnInterval: TimeInterval {
        guard mode == .challenge else { return Tuning.relaxedSpawnInterval }
        let range = Tuning.challengeSpawnInterval
        return range.upperBound - (range.upperBound - range.lowerBound) * progress
    }

    // MARK: - ループ

    override func update(_ currentTime: TimeInterval) {
        defer { lastUpdate = currentTime }
        guard state.status == .playing else { return }
        let delta = min(lastUpdate.map { currentTime - $0 } ?? 0, 0.1)

        elapsed += delta
        spawnTimer += delta

        if mode == .challenge {
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
        let hard = mode == .challenge && state.phase == .night
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

    // MARK: - タップ

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard state.status == .playing else { return }
        for touch in touches {
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
            popup(L10n.safe, at: at, color: .brown)
            node.run(.sequence([.fadeOut(withDuration: 0.25), .removeFromParent()]))
            return
        }
        Haptics.wolf()
        state.combo = 0
        state.missCount += 1
        node.texture = SKTexture(imageNamed: node.kind.textureName(.tapped))
        popup(node.kind == .wolf ? L10n.grr : L10n.busted, at: at, color: .systemRed)
        if mode == .challenge {
            loseApple()
        } else {
            state.addScore(-Tuning.relaxedWolfPenalty)
            popup(L10n.points(-Tuning.relaxedWolfPenalty), at: CGPoint(x: at.x, y: at.y + 26), size: 16, color: .systemRed)
        }
        vanishAfterReaction(node)
    }

    func tapBrick(_ node: ItemNode, at: CGPoint) {
        Haptics.brick()
        state.shieldRemaining = Tuning.shieldDuration
        popup(L10n.shieldOn, at: at, color: .brown)
        node.run(.sequence([.scale(to: 1.2, duration: 0.1), .fadeOut(withDuration: 0.2), .removeFromParent()]))
    }

    func tapApple(_ node: ItemNode, at: CGPoint) {
        if let apples = state.apples {
            state.apples = min(apples + 1, Tuning.maxApples)
            popup(L10n.appleUp, at: at, color: .systemRed)
        } else {
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
            if mode == .challenge { loseApple() }
            animalLanding(node, reaction: L10n.ouch)
        case .wolf:
            animalLanding(node, reaction: L10n.ouch)
        case .disguise:
            state.addScore(Tuning.disguiseBonus)
            state.spottedCount += 1
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

    /// ぽてっ → 尻もち → 傘を拾って走って逃げる
    func animalLanding(_ node: ItemNode, reaction: String) {
        let kind = node.kind
        // 足もと基準に切り替える
        let x = node.frame.midX
        node.zRotation = 0
        node.anchorPoint = CGPoint(x: 0.5, y: 0.03)
        node.position = CGPoint(x: x, y: groundY)

        let dir: CGFloat = x < size.width / 2 ? -1 : 1   // 近い方の端へ逃げる
        let umbrella = SKSpriteNode(imageNamed: kind.umbrellaTexture)
        umbrella.size = CGSize(width: node.size.width * 0.62, height: node.size.width * 0.62 * 120 / 140)
        umbrella.position = CGPoint(x: x - dir * node.size.width * 0.6, y: groundY + umbrella.size.width * 0.25)
        umbrella.zRotation = dir * 1.75
        umbrella.zPosition = 9

        let width = node.size.width
        popup(L10n.plop, at: CGPoint(x: x, y: groundY + width * 1.2), size: 16)

        node.run(.sequence([
            .scaleX(to: 1.12, y: 0.86, duration: 0.07),
            .scale(to: 1.0, duration: 0.08),
            .setTexture(SKTexture(imageNamed: kind.textureName(.sit))),
            .run { [weak self, weak umbrella] in
                MainActor.assumeIsolated {
                    guard let self, let umbrella else { return }
                    self.addChild(umbrella)
                    self.popup(reaction, at: CGPoint(x: x, y: self.groundY + width * 1.35))
                }
            },
            .wait(forDuration: 0.75),
            .run { [weak umbrella] in
                MainActor.assumeIsolated { umbrella?.removeFromParent() }
            },
            .setTexture(SKTexture(imageNamed: kind.textureName(.run))),
            .scaleX(to: dir, y: 1, duration: 0),   // 走る絵は右向き。左へ逃げるときは反転
            .moveBy(x: dir * size.width * 0.75, y: 0, duration: 0.9),
            .removeFromParent()
        ]))
    }

    /// ごとっ → 草にうもれて消える
    func brickLanding(_ node: ItemNode) {
        popup(L10n.thud, at: CGPoint(x: node.position.x, y: node.position.y + node.size.height))
        node.run(.sequence([
            .scaleX(to: 1.1, y: 0.85, duration: 0.06), .scale(to: 1.0, duration: 0.08),
            .wait(forDuration: 0.4),
            .group([.moveBy(x: 0, y: -node.size.height * 0.6, duration: 0.6), .fadeOut(withDuration: 0.6)]),
            .removeFromParent()
        ]))
    }

    /// ぽんとはねて、ころころ画面の外へ
    func appleLanding(_ node: ItemNode) {
        let dir: CGFloat = node.position.x < size.width / 2 ? -1 : 1
        let up = SKAction.moveBy(x: 0, y: node.size.height * 0.6, duration: 0.18)
        up.timingMode = .easeOut
        let down = up.reversed()
        down.timingMode = .easeIn
        popup(L10n.rolling, at: CGPoint(x: node.position.x, y: node.position.y + node.size.height * 1.2))
        node.run(.sequence([
            up, down,
            .group([
                .moveBy(x: dir * size.width * 0.7, y: 0, duration: 1.1),
                .rotate(byAngle: -dir * .pi * 4, duration: 1.1)
            ]),
            .removeFromParent()
        ]))
    }
}

// MARK: - りんごと終了

extension GameScene {
    private func loseApple() {
        guard let apples = state.apples else { return }
        Haptics.appleLost()
        state.apples = max(apples - 1, 0)
        if apples - 1 <= 0 { outOfApples() }
    }

    private func outOfApples() {
        if state.continueUsed {
            endGame()
        } else {
            state.status = .askContinue
            isPaused = true
        }
    }

    /// 続ける画面で「続ける」を選んだとき（広告の再生後に呼ぶ）
    func continueGame() {
        state.continueUsed = true
        state.apples = 1
        state.status = .playing
        isPaused = false
        lastUpdate = nil
    }

    /// のんびりの「おしまい」、時間切れ、続けない場合
    func endGame() {
        guard state.status != .finished else { return }
        state.status = .finished
        state.finalizeBest()
        isPaused = true
    }
}

// MARK: - 文字の演出

private extension GameScene {
    static let popupInk = UIColor(red: 0.24, green: 0.17, blue: 0.2, alpha: 1)

    func popup(_ text: String, at point: CGPoint, size fontSize: CGFloat = 22, color: UIColor = GameScene.popupInk) {
        let label = SKLabelNode()
        label.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: AppFont.uiFont(fontSize),
                .foregroundColor: color,
                .strokeColor: UIColor.white,
                .strokeWidth: -5
            ]
        )
        label.position = point
        label.zPosition = 50
        addChild(label)
        label.run(.sequence([
            .group([.moveBy(x: 0, y: 40, duration: 0.7), .sequence([.wait(forDuration: 0.4), .fadeOut(withDuration: 0.3)])]),
            .removeFromParent()
        ]))
    }
}
