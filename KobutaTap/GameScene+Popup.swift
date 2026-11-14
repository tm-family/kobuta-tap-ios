import SpriteKit
import UIKit

/// 文字の演出（点数やセリフを浮かせて消す）
extension GameScene {
    static let popupInk = UIColor(red: 0.24, green: 0.17, blue: 0.2, alpha: 1)

    @discardableResult
    func popup(_ text: String, at point: CGPoint, size fontSize: CGFloat = 22, color: UIColor = GameScene.popupInk) -> SKLabelNode {
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
        return label
    }
}
