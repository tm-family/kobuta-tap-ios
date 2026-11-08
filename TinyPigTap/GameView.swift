import SpriteKit
import SwiftUI

struct GameView: View {
    let mode: GameMode
    let onRestart: () -> Void
    let onExit: () -> Void

    @State private var state: GameState
    @State private var scene: GameScene

    init(mode: GameMode, onRestart: @escaping () -> Void, onExit: @escaping () -> Void) {
        self.mode = mode
        self.onRestart = onRestart
        self.onExit = onExit
        let state = GameState(mode: mode)
        _state = State(initialValue: state)
        _scene = State(initialValue: GameScene(size: CGSize(width: 390, height: 844), mode: mode, state: state))
    }

    var body: some View {
        GeometryReader { geo in
            // 上部の表示は、遊ぶ範囲の幅にそろえる（iPadでは中央）
            let playWidth = min(geo.size.width, (geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom) * Tuning.playAspect)
            ZStack {
                SpriteView(scene: scene).ignoresSafeArea()

                if state.shieldRemaining > 0 {
                    RoundedRectangle(cornerRadius: 44)
                        .strokeBorder(Color.kBrick, lineWidth: 10)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }

                VStack { hud; Spacer() }
                    .frame(width: playWidth)

                if let remaining = state.timeRemaining, remaining > 0, remaining <= 10, state.status == .playing {
                    OutlinedText(text: String(localized: "あと \(Int(remaining.rounded(.up)))"), size: 40, color: Color(hex: 0xE85A4F))
                        .allowsHitTesting(false)
                }

                overlay.frame(width: geo.size.width, height: geo.size.height)
            }
        }
        // プレイ中は時刻や電池の表示がキャラクターと重ならないよう、ステータスバーを隠す（メニューでは出す）
        .statusBarHidden()
    }

    @ViewBuilder private var overlay: some View {
        switch state.status {
        case .intro:
            if let kind = state.introKind {
                IntroCard(kind: kind) { scene.resumeFromIntro() }
            }
        case .askContinue:
            ContinueCard(onContinue: { scene.continueGame() }, onStop: { scene.endGame() })
        case .finished:
            ResultView(state: state, onRestart: onRestart, onExit: onExit)
        case .playing:
            EmptyView()
        }
    }

    // MARK: 上部の表示（スコアとりんご → タイムバー → レンガの残り時間）

    private var hud: some View {
        VStack(spacing: 10) {
            HStack {
                Text(String(localized: "\(state.score)点")).font(.kRounded(18).monospacedDigit()).foregroundStyle(Color.ink)
                Spacer()
                if let apples = state.apples {
                    HStack(spacing: 2) {
                        ForEach(0..<max(Tuning.startingApples, apples), id: \.self) { index in
                            Image("icon_apple")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 26, height: 26)
                                .opacity(index < apples ? 1 : 0.25)
                        }
                    }
                } else if state.status == .playing {
                    Button { scene.endGame() } label: {
                        Text("おしまい")
                            .font(.kRounded(13, .bold))
                            .foregroundStyle(Color.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Color(hex: 0xEFEDE7), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(.white.opacity(0.92), in: Capsule())

            if let remaining = state.timeRemaining {
                TimeBar(fraction: remaining / Tuning.challengeDuration, phase: state.phase)
            }

            if state.shieldRemaining > 0 {
                ShieldBadge(remaining: state.shieldRemaining)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }
}

/// 太陽（夕日・月）が乗ったタイムバー
struct TimeBar: View {
    let fraction: Double
    let phase: Phase

    var body: some View {
        GeometryReader { geo in
            let width = max(16, geo.size.width * fraction)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(phase == .night ? 0.35 : 0.7))
                Capsule().fill(barColor).frame(width: width)
                knob.offset(x: width - 11)
            }
        }
        .frame(height: 16)
        .padding(.horizontal, 8)
        .animation(.linear(duration: 0.2), value: fraction)
    }

    @ViewBuilder private var knob: some View {
        switch phase {
        case .day: Circle().fill(Color(hex: 0xFFD24D)).frame(width: 22, height: 22)
        case .evening: Circle().fill(Color(hex: 0xF6A33C)).frame(width: 22, height: 22)
        case .night: Image("sky_moon").resizable().scaledToFit().frame(width: 22, height: 22)
        }
    }

    private var barColor: Color {
        switch phase {
        case .day: Color(hex: 0x8CC97E)
        case .evening: Color(hex: 0xF2B33D)
        case .night: Color(hex: 0xE85A4F)
        }
    }
}

/// レンガで守られている残り時間（輪が5秒かけて減る）
struct ShieldBadge: View {
    let remaining: TimeInterval

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().stroke(Color(hex: 0xF3D3C4), lineWidth: 3.5)
                Circle()
                    .trim(from: 0, to: remaining / Tuning.shieldDuration)
                    .stroke(Color.kBrick, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image("icon_brick").resizable().scaledToFit().frame(width: 16)
            }
            .frame(width: 26, height: 26)
            Text(String(localized: "あと\(Int(remaining.rounded(.up)))"))
                .font(.kRounded(15))
                .foregroundStyle(Color(hex: 0xA9502F))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.white.opacity(0.95), in: Capsule())
    }
}

/// 初登場のお知らせ
struct IntroCard: View {
    let kind: ItemKind
    let onOK: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(.white.opacity(0.85)).frame(width: 190, height: 190)
                    // 横長のレンガも丸の中に収まるよう、幅と高さの両方を 150 までにする
                    Image(kind.textureName(.normal)).resizable().scaledToFit().frame(maxWidth: 150, maxHeight: 150)
                }
                .padding(.bottom, 20)
                VStack(spacing: 12) {
                    Text(L10n.introTitle(kind))
                        .font(.kRounded(18))
                        .foregroundStyle(Color.kPink)
                        .multilineTextAlignment(.center)
                    Text(L10n.introBody(kind))
                        .font(.kRounded(13, .medium))
                        .foregroundStyle(Color.ink)
                        .multilineTextAlignment(.center)
                    Button(action: onOK) {
                        Text("わかった！")
                            .font(.kRounded(15, .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 9)
                            .background(Color.kGreen, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(22)
                .frame(maxWidth: .infinity)
                .background(.white, in: .rect(cornerRadius: 24))
            }
            .padding(28)
            .frame(maxWidth: 360)
        }
    }
}

/// 続ける画面（1プレイ1回。「続ける」と「やめる」を同じくらい分かりやすく、急かさない）
struct ContinueCard: View {
    let onContinue: () -> Void
    let onStop: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 14) {
                Image("icon_apple").resizable().scaledToFit().frame(width: 56).opacity(0.35)
                Text("りんごがなくなった！").font(.kRounded(18)).foregroundStyle(Color.ink)
                Text("りんごを1つもらって、続きから遊べます")
                    .font(.kRounded(13, .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if Monetization.adsRemoved || Monetization.isRewardedAdReady {
                    PillButton(
                        title: Monetization.adsRemoved ? String(localized: "続ける") : String(localized: "広告を見て続ける"),
                        fill: .kGreen,
                        textColor: .white,
                        action: onContinue
                    )
                }
                PillButton(title: String(localized: "やめる"), fill: Color(hex: 0xEFEDE7), action: onStop)
            }
            .padding(24)
            .background(.white, in: .rect(cornerRadius: 24))
            .padding(28)
            .frame(maxWidth: 380)
        }
    }
}

