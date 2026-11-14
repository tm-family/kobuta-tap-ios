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
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

/// 60 秒のモードとちゃれんじの、太陽と月の位置。経過時間だけで決める（止めているあいだは動かない）。
/// 日中は太陽を動かさず、夕方になる少し前から右上の太陽が弧を描いて地平線へ沈み、夕日に替わる。
/// 夜になる少し前に夕日が地平線の下へ沈み、夜になったら右の丘の向こうから月が昇る。
/// 位置は絵の単位（画面の高さが 624）で、x は遊ぶ範囲の中心から、y は画面の下から
struct SkyBodies: Equatable {
    var sun: CGPoint
    var sunWidth: CGFloat
    /// 0 は昼の太陽の絵、1 は夕日の絵（あいだは 2 枚を重ねて移り変わる）
    var sunset: CGFloat
    /// 夕日が地平線の下に沈みきったら false
    var showsSun: Bool
    /// nil のときは月を出さない
    var moon: CGPoint?

    static let daySun = CGPoint(x: 92, y: 484)
    static let daySunWidth: CGFloat = 80
    /// 夕日は半分ほど丘に隠れる高さ
    static let eveningSun = CGPoint(x: 0, y: 138)
    static let eveningSunWidth: CGFloat = 128
    /// 地平線の下（夕日の光の輪まで丘に隠れる高さ）
    static let setSun = CGPoint(x: 0, y: 50)
    /// 右の丘に隠れた位置から、右上まで昇る
    static let moonStart = CGPoint(x: 120, y: 100)
    static let moonEnd = CGPoint(x: 90, y: 514)
    static let moonWidth: CGFloat = 52

    static func at(elapsed: TimeInterval) -> SkyBodies {
        let sunset = progress(elapsed, from: Tuning.eveningStarts - Tuning.sunsetLead, duration: Tuning.sunsetDuration)
        let dusk = progress(elapsed, from: Tuning.nightStarts - Tuning.duskLead, duration: Tuning.duskLead)
        // 横は先に、縦はあとから大きく動かし、弧を描いて沈む
        let sunsetY = lerp(daySun.y, eveningSun.y, easeIn(sunset))
        let sun = CGPoint(
            x: lerp(daySun.x, eveningSun.x, easeOut(sunset)),
            y: lerp(sunsetY, setSun.y, easeIn(dusk))
        )
        var moon: CGPoint?
        if elapsed >= Tuning.nightStarts {
            let rise = progress(elapsed, from: Tuning.nightStarts, duration: Tuning.moonriseDuration)
            moon = CGPoint(x: lerp(moonStart.x, moonEnd.x, rise), y: lerp(moonStart.y, moonEnd.y, easeOut(rise)))
        }
        return SkyBodies(
            sun: sun,
            sunWidth: lerp(daySunWidth, eveningSunWidth, smooth(sunset)),
            sunset: smooth(sunset),
            showsSun: dusk < 1,
            moon: moon
        )
    }

    private static func progress(_ elapsed: TimeInterval, from start: TimeInterval, duration: TimeInterval) -> CGFloat {
        CGFloat(min(max((elapsed - start) / duration, 0), 1))
    }

    private static func lerp(_ from: CGFloat, _ to: CGFloat, _ amount: CGFloat) -> CGFloat {
        from + (to - from) * amount
    }

    private static func easeIn(_ value: CGFloat) -> CGFloat { value * value }
    private static func easeOut(_ value: CGFloat) -> CGFloat { 1 - (1 - value) * (1 - value) }
    private static func smooth(_ value: CGFloat) -> CGFloat { value * value * (3 - 2 * value) }
}

/// 空・地面・季節の飾り・舞うものを重ねた背景。
/// 絵は 624 の高さを基準に描いてあり、遊ぶ範囲（中央）の外側にも広がっているので、iPadでは左右まで見える。
@MainActor
final class BackgroundNode: SKNode {
    private(set) var scenery: Scenery
    private var current: SKNode?
    /// 太陽と月を経過時間で動かすか（60 秒のモードとちゃれんじ）。のんびりは空の絵の一部として描き、動かさない
    private let movesSkyBodies: Bool
    private var skyBodyNodes: SkyBodyNodes?
    private var lastSize: CGSize = .zero
    private var lastElapsed: TimeInterval = 0

    init(scenery: Scenery) {
        self.scenery = scenery
        movesSkyBodies = scenery.season == nil
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
        lastSize = size
        if movesSkyBodies {
            makeSkyBodies()
            updateSkyBodies(elapsed: lastElapsed)
        }
    }

