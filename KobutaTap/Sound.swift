import AVFoundation

/// 効果音。値は KobutaTap/Sounds/ のファイル名（拡張子を除く）
enum SoundEffect: String, CaseIterable {
    case tapPiglet = "se_tap_piglet"
    case tapGolden = "se_tap_golden"
    case combo = "se_combo"
    case wolf = "se_wolf"
    case wolfBlocked = "se_shield_block"
    case spotted = "se_spotted"
    case brick = "se_brick"
    case appleGet = "se_apple_get"
    case appleLost = "se_apple_lost"
    case start = "se_start"
    case finish = "se_timeup"
    case button = "se_button"

    /// 音量（0〜1）。素材はピークをそろえてあるので、聞こえる大きさ（RMS）がそろうように下げる。
    /// こぶたのタップは何度も鳴るので、さらに小さめにする
    var volume: Float {
        switch self {
        case .tapPiglet: 0.55
        case .tapGolden: 0.75
        case .combo: 0.6
        case .appleGet: 0.6
        case .appleLost: 0.5
        case .start: 0.4
        case .finish: 0.6
        case .button: 0.6
        case .wolf, .wolfBlocked, .spotted, .brick: 1
        }
    }
}

/// BGM（繰り返し流す）。値は KobutaTap/Sounds/ のファイル名（拡張子を除く）
enum BGM: String, CaseIterable {
    /// タイトル・モード選択・遊び方・設定
    case title = "bgm_title"
    /// プレイ中（すべてのモード）
    case play = "bgm_play"
    /// 結果画面（ジングルの後に流す）
    case result = "bgm_result"

    /// 音量（0〜1）。曲ごとの大きさの違いをそろえる
    var volume: Float {
        switch self {
        case .title: 0.5
        case .play: 0.38
        case .result: 0.14
        }
    }
}

/// BGM の前に 1 回だけ流す短い曲。値は KobutaTap/Sounds/ のファイル名（拡張子を除く）
enum Jingle: String, CaseIterable {
    /// 結果画面
    case result = "jingle_result"
    /// 自己ベストを更新したときの結果画面
    case newBest = "jingle_new_best"

    var volume: Float {
        switch self {
        case .result: 0.33
        case .newBest: 0.2
        }
    }
}

/// 効果音と BGM を鳴らす。設定で音をオフにしていたら鳴らさない。
/// 消音モードでは鳴らさず、ほかのアプリの音楽とも混ぜる（.ambient）。ほかのアプリが音楽を流しているあいだは BGM を流さない
@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()

    /// 素材の拡張子。この順に探し、見つかったものを使う
    static let fileExtensions = ["m4a", "caf", "wav", "mp3"]
    /// 同じ効果音が続けて鳴っても途切れないよう、効果音ごとに用意するプレーヤーの数
    private static let voices = 3

    private var effects: [SoundEffect: [AVAudioPlayer]] = [:]
    private var nextVoice: [SoundEffect: Int] = [:]
    private var bgmPlayer: AVAudioPlayer?
    private var jinglePlayer: AVAudioPlayer?
    /// 画面に合わせて流す BGM。音がオフのあいだも覚えておき、オンに戻したら流す
    private var bgm: BGM?

    private init() {}

    static func url(for name: String) -> URL? {
        fileExtensions.lazy.compactMap { Bundle.main.url(forResource: name, withExtension: $0) }.first
    }

    /// 起動時に 1 回呼ぶ。効果音を読み込んでおき、最初に鳴らすときの遅れをなくす
    func configure() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        for effect in SoundEffect.allCases {
            guard let url = Self.url(for: effect.rawValue) else { continue }
            effects[effect] = (0..<Self.voices).compactMap { _ in
                guard let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
                player.volume = effect.volume
                player.prepareToPlay()
                return player
            }
        }
        // 電話などで止まったあと・ほかのアプリの音楽が止まったあとに、BGM を戻す
        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.resume() }
        }
        center.addObserver(forName: AVAudioSession.silenceSecondaryAudioHintNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.resume() }
        }
    }

    func play(_ effect: SoundEffect) {
        guard AppSettings.isSoundOn, let players = effects[effect], !players.isEmpty else { return }
        let index = nextVoice[effect, default: 0] % players.count
        nextVoice[effect] = index + 1
        let player = players[index]
        player.currentTime = 0
        player.play()
    }

    /// 画面に合わせて BGM を切り替える。同じ BGM が流れていれば、そのまま続ける。
    /// jingle を渡すと、それを 1 回流し終えてから BGM を流す
    func playBGM(_ newBGM: BGM, after jingle: Jingle? = nil) {
        if bgm == newBGM, jingle == nil, bgmPlayer?.isPlaying == true { return }
        bgm = newBGM
        startBGM(after: jingle)
    }

    /// BGM を止める（次の画面の BGM を流すまで、何も流さない）
    func stopBGM() {
        bgm = nil
        fadeOutBGM()
    }

    /// アプリが裏に回ったとき
    func pause() {
        jinglePlayer?.stop()
        jinglePlayer = nil
        bgmPlayer?.pause()
    }

    /// 設定で音を切り替えたとき・アプリに戻ったとき・ほかのアプリの音楽が止まったとき
    func resume() {
        let silenced = AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint
        guard AppSettings.isSoundOn, !silenced else {
            pause()
            return
        }
        guard bgmPlayer?.isPlaying != true, jinglePlayer?.isPlaying != true else { return }
        if let bgmPlayer {
            bgmPlayer.play()
        } else if bgm != nil {
            startBGM(after: nil)
        }
    }

    private func startBGM(after jingle: Jingle?) {
        fadeOutBGM()
        guard AppSettings.isSoundOn,
              !AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint,
              let bgm,
              let url = Self.url(for: bgm.rawValue),
              let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.numberOfLoops = -1
        bgmPlayer = player

        if let jingle, let jingleURL = Self.url(for: jingle.rawValue),
           let intro = try? AVAudioPlayer(contentsOf: jingleURL) {
            // ジングルが終わる時刻に BGM が始まるよう、端末の時計で予約する
            intro.volume = jingle.volume
            intro.play()
            jinglePlayer = intro
            player.volume = bgm.volume
            player.play(atTime: intro.deviceCurrentTime + intro.duration)
        } else {
            player.volume = 0
            player.play()
            player.setVolume(bgm.volume, fadeDuration: 0.4)
        }
    }

    private func fadeOutBGM() {
        let players = [bgmPlayer, jinglePlayer].compactMap(\.self)
        bgmPlayer = nil
        jinglePlayer = nil
        guard !players.isEmpty else { return }
        for player in players {
            player.setVolume(0, fadeDuration: 0.3)
        }
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            for player in players {
                player.stop()
            }
        }
    }
}
