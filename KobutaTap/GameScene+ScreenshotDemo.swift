import SpriteKit

/// 撮影モード（ScreenshotDemo）の盤面を並べる
extension GameScene {
    /// 盤面があれば、いまの画面の大きさで並べ直して止める。ふだんのプレイでは何もしない
    func layoutBoard() {
        guard let board, size.width > 0, size.height > 0 else { return }
        boardNodes.forEach { $0.removeFromParent() }
        boardNodes = []
        background.updateSkyBodies(elapsed: board.elapsed)

        let rect = playRect
        let hard = mode != .relaxed && board.scenery.phase == .night
        for item in board.items {
            let texture = item.kind.textureName(item.tapped ? .tapped : .normal, hard: hard, skin: umbrellaSkin)
            let node = ItemNode(kind: item.kind, textureName: texture, width: baseWidth)
            node.position = CGPoint(x: rect.minX + rect.width * item.x, y: size.height * item.y)
            node.zRotation = item.angle
            node.isResolved = true
            addChild(node)
            boardNodes.append(node)
        }
        for item in board.popups {
            let label = popup(
                item.text,
                at: CGPoint(x: rect.minX + rect.width * item.x, y: size.height * item.y),
                size: item.size,
                color: item.color
            )
            // 浮かせて消す動きを止め、出した瞬間のまま残す
            label.removeAllActions()
            boardNodes.append(label)
        }
        isPaused = true
    }
}