    /// 毎フレーム、経過時間に合わせて太陽と月を動かす（60 秒のモードとちゃれんじ）
    func updateSkyBodies(elapsed: TimeInterval) {
        lastElapsed = elapsed
        guard let nodes = skyBodyNodes, lastSize.height > 0 else { return }
        let unit = lastSize.height / 624
        let centerX = lastSize.width / 2
        let bodies = SkyBodies.at(elapsed: elapsed)
        let sunPosition = CGPoint(x: centerX + bodies.sun.x * unit, y: bodies.sun.y * unit)
        let sunSize = CGSize(width: bodies.sunWidth * unit, height: bodies.sunWidth * unit)
        for (node, alpha) in [(nodes.daySun, 1 - bodies.sunset), (nodes.eveningSun, bodies.sunset)] {
            node.position = sunPosition
            node.size = sunSize
            node.alpha = alpha
            node.isHidden = !bodies.showsSun
        }
        if let moon = bodies.moon {
            nodes.moon.isHidden = false
            nodes.moon.position = CGPoint(x: centerX + moon.x * unit, y: moon.y * unit)
        } else {
            nodes.moon.isHidden = true
        }
    }

    /// 動かす太陽と月。空（0・1）より手前、雲（2・3）と地面（10・11）より奥に置き、夕日と昇る月は丘に隠れる
    private func makeSkyBodies() {
        skyBodyNodes?.all.forEach { $0.removeFromParent() }
        let unit = lastSize.height / 624
        let nodes = SkyBodyNodes()
        nodes.moon.size = CGSize(width: SkyBodies.moonWidth * unit, height: SkyBodies.moonWidth * unit)
        for node in nodes.all {
            node.zPosition = 1.6
            addChild(node)
        }
        skyBodyNodes = nodes
    }

    /// 動かす太陽（昼の絵と夕日の絵を重ねて移り変わる）と月
    private struct SkyBodyNodes {
        let daySun = SKSpriteNode(imageNamed: "sky_sun_day")
        let eveningSun = SKSpriteNode(imageNamed: "sky_sun_evening")
        let moon = SKSpriteNode(imageNamed: "sky_moon")
        var all: [SKSpriteNode] { [daySun, eveningSun, moon] }
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

    private func makeLayer(_ scenery: Scenery, size: CGSize) -> SKNode {
        let root = SKNode()
        let canvas = Canvas(root: root, size: size)

        // 空
        let sky = SKSpriteNode(texture: Self.gradientTexture(scenery.skyColors), size: size)
        sky.anchorPoint = .zero
        sky.zPosition = 0
        root.addChild(sky)

        addSkyObjects(scenery, to: canvas)
        let ground = addGround(scenery, to: canvas)
        if let season = scenery.season {
            addSeasonDecoration(season, phase: scenery.phase, ground: ground, to: canvas)
        }
        return root
    }

    /// 重ねて描く先。unit は絵の1単位あたりのポイント、centerX は遊ぶ範囲の中心
    private struct Canvas {
        let root: SKNode
        let size: CGSize
        var unit: CGFloat { size.height / 624 }
        var centerX: CGFloat { size.width / 2 }

        @discardableResult
        func sprite(_ name: String, x: CGFloat, y: CGFloat, width: CGFloat, zPosition: CGFloat) -> SKSpriteNode {
            let node = SKSpriteNode(imageNamed: name)
            let ratio = node.size.height / max(node.size.width, 1)
            node.size = CGSize(width: width, height: width * ratio)
            node.position = CGPoint(x: x, y: y)
            node.zPosition = zPosition
            root.addChild(node)
            return node
        }
    }

