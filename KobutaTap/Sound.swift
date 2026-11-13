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
    case newBest = "se_new_best"
    case button = "se_button"

    /// 音量（0〜1）。何度も鳴る音は小さめにする
    var volume: Float {
        switch self {
        case .tapPiglet, .button: 0.6
        default: 0.9
        }
    }
}

/// BGM。値は KobutaTap/Sounds/ のファイル名（拡張子を除く）
enum BGM: String, CaseIterable {
    /// タイトル・モード選択・遊び方・設定
    case title = "bgm_title"
    /// プレイ中（チャレンジ・のんびり）
    case play = "bgm_play"
    /// 結果画面。ジングルなので繰り返さない
    case result = "bgm_result"

    var loops: Bool { self != .result }
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
    private static let bgmVolume: Float = 0.5

    private var effects: [SoundEffect: [AVAudioPlayer]] = [:]
    private var nextVoice: [SoundEffect: Int] = [:]
    private var bgmPlayer: AVAudioPlayer?
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

    /// 画面に合わせて BGM を切り替える。同じ BGM が流れていれば、そのまま続ける
    func playBGM(_ newBGM: BGM) {
        if bgm == newBGM, bgmPlayer?.isPlaying == true { return }
        bgm = newBGM
        startBGM()
    }

    /// アプリが裏に回ったとき
    func pause() {
        bgmPlayer?.pause()
    }

    /// 設定で音を切り替えたとき・アプリに戻ったとき・ほかのアプリの音楽が止まったとき
    func resume() {
        let silenced = AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint
        guard AppSettings.isSoundOn, !silenced else {
            bgmPlayer?.pause()
            return
        }
        guard bgmPlayer?.isPlaying != true else { return }
        if let bgmPlayer, bgm?.loops == true {
            bgmPlayer.play()
        } else if bgm?.loops == true {
            startBGM()
        }
    }

    private func startBGM() {
        fadeOutBGM()
        guard AppSettings.isSoundOn,
              !AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint,
              let bgm,
              let url = Self.url(for: bgm.rawValue),
              let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.numberOfLoops = bgm.loops ? -1 : 0
        player.volume = 0
        player.play()
        player.setVolume(Self.bgmVolume, fadeDuration: 0.4)
        bgmPlayer = player
    }

    private func fadeOutBGM() {
        guard let old = bgmPlayer else { return }
        bgmPlayer = nil
        old.setVolume(0, fadeDuration: 0.3)
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            old.stop()
        }
    }
}
