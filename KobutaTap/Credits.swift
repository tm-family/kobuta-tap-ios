import Foundation

/// アプリに入れている、ほかの人が作った素材とそのライセンス（設定 → ライセンスに出す）
struct Credit: Identifiable {
    /// 素材の名前
    let title: String
    let author: String
    /// ライセンスと、作者が求める書式のクレジット
    let license: String
    /// 素材のページ
    let url: URL

    var id: String { "\(author)/\(title)" }
}

enum Credits {
    /// BGM。Kevin MacLeod の曲は CC BY 4.0 なので、作者が指定する書式のクレジットが必須
    /// （書式は https://incompetech.com/music/royalty-free/faq.html ）
    static let music: [Credit] = [
        Credit(
            title: "\"Carefree\" Kevin MacLeod (incompetech.com)",
            author: "Kevin MacLeod",
            license: "Licensed under Creative Commons: By Attribution 4.0\nhttps://creativecommons.org/licenses/by/4.0/",
            url: URL(string: "https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1400037")!
        ),
        Credit(
            title: "Children's March Theme",
            author: "Cleyton Kauffman",
            license: "CC0 · Music by Cleyton Kauffman - https://soundcloud.com/cleytonkauffman",
            url: URL(string: "https://opengameart.org/content/childrens-march-theme")!
        ),
        Credit(
            title: "Cozy Puzzle Jingle & Result",
            author: "MintoDog",
            license: "CC0",
            url: URL(string: "https://opengameart.org/content/cozy-puzzle-jingle-result")!
        )
    ]

    /// 効果音（すべて CC0。表示の義務はないが、作者と出典を載せる）
    static let soundEffects: [Credit] = [
        cc0("Pop Sounds", by: "EZduzziteh", at: "https://opengameart.org/content/pop-sounds-0"),
        cc0("Music Jingles", by: "Kenney (www.kenney.nl)", at: "https://kenney.nl/assets/music-jingles"),
        cc0("UI Audio", by: "Kenney (www.kenney.nl)", at: "https://kenney.nl/assets/ui-audio"),
        cc0("ShiningRinging", by: "NoisyRedFox", at: "https://freesound.org/people/NoisyRedFox/sounds/759840/"),
        cc0("Bonk.wav", by: "facklere", at: "https://freesound.org/people/facklere/sounds/458572/"),
        cc0("FX swanee whistle down.wav", by: "v0idation", at: "https://freesound.org/people/v0idation/sounds/497093/"),
        cc0("Brick Drop on Grass 1.wav", by: "dichardson", at: "https://freesound.org/people/dichardson/sounds/570966/"),
        cc0("Boing 2", by: "magnuswaker", at: "https://freesound.org/people/magnuswaker/sounds/540790/"),
        cc0("Poof of Smoke", by: "Planman", at: "https://freesound.org/people/Planman/sounds/208111/"),
        cc0("Referee whistle sound.wav", by: "Rosa-Orenes256", at: "https://freesound.org/people/Rosa-Orenes256/sounds/538422/"),
        cc0("Referee whistle blow, gymnasium.wav", by: "SpliceSound", at: "https://freesound.org/people/SpliceSound/sounds/218318/"),
        cc0("Two Kazoo Fanfare.wav", by: "pel2na", at: "https://freesound.org/people/pel2na/sounds/321937/")
    ]

    private static func cc0(_ title: String, by author: String, at url: String) -> Credit {
        Credit(title: title, author: author, license: "CC0", url: URL(string: url)!)
    }

    /// フォント（M PLUS Rounded 1c）のライセンスの全文。アプリに入れている OFL.txt を読む
    static var fontLicense: String {
        guard let url = Bundle.main.url(forResource: "OFL", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "SIL Open Font License 1.1" }
        return text
    }
}
