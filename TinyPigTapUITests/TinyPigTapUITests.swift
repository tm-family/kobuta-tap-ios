//
//  TinyPigTapUITests.swift
//  TinyPigTapUITests
//
//  Created by 村石 拓海 on 2024/05/12.
//

import XCTest

final class TinyPigTapUITests: XCTestCase {
    override func setUpWithError() throws {
        // UI テストでは失敗した時点で即座に止める
        continueAfterFailure = false
    }

    /// 端末の言語に関係なく、指定した言語で起動する。
    /// 初登場のお知らせはプレイを一時停止して画面をふさぐため、表示済みとして起動する（引数のドメインなので端末には保存されない）
    @MainActor
    private func launch(language: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", language == "ja" ? "ja_JP" : "en_US"]
        for kind in ["golden", "disguise", "brick", "apple"] {
            app.launchArguments += ["-intro_\(kind)", "YES"]
        }
        app.launch()
        return app
    }

    /// タイトル → モード選択 → プレイ → 結果 → もう一度 → 結果 → モード選択 → タイトル → 遊び方 → タイトル
    @MainActor
    func testFlowFromTitleToResultAndBack() throws {
        let app = launch(language: "ja")

        let start = app.buttons["タップしてスタート"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()

        // のんびりは「おしまい」ですぐ終われる
        let relaxed = app.buttons["mode_relaxed"]
        XCTAssertTrue(relaxed.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["mode_challenge"].exists)
        relaxed.tap()

        finishRelaxedRound(app)
        app.buttons["もう一度"].tap()
        finishRelaxedRound(app)

        app.buttons["モード選択へ"].tap()
        XCTAssertTrue(relaxed.waitForExistence(timeout: 5))
        app.buttons["‹ 戻る"].tap()

        XCTAssertTrue(app.buttons["遊び方"].waitForExistence(timeout: 5))
        app.buttons["遊び方"].tap()
        XCTAssertTrue(app.staticTexts["着ぐるみのおおかみ"].waitForExistence(timeout: 5))
        app.buttons["ルール"].tap()
        XCTAssertTrue(app.staticTexts["ボーナス"].waitForExistence(timeout: 5))
        app.buttons["‹ 戻る"].tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5))
    }

    /// 英語の端末では、画面の文字が英語になる
    @MainActor
    func testEnglishTitleAndModes() throws {
        let app = launch(language: "en")

        let start = app.buttons["Tap to Start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["How to Play"].exists)
        start.tap()

        XCTAssertTrue(app.staticTexts["Choose a Mode"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["mode_challenge"].label.contains("Challenge"))
        XCTAssertTrue(app.buttons["mode_relaxed"].label.contains("Relax"))
    }

    /// のんびりのプレイ画面で「おしまい」を押し、結果画面が出るのを確かめる
    @MainActor
    private func finishRelaxedRound(_ app: XCUIApplication) {
        let done = app.buttons["おしまい"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertTrue(app.staticTexts["おつかれさま！"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["もう一度"].exists)
    }
}
