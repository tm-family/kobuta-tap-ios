import SpriteKit
import SwiftUI

struct GameView: View {
    let mode: GameMode
    let onRestart: () -> Void
    let onExit: () -> Void

    @State private var state: GameState
    @State private var scene: GameScene
    @Environment(\.scenePhase) private var scenePhase

    /// 画面の上端から上部の表示までの最小の距離（iPad のステータスバーの高さ）
    private static let hudMinimumTopInset: CGFloat = 24

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

                // ひと休みのあいだと、そのあとのカウントダウンのあいだは盤面を隠す（止めて考えられないように）
                if state.hidesBoard {
                    Backdrop()
                }

                if state.shieldRemaining > 0 {
                    RoundedRectangle(cornerRadius: 44)
                        .strokeBorder(Color.kBrick, lineWidth: 10)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }

                VStack { hud; Spacer() }
                    .frame(width: playWidth)
                    // ステータスバーを隠すと、iPad やホームボタンのある iPhone では上の安全領域が 0 になる。
                    // 上部の表示が画面の端に付かないよう、ステータスバーがあったときと同じだけは空ける
                    .padding(.top, max(0, Self.hudMinimumTopInset - geo.safeAreaInsets.top))

                if let remaining = state.timeRemaining, remaining > 0, remaining <= 10, state.status == .playing {
                    OutlinedText(text: String(localized: "あと \(Int(remaining.rounded(.up)))"), size: 40, color: Color(hex: 0xE85A4F))
                        .allowsHitTesting(false)
                }