/// 結果画面（合計点、自己ベスト、内訳）
struct ResultView: View {
    let state: GameState
    let onRestart: () -> Void
    let onExit: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: 12) {
                Text(state.mode == .challenge ? String(localized: "おしまい！") : String(localized: "おつかれさま！"))
                    .font(.kRounded(26))
                    .foregroundStyle(Color.ink)
                Text(String(localized: "\(state.score)点")).font(.kRounded(42)).foregroundStyle(Color.kPink)
                Text(state.isNewBest ? String(localized: "自己ベスト更新！") : String(localized: "自己ベスト \(state.bestScore)点"))
                    .font(.kRounded(14, .bold))
                    .foregroundStyle(state.isNewBest ? Color(hex: 0xE8833A) : .secondary)

                VStack(alignment: .leading, spacing: 6) {
                    row("piglet_normal", L10n.name(.piglet), state.tappedCount[.piglet, default: 0], points: 1)
                    row("golden_normal", L10n.name(.golden), state.tappedCount[.golden, default: 0], points: 10)
                    row("disguise_normal", String(localized: "見破り"), state.spottedCount, points: Tuning.disguiseBonus)
                    row(nil, String(localized: "コンボ"), state.comboCount, points: Tuning.comboBonus)
                    if state.mode == .relaxed {
                        row("item_apple", L10n.name(.apple), state.appleCount, points: Tuning.relaxedApplePoints)
                        row("wolf_normal", String(localized: "ミス"), state.missCount, points: -Tuning.relaxedWolfPenalty)
                    } else {
                        row("wolf_normal", String(localized: "ミス"), state.missCount, points: nil)
                    }
                }
                .padding(.vertical, 6)

                PillButton(title: String(localized: "もう一度"), fill: .kGreen, textColor: .white, action: onRestart)
                PillButton(title: String(localized: "モード選択へ"), fill: Color(hex: 0xEFEDE7), action: onExit)
            }
            .padding(24)
            .background(.white, in: .rect(cornerRadius: 28))
            .padding(28)
            .frame(maxWidth: 380)
        }
    }

    private func row(_ image: String?, _ title: String, _ count: Int, points: Int?) -> some View {
        HStack(spacing: 8) {
            Group {
                if let image { Image(image).resizable().scaledToFit() } else { Color.clear }
            }
            .frame(width: 30, height: 30)
            Text("\(title) × \(count)").font(.kRounded(15, .bold)).foregroundStyle(Color.ink)
            Spacer()
            if let points {
                Text(String(localized: "\(count * points)点")).font(.kRounded(15, .bold)).foregroundStyle(.secondary)
            }
        }
    }
}
