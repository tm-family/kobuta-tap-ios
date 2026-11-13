//
//  KobutaTapTests.swift
//  KobutaTapTests
//
//  Created by 村石 拓海 on 2024/05/12.
//

import Foundation
@testable import KobutaTap
import Testing

struct KobutaTapTests {
    /// Configs/Project.xcconfig の MARKETING_VERSION が「x.y.z」形式で Info.plist に反映されていることを確認する
    @Test
    func marketingVersionIsSemanticVersion() throws {
        let version = try #require(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        )
        let components = version.split(separator: ".")
        #expect(components.count == 3, "MARKETING_VERSION は x.y.z 形式で指定する: \(version)")
        #expect(components.allSatisfy { Int($0) != nil }, "各要素は整数で指定する: \(version)")
    }

    /// 見た目はライトモードの前提なので、端末がダークモードでもライトモードで表示する
    @Test
    func interfaceStyleIsLight() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "UIUserInterfaceStyle") as? String == "Light")
    }

    /// CURRENT_PROJECT_VERSION が正の整数として Info.plist に反映されていることを確認する
    @Test
    func buildNumberIsPositiveInteger() throws {
        let build = try #require(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        )
        let number = try #require(Int(build), "CURRENT_PROJECT_VERSION は整数で指定する: \(build)")
        #expect(number > 0)
    }
}
