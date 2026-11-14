import Foundation
@testable import KobutaTap
import Testing

/// 60 秒のモードとちゃれんじの、太陽と月の動き
@MainActor
struct SkyBodiesTests {
    private let sunsetStart = Tuning.eveningStarts - Tuning.sunsetLead
    private let duskStart = Tuning.nightStarts - Tuning.duskLead

    /// 日中は、沈み始めるまで太陽を動かさない
    @Test
    func sunStaysStillDuringTheDay() {
        let start = SkyBodies.at(elapsed: 0)
        #expect(start.sun == SkyBodies.daySun)
        #expect(start.sunWidth == SkyBodies.daySunWidth)
        #expect(start.sunset == 0)
        #expect(start.showsSun)
        #expect(start.moon == nil)
        #expect(SkyBodies.at(elapsed: sunsetStart) == start)
    }

    /// 夕方になる少し前から沈み始め、夕方のあいだに地平線で夕日になる
    @Test
    func sunSetsAroundEvening() {
        #expect(sunsetStart < Tuning.eveningStarts)
        let end = sunsetStart + Tuning.sunsetDuration
        var previous = SkyBodies.at(elapsed: sunsetStart)
        for step in 1...20 {
            let now = SkyBodies.at(elapsed: sunsetStart + Tuning.sunsetDuration * Double(step) / 20)
            #expect(now.sun.y < previous.sun.y, "沈むあいだは下がり続ける")
            #expect(now.sunset >= previous.sunset)
            previous = now
        }
        let evening = SkyBodies.at(elapsed: end)
        #expect(evening.sun == SkyBodies.eveningSun)
        #expect(evening.sunWidth == SkyBodies.eveningSunWidth)
        #expect(evening.sunset == 1)
        // 夕方のあいだは夕日を動かさない
        #expect(SkyBodies.at(elapsed: duskStart) == evening)
    }

    /// 夜になる少し前に夕日が地平線の下へ沈み、夜になったら月が昇る
    @Test
    func sunGoesDownAndMoonRises() {
        #expect(SkyBodies.at(elapsed: duskStart + Tuning.duskLead / 2).sun.y < SkyBodies.eveningSun.y)
        let night = SkyBodies.at(elapsed: Tuning.nightStarts)
        #expect(night.sun == SkyBodies.setSun)
        #expect(!night.showsSun)
        #expect(night.moon == SkyBodies.moonStart)
        #expect(SkyBodies.at(elapsed: Tuning.nightStarts - 0.01).moon == nil)

        let rising = SkyBodies.at(elapsed: Tuning.nightStarts + Tuning.moonriseDuration / 2).moon
        #expect((rising?.y ?? 0) > SkyBodies.moonStart.y)
        #expect(SkyBodies.at(elapsed: Tuning.nightStarts + Tuning.moonriseDuration).moon == SkyBodies.moonEnd)
        // ちゃれんじは夜のまま続くので、昇りきったら動かさない
        #expect(SkyBodies.at(elapsed: 600).moon == SkyBodies.moonEnd)
    }

    /// 夕日と昇り始めの月は、丘（地面の絵の上端）に隠れる高さにある
    @Test
    func setSunAndRisingMoonAreBehindTheHills() {
        // 地面の絵の丘のいちばん低いところは、画面の下から約 136（絵の単位）
        let lowestHill: CGFloat = 136
        #expect(SkyBodies.setSun.y + SkyBodies.eveningSunWidth / 2 < lowestHill)
        #expect(SkyBodies.moonStart.y + SkyBodies.moonWidth / 2 < lowestHill)
        // 夕日は半分ほど丘から出る
        #expect(SkyBodies.eveningSun.y + SkyBodies.eveningSunWidth / 2 > lowestHill)
    }
}