    /// 空のもの（y は画面の下からの距離）
    private func addSkyObjects(_ scenery: Scenery, to canvas: Canvas) {
        let unit = canvas.unit
        let centerX = canvas.centerX
        let height = canvas.size.height
        // 60 秒のモードとちゃれんじでは、太陽と月は updateSkyBodies で動かすので、ここでは描かない
        let drawsSkyBodies = !movesSkyBodies
        switch scenery.phase {
        case .day:
            if drawsSkyBodies {
                canvas.sprite("sky_sun_day", x: centerX + 92 * unit, y: height - 140 * unit, width: 80 * unit, zPosition: 1)
            }
            canvas.sprite("sky_cloud", x: centerX - 90 * unit, y: height - 180 * unit, width: 100 * unit, zPosition: 2)
            canvas.sprite("sky_cloud", x: centerX + 80 * unit, y: height - 300 * unit, width: 84 * unit, zPosition: 2)
            canvas.sprite("sky_cloud", x: centerX - 230 * unit, y: height - 320 * unit, width: 90 * unit, zPosition: 2)
            canvas.sprite("sky_cloud", x: centerX + 240 * unit, y: height - 210 * unit, width: 90 * unit, zPosition: 2)
            if scenery.season == .summer {
                canvas.sprite("sky_cumulus", x: centerX + 80 * unit, y: 230 * unit, width: 160 * unit, zPosition: 2)
            }
        case .evening:
            if drawsSkyBodies {
                canvas.sprite("sky_sun_evening", x: centerX, y: 138 * unit, width: 128 * unit, zPosition: 1)
            }
            canvas.sprite("sky_cloud_evening", x: centerX - 80 * unit, y: height - 210 * unit, width: 100 * unit, zPosition: 2)
            canvas.sprite("sky_cloud_evening", x: centerX + 200 * unit, y: height - 290 * unit, width: 90 * unit, zPosition: 2)
        case .night:
            if drawsSkyBodies {
                canvas.sprite("sky_moon", x: centerX + 90 * unit, y: height - 110 * unit, width: 52 * unit, zPosition: 1)
            }
            for _ in 0..<24 {
                let star = SKShapeNode(circleOfRadius: .random(in: 1.0...2.2) * unit)
                star.fillColor = .white
                star.strokeColor = .clear
                star.position = CGPoint(x: .random(in: 0...canvas.size.width), y: .random(in: (height * 0.4)...height))
                // 星は月より奥（昇る月が星の手前を通る）
                star.zPosition = 0.5
                canvas.root.addChild(star)
            }
        }
    }

    /// 地面（横長の帯。画面より狭いときは横に引き伸ばす）
    private func addGround(_ scenery: Scenery, to canvas: Canvas) -> SKSpriteNode {
        let unit = canvas.unit
        let ground = SKSpriteNode(imageNamed: scenery.phase.groundTexture)
        ground.anchorPoint = CGPoint(x: 0.5, y: 0)
        ground.size = CGSize(width: max(640 * unit, canvas.size.width), height: 204 * unit)
        ground.position = CGPoint(x: canvas.centerX, y: 0)
        ground.zPosition = 10
        canvas.root.addChild(ground)
        return ground
    }

    /// 季節の飾り（夜と夕方は少し暗くする）と舞うもの
    private func addSeasonDecoration(_ season: Season, phase: Phase, ground: SKSpriteNode, to canvas: Canvas) {
        let deco = SKSpriteNode(imageNamed: "deco_\(season.rawValue)")
        deco.anchorPoint = CGPoint(x: 0.5, y: 0)
        deco.size = ground.size
        deco.position = ground.position
        deco.zPosition = 11
        deco.color = .black
        deco.colorBlendFactor = phase == .night ? 0.35 : (phase == .evening ? 0.12 : 0)
        canvas.root.addChild(deco)

        if let emitter = Self.particles(for: season, size: canvas.size, unit: canvas.unit) {
            emitter.zPosition = 12
            canvas.root.addChild(emitter)
        }
    }

    private static func particles(for season: Season, size: CGSize, unit: CGFloat) -> SKEmitterNode? {
        let name: String
        switch season {
        case .spring: name = "particle_petal"
        case .autumn: name = "particle_leaf"
        case .winter: name = "particle_snow"
        case .summer: return nil
        }
        let emitter = SKEmitterNode()
        emitter.particleTexture = SKTexture(imageNamed: name)
        emitter.particleBirthRate = season == .winter ? 4 : 1.2
        emitter.particleLifetime = 14
        emitter.position = CGPoint(x: size.width / 2, y: size.height + 10)
        emitter.particlePositionRange = CGVector(dx: size.width, dy: 0)
        emitter.emissionAngle = -.pi / 2
        emitter.emissionAngleRange = 0.4
        emitter.particleSpeed = 40 * unit
        emitter.particleSpeedRange = 20 * unit
        emitter.xAcceleration = 4
        emitter.particleRotationRange = .pi * 2
        emitter.particleRotationSpeed = season == .winter ? 0 : 1.2
        emitter.particleScale = unit * 0.9
        emitter.particleScaleRange = unit * 0.4
        emitter.particleAlpha = 0.9
        emitter.advanceSimulationTime(10)
        return emitter
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
