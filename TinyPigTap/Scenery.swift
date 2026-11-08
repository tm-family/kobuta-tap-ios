import SpriteKit
import UIKit

/// 季節（のんびりモードの地面の飾り）
enum Season: String, CaseIterable {
    case spring, summer, autumn, winter

    static func current(_ date: Date = .now) -> Season {
        switch Calendar.current.component(.month, from: date) {
        case 3...5: .spring
        case 6...8: .summer
        case 9...11: .autumn
        default: .winter
        }
    }
}

extension Phase {
    /// のんびりモード：端末の時刻で空を決める
    static func forClock(_ date: Date = .now) -> Phase {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<16: .day
        case 16..<19: .evening
        default: .night
        }
    }

    var groundTexture: String {
        switch self {
        case .day: "ground_day"
        case .evening: "ground_evening"
        case .night: "ground_night"
        }
    }
}

/// 背景の組み合わせ。season が nil のときは季節の飾りなし（チャレンジ）
struct Scenery: Equatable {
    var phase: Phase
    var season: Season?

    static func challenge(_ phase: Phase) -> Scenery { Scenery(phase: phase, season: nil) }
    static func now() -> Scenery { Scenery(phase: .forClock(), season: .current()) }

    /// 空のグラデーション（上から下）
    var skyColors: [UIColor] {
        switch phase {
        case .evening: return [UIColor(hex: 0xE4849C), UIColor(hex: 0xF6AE7C), UIColor(hex: 0xFDE3B4)]
        case .night: return [UIColor(hex: 0x1C2850), UIColor(hex: 0x4A5E92)]
        case .day:
            switch season {
            case .spring: return [UIColor(hex: 0xA6DCF4), UIColor(hex: 0xF3FAFD)]
            case .summer: return [UIColor(hex: 0x4FB2EE), UIColor(hex: 0xCDEFFC)]
            case .autumn: return [UIColor(hex: 0x8FCBEA), UIColor(hex: 0xF4EEDC)]
            case .winter: return [UIColor(hex: 0xA9CDE8), UIColor(hex: 0xEEF5FB)]
            case nil: return [UIColor(hex: 0x7CC6F2), UIColor(hex: 0xDDF2FC)]
            }
        }
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// 空・地面・季節の飾り・舞うものを重ねた背景。
/// 絵は 624 の高さを基準に描いてあり、遊ぶ範囲（中央）の外側にも広がっているので、iPadでは左右まで見える。
@MainActor
final class BackgroundNode: SKNode {
    private(set) var scenery: Scenery
    private var current: SKNode?

    init(scenery: Scenery) {
        self.scenery = scenery
        super.init()
        zPosition = -100
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func layout(size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        current?.removeFromParent()
        let layer = makeLayer(scenery, size: size)
        addChild(layer)
        current = layer
    }

    /// 数秒かけて切り替える
    func transition(to newScenery: Scenery, size: CGSize) {
        scenery = newScenery
        let old = current
        let layer = makeLayer(newScenery, size: size)
        layer.alpha = 0
        layer.zPosition = 1
        addChild(layer)
        current = layer
        layer.run(.fadeIn(withDuration: 2.0))
        old?.run(.sequence([.wait(forDuration: 2.0), .removeFromParent()]))
    }

    private func makeLayer(_ s: Scenery, size: CGSize) -> SKNode {
        let root = SKNode()
        let u = size.height / 624          // 絵の1単位あたりのポイント
        let cx = size.width / 2            // 遊ぶ範囲の中心

        // 空
        let sky = SKSpriteNode(texture: Self.gradientTexture(s.skyColors), size: size)
        sky.anchorPoint = .zero
        sky.zPosition = 0
        root.addChild(sky)

        func sprite(_ name: String, x: CGFloat, y: CGFloat, width: CGFloat, z: CGFloat) -> SKSpriteNode {
            let node = SKSpriteNode(imageNamed: name)
            let ratio = node.size.height / max(node.size.width, 1)
            node.size = CGSize(width: width, height: width * ratio)
            node.position = CGPoint(x: x, y: y)
            node.zPosition = z
            root.addChild(node)
            return node
        }

        // 空のもの（y は画面の下からの距離）
        switch s.phase {
        case .day:
            _ = sprite("sky_sun_day", x: cx + 92 * u, y: size.height - 140 * u, width: 80 * u, z: 1)
            _ = sprite("sky_cloud", x: cx - 90 * u, y: size.height - 180 * u, width: 100 * u, z: 2)
            _ = sprite("sky_cloud", x: cx + 80 * u, y: size.height - 300 * u, width: 84 * u, z: 2)
            _ = sprite("sky_cloud", x: cx - 230 * u, y: size.height - 320 * u, width: 90 * u, z: 2)
            _ = sprite("sky_cloud", x: cx + 240 * u, y: size.height - 210 * u, width: 90 * u, z: 2)
            if s.season == .summer {
                _ = sprite("sky_cumulus", x: cx + 80 * u, y: 230 * u, width: 160 * u, z: 2)
            }
        case .evening:
            _ = sprite("sky_sun_evening", x: cx, y: 138 * u, width: 128 * u, z: 1)
            _ = sprite("sky_cloud_evening", x: cx - 80 * u, y: size.height - 210 * u, width: 100 * u, z: 2)
            _ = sprite("sky_cloud_evening", x: cx + 200 * u, y: size.height - 290 * u, width: 90 * u, z: 2)
        case .night:
            _ = sprite("sky_moon", x: cx + 90 * u, y: size.height - 110 * u, width: 52 * u, z: 1)
            for _ in 0..<24 {
                let star = SKShapeNode(circleOfRadius: .random(in: 1.0...2.2) * u)
                star.fillColor = .white
                star.strokeColor = .clear
                star.position = CGPoint(x: .random(in: 0...size.width), y: .random(in: (size.height * 0.4)...size.height))
                star.zPosition = 1
                root.addChild(star)
            }
        }

        // 地面（横長の帯。画面より狭いときは横に引き伸ばす）
        let groundWidth = max(640 * u, size.width)
        let ground = SKSpriteNode(imageNamed: s.phase.groundTexture)
        ground.anchorPoint = CGPoint(x: 0.5, y: 0)
        ground.size = CGSize(width: groundWidth, height: 204 * u)
        ground.position = CGPoint(x: cx, y: 0)
        ground.zPosition = 10
        root.addChild(ground)

        // 季節の飾り（夜と夕方は少し暗くする）
        if let season = s.season {
            let deco = SKSpriteNode(imageNamed: "deco_\(season.rawValue)")
            deco.anchorPoint = CGPoint(x: 0.5, y: 0)
            deco.size = ground.size
            deco.position = ground.position
            deco.zPosition = 11
            deco.color = .black
            deco.colorBlendFactor = s.phase == .night ? 0.35 : (s.phase == .evening ? 0.12 : 0)
            root.addChild(deco)

            if let emitter = Self.particles(for: season, size: size, unit: u) {
                emitter.zPosition = 12
                root.addChild(emitter)
            }
        }
        return root
    }

    private static func particles(for season: Season, size: CGSize, unit u: CGFloat) -> SKEmitterNode? {
        let name: String
        switch season {
        case .spring: name = "particle_petal"
        case .autumn: name = "particle_leaf"
        case .winter: name = "particle_snow"
        case .summer: return nil
        }
        let e = SKEmitterNode()
        e.particleTexture = SKTexture(imageNamed: name)
        e.particleBirthRate = season == .winter ? 4 : 1.2
        e.particleLifetime = 14
        e.position = CGPoint(x: size.width / 2, y: size.height + 10)
        e.particlePositionRange = CGVector(dx: size.width, dy: 0)
        e.emissionAngle = -.pi / 2
        e.emissionAngleRange = 0.4
        e.particleSpeed = 40 * u
        e.particleSpeedRange = 20 * u
        e.xAcceleration = 4
        e.particleRotationRange = .pi * 2
        e.particleRotationSpeed = season == .winter ? 0 : 1.2
        e.particleScale = u * 0.9
        e.particleScaleRange = u * 0.4
        e.particleAlpha = 0.9
        e.advanceSimulationTime(10)
        return e
    }

    /// 縦のグラデーションを小さなテクスチャにして引き伸ばす
    private static func gradientTexture(_ colors: [UIColor]) -> SKTexture {
        let size = CGSize(width: 4, height: 256)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            let cgColors = colors.map(\.cgColor) as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColors, locations: nil)!
            ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }
}