                overlay.frame(width: geo.size.width, height: geo.size.height)
                    .animation(.easeOut(duration: 0.25), value: state.countdown)
            }
        }
        // プレイ中は時刻や電池の表示がキャラクターと重ならないよう、ステータスバーを隠す（メニューでは出す）
        .statusBarHidden()
        .onAppear {
            SoundPlayer.shared.playBGM(.play)
            SoundPlayer.shared.play(.start)
            // りんごのあるモードでは広告を使うので、無い・古くなっていたら読み込み直しておく
            if mode.startingApples != nil { Ads.shared.prepare() }
        }
        // App Switcher などでアプリが裏に回ったら、止めて盤面を隠す
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { scene.suspend() }
        }
        .task(id: state.status) {
            // 終わったら BGM を止めて笛を鳴らし、結果のジングル → 結果の BGM を流す。
            // すぐに「もう一度」を押したときは、この画面が消えて待ちが取り消される
            guard state.status == .finished else { return }
            if mode.hasLeaderboard { GameCenter.shared.submit(score: state.score) }
            SoundPlayer.shared.stopBGM()
            SoundPlayer.shared.play(.finish)
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            SoundPlayer.shared.playBGM(.result, after: state.isNewBest ? .newBest : .result)
        }
    }

    @ViewBuilder private var overlay: some View {
        switch state.status {
        case .intro:
            if let kind = state.introKind {
                IntroCard(kind: kind) { scene.resumeFromIntro() }
            }
        case .askContinue:
            ContinueCard(onContinue: { scene.continueGame() }, onStop: { scene.endGame() })
        case .appleOffer:
            AppleOfferCard(onFinish: { scene.finishAppleOffer(rewarded: $0) })
        case .suspended:
            SuspendedCard { scene.resumeFromSuspension() }
        case .countdown:
            OutlinedText(text: "\(state.countdown)", size: 96, color: .kPink, outline: 8)
                .id(state.countdown)
                .transition(.scale.combined(with: .opacity))
                .allowsHitTesting(false)
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
                    if apples > Tuning.maxApples {
                        // ちゃれんじは最大 9 つまで増えるので、5 つを超えたら数で出す
                        HStack(spacing: 4) {
                            Image("icon_apple").resizable().scaledToFit().frame(width: 26, height: 26)
                            Text(verbatim: "× \(apples)").font(.kRounded(18).monospacedDigit()).foregroundStyle(Color.ink)
                        }
                    } else {
                        HStack(spacing: 2) {
                            ForEach(0..<max(Tuning.startingApples, apples), id: \.self) { index in
                                Image("icon_apple")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 26, height: 26)
                                    .opacity(index < apples ? 1 : 0.25)
                            }
                        }
                    }
                } else if state.status == .playing {
                    Button {
                        SoundPlayer.shared.play(.button)
                        scene.endGame()
                    } label: {
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
                TimeBar(fraction: remaining / (mode.timeLimit ?? Tuning.timedDuration), phase: state.phase)
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
                    Button {
                        SoundPlayer.shared.play(.button)
                        onOK()
                    } label: {
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

/// ひと休みの画面（アプリが裏に回って止めたとき。盤面は隠している）
struct SuspendedCard: View {
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            // ほかのカードと同じく背景を暗くし、カードと背景の雲を分ける
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 14) {
                Image("piglet_normal").resizable().scaledToFit().frame(width: 72)
                Text("ひと休み中").font(.kRounded(18)).foregroundStyle(Color.ink)
                Text("続けると、3・2・1 のあとに動き出します")
                    .font(.kRounded(13, .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                PillButton(title: String(localized: "続ける"), fill: .kGreen, textColor: .white, action: onContinue)
            }
            .padding(24)
            .background(.white, in: .rect(cornerRadius: 24))
            .padding(28)
            .frame(maxWidth: 380)
        }
    }
}

/// 続ける画面（1プレイ1回。「続ける」と「やめる」を同じくらい分かりやすく、急かさない）
struct ContinueCard: View {
    let onContinue: () -> Void
    let onStop: () -> Void
    /// 出したときに広告を用意できていれば、広告を見て続ける。
    /// 広告を外す購入をしているときと、広告を用意できていないとき（オフラインなど）は、広告なしで続ける
    @State private var watchesAd = !Monetization.adsRemoved && Monetization.isRewardedAdReady
    @State private var isShowingAd = false

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
                PillButton(
                    title: watchesAd ? String(localized: "広告を見て続ける") : String(localized: "続ける"),
                    fill: .kGreen,
                    textColor: .white
                ) {
                    guard watchesAd else {
                        onContinue()
                        return
                    }
                    guard !isShowingAd else { return }
                    isShowingAd = true
                    // 広告を途中で閉じたら、りんごはもらえず、この画面に戻る
                    Task {
                        let result = await Monetization.showRewardedAd()
                        isShowingAd = false
                        if result.grantsReward { onContinue() }
                    }
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

/// ちゃれんじで、広告を見てりんごを取るか選ぶ（広告を外す購入をしていない人の 1・4・7・10…個目のりんご）
struct AppleOfferCard: View {
    /// りんごを取るなら true（広告を最後まで見た・広告を出せなかった）。見送ったか途中で閉じたら false
    let onFinish: (Bool) -> Void
    @State private var isShowingAd = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 14) {
                Image("icon_apple").resizable().scaledToFit().frame(width: 56)
                Text("りんごを取る？").font(.kRounded(18)).foregroundStyle(Color.ink)
                Text("広告を見ると、りんごが1つ増えます")
                    .font(.kRounded(13, .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                PillButton(title: String(localized: "広告を見て取る"), fill: .kGreen, textColor: .white) {
                    guard !isShowingAd else { return }
                    isShowingAd = true
                    Task { onFinish(await Monetization.showRewardedAd().grantsReward) }
                }
                PillButton(title: String(localized: "見送る"), fill: Color(hex: 0xEFEDE7)) {
                    onFinish(false)
                }
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
                Text(state.mode == .relaxed ? String(localized: "おつかれさま！") : String(localized: "おしまい！"))
                    .font(.kRounded(26))
                    .foregroundStyle(Color.ink)
                Text(String(localized: "\(state.score)点")).font(.kRounded(42)).foregroundStyle(Color.kPink)
                Text(state.isNewBest ? String(localized: "自己ベスト更新！") : String(localized: "自己ベスト \(state.bestScore)点"))
                    .font(.kRounded(14, .bold))
                    .foregroundStyle(state.isNewBest ? Color(hex: 0xE8833A) : .secondary)
                if state.mode.hasLeaderboard {
                    rankingButton
                }

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

    /// Game Center のランキング（チャレンジだけ）
    private var rankingButton: some View {
        Button {
            SoundPlayer.shared.play(.button)
            GameCenter.shared.showLeaderboard()
        } label: {
            Label(String(localized: "ランキング"), systemImage: "trophy.fill")
                .font(.kRounded(14, .bold))
                .foregroundStyle(Color(hex: 0x8A5E12))
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(Color(hex: 0xF9E29A), in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
