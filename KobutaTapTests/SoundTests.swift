//
//  SoundTests.swift
//  KobutaTapTests
//
//  鳴らす音のファイルがアプリに入っているか、ライセンスの表示に要るものがそろっているかを確かめる。
//

import Foundation
@testable import KobutaTap
import Testing

struct SoundTests {
    /// 効果音・BGM・ジングルのファイルが、すべて KobutaTap/Sounds/ からアプリに入っている
    @Test(arguments: SoundEffect.allCases.map(\.rawValue) + BGM.allCases.map(\.rawValue) + Jingle.allCases.map(\.rawValue))
    func soundFileIsBundled(name: String) {
        #expect(SoundPlayer.url(for: name) != nil, "KobutaTap/Sounds/ に \(name) が無い")
    }

    /// 音量は 0〜1 の範囲にする（AVAudioPlayer の volume の範囲）
    @Test
    func volumesAreInRange() {
        let volumes = SoundEffect.allCases.map(\.volume) + BGM.allCases.map(\.volume) + Jingle.allCases.map(\.volume)
        #expect(volumes.allSatisfy { (0...1).contains($0) })
    }

    /// CC BY 4.0 の曲には、作者が指定する書式（ライセンス名と URL）のクレジットを付ける
    @Test
    func attributionCreditsHaveLicenseURL() {
        let attributions = (Credits.music + Credits.soundEffects).filter { $0.license.contains("Attribution") }
        #expect(!attributions.isEmpty)
        #expect(attributions.allSatisfy { $0.license.contains("https://creativecommons.org/licenses/by/4.0/") })
    }

    /// フォントのライセンス（OFL.txt）をアプリから読める
    @Test
    func fontLicenseIsBundled() {
        #expect(Credits.fontLicense.contains("SIL OPEN FONT LICENSE Version 1.1"))
    }
}
