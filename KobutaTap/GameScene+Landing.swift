import SpriteKit

/// 着地したときの動き（こぶた・おおかみは尻もちをついて逃げる、レンガはうもれる、りんごは転がる）
extension GameScene {
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
