//
//  KobutaTapUITests.swift
//  KobutaTapUITests
//
//  Created by 村石 拓海 on 2024/05/12.
//

import XCTest

final class KobutaTapUITests: XCTestCase {
    override func setUpWithError() throws {
        // UI テストでは失敗した時点で即座に止める
        continueAfterFailure = false
    }

    /// 端末の言語に関係なく、指定した言語で起動する。
    /// 初登場のお知らせはプレイを一時停止して画面をふさぐため、表示済みとして起動する（引数のドメインなので端末には保存されない）。
    /// トラッキングの許可・広告の同意のダイアログも画面をふさぐため、広告を止めて起動する
    @MainActor
    private func launch(language: String) -> XCUIApplication {
        let app = XCUIApplication()
        let locale = ["ja": "ja_JP", "en": "en_US", "de": "de_DE"][language] ?? "en_US"
        app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", locale, "-disable-ads"]
        for kind in ["golden", "disguise", "brick", "apple"] {
            app.launchArguments += ["-intro_\(kind)", "YES"]
        }
        app.launch()
        return app
    }

    /// タイトル → モード選択（5 つ）→ プレイ → 結果 → もう一度 → 結果 → モード選択 → タイトル → 遊び方 → タイトル
    @MainActor
    func testFlowFromTitleToResultAndBack() throws {
        let app = launch(language: "ja")

        let start = app.buttons["タップしてスタート"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()

        // のんびりは「おしまい」ですぐ終われる
        let relaxed = app.buttons["mode_relaxed"]
        XCTAssertTrue(relaxed.waitForExistence(timeout: 5))
        // のんびり・かんたん・ふつう・むずかしい・ちゃれんじの 5 つ
        for mode in ["easy", "normal", "hard", "challenge"] {
            XCTAssertTrue(app.buttons["mode_\(mode)"].exists, mode)
        }
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

    /// タイトル → 設定（音と振動のスイッチ）→ ライセンス → 設定 → タイトル
    @MainActor
    func testSettingsAndLicenses() throws {
        let app = launch(language: "ja")

        let settings = app.buttons["設定"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        // ランキング（Game Center）のボタンも右上に並ぶ。押すとサインインの画面が出るので、ここでは押さない
        XCTAssertTrue(app.buttons["ランキング"].exists)
        settings.tap()

        XCTAssertTrue(app.switches["settings_sound"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["settings_haptics"].exists)
        XCTAssertTrue(app.buttons["settings_restore"].exists)
        app.buttons["settings_licenses"].tap()

        XCTAssertTrue(app.staticTexts["\"Carefree\" Kevin MacLeod (incompetech.com)"].waitForExistence(timeout: 5))
        app.buttons["‹ 戻る"].tap()
        XCTAssertTrue(app.switches["settings_sound"].waitForExistence(timeout: 5))
        app.buttons["‹ 戻る"].tap()
        XCTAssertTrue(app.buttons["タップしてスタート"].waitForExistence(timeout: 5))
    }

    /// タイトル → きせかえ（購入前は購入・復元のボタンと鍵つきの傘）→ タイトル
    @MainActor
    func testDressUp() throws {
        let app = launch(language: "ja")

        let dressUp = app.buttons["きせかえ"]
        XCTAssertTrue(dressUp.waitForExistence(timeout: 10))
        dressUp.tap()

        XCTAssertTrue(app.buttons["dressup_purchase"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dressup_restore"].exists)
        for skin in ["leaf", "sakura", "sunflower", "momiji", "snow", "polkadot"] {
            XCTAssertTrue(app.buttons["skin_\(skin)"].exists, skin)
        }
        app.buttons["‹ 戻る"].tap()
        XCTAssertTrue(app.buttons["タップしてスタート"].waitForExistence(timeout: 5))
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

    /// 日本語・英語以外の端末（ドイツ語）では、既定の言語の英語で表示する
    @MainActor
    func testOtherLanguagesFallBackToEnglish() throws {
        let app = launch(language: "de")

        let start = app.buttons["Tap to Start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["How to Play"].exists)
        start.tap()
        XCTAssertTrue(app.staticTexts["Choose a Mode"].waitForExistence(timeout: 5))
    }

    /// プレイ中にアプリが裏に回ったら、盤面を隠して止める。「続ける」でカウントダウンしてから再開する
    @MainActor
    func testSuspendHidesBoardAndResumes() throws {
        let app = launch(language: "ja")

        let start = app.buttons["タップしてスタート"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        let relaxed = app.buttons["mode_relaxed"]
        XCTAssertTrue(relaxed.waitForExistence(timeout: 5))
        relaxed.tap()
        XCTAssertTrue(app.buttons["おしまい"].waitForExistence(timeout: 5))

        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertTrue(app.staticTexts["ひと休み中"].waitForExistence(timeout: 5))
        // 止めているあいだは、プレイ中だけ出す「おしまい」も出さない
        XCTAssertFalse(app.buttons["おしまい"].exists)
        app.buttons["続ける"].tap()
        XCTAssertTrue(app.staticTexts["ひと休み中"].waitForNonExistence(timeout: 5))

        // カウントダウンが終わるとプレイに戻り、いつもどおり終われる
        finishRelaxedRound(app)
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
