import Foundation
@testable import KobutaTap
import Testing
import UIKit

/// 傘のきせかえ
@MainActor
struct UmbrellaSkinTests {
    /// どの傘でも、こぶたと着ぐるみのおおかみの傘をさしている絵と、落とす傘の絵がある
    @Test(arguments: UmbrellaSkin.allCases)
    func everySkinHasTextures(skin: UmbrellaSkin) {
        for kind in [ItemKind.piglet, .disguise] {
            for pose in [ItemKind.Pose.normal, .tapped, .run, .sit] {
                let name = kind.textureName(pose, skin: skin)
                #expect(UIImage(named: name) != nil, "\(name) がありません")
            }
            let hard = kind.textureName(.normal, hard: true, skin: skin)
            #expect(UIImage(named: hard) != nil, "\(hard) がありません")
            #expect(UIImage(named: kind.umbrellaTexture(skin: skin)) != nil)
        }
    }

    /// 傘の絵の名前。葉っぱはこれまでの絵、ほかは後ろに傘の名前を付ける。座った絵は傘を落としているので共通
    @Test
    func textureNames() {
        #expect(ItemKind.piglet.textureName(.normal, skin: .leaf) == "piglet_normal")
        #expect(ItemKind.piglet.textureName(.tapped, skin: .sakura) == "piglet_tapped_sakura")
        #expect(ItemKind.disguise.textureName(.normal, hard: true, skin: .snow) == "disguise_hard_snow")
        #expect(ItemKind.piglet.textureName(.sit, skin: .momiji) == "piglet_sit")
        #expect(ItemKind.piglet.umbrellaTexture(skin: .polkadot) == "umbrella_polkadot")
        #expect(ItemKind.piglet.umbrellaTexture() == "umbrella_leaf")
    }

    /// 金のこぶたとおおかみの傘は、きせかえの対象外
    @Test
    func goldenAndWolfKeepTheirUmbrellas() {
        #expect(ItemKind.golden.textureName(.normal, skin: .sakura) == "golden_normal")
        #expect(ItemKind.wolf.textureName(.run, skin: .sunflower) == "wolf_run")
        #expect(ItemKind.golden.umbrellaTexture(skin: .sakura) == "umbrella_gold")
        #expect(ItemKind.wolf.umbrellaTexture(skin: .sakura) == "umbrella_wolf")
    }

    /// 購入していなければ、選んでいても葉っぱの傘。購入していれば選んだ傘。覚えている値が壊れていたら葉っぱ
    @Test
    func currentSkinNeedsPurchase() throws {
        let defaults = try #require(UserDefaults(suiteName: "UmbrellaSkinTests"))
        defaults.removePersistentDomain(forName: "UmbrellaSkinTests")
        #expect(UmbrellaSkin.current(purchased: true, defaults: defaults) == .leaf)

        UmbrellaSkin.select(.sakura, defaults: defaults)
        #expect(UmbrellaSkin.current(purchased: false, defaults: defaults) == .leaf)
        #expect(UmbrellaSkin.current(purchased: true, defaults: defaults) == .sakura)

        defaults.set("unknown", forKey: UmbrellaSkin.selectedKey)
        #expect(UmbrellaSkin.current(purchased: true, defaults: defaults) == .leaf)
        defaults.removePersistentDomain(forName: "UmbrellaSkinTests")
    }

    /// 無料なのは葉っぱの傘だけで、きせかえは 5 種類
    @Test
    func fiveSkinsArePaid() {
        #expect(UmbrellaSkin.allCases.filter(\.isFree) == [.leaf])
        #expect(UmbrellaSkin.allCases.filter { !$0.isFree }.count == 5)
    }
}
