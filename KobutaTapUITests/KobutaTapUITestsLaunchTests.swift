//
//  KobutaTapUITestsLaunchTests.swift
//  KobutaTapUITests
//
//  Created by 村石 拓海 on 2024/05/12.
//

import XCTest

final class KobutaTapUITestsLaunchTests: XCTestCase {
    override static var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        // トラッキングの許可のダイアログで画面がふさがらないよう、広告を止めて起動する
        app.launchArguments += ["-disable-ads"]
        app.launch()

        // 起動直後のスクリーンショットをテスト結果に添付する
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
