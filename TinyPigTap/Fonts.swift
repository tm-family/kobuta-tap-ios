import CoreText
import SwiftUI
import UIKit

/// アプリ全体の文字は M PLUS Rounded 1c にそろえる（ロゴと同じ書体）。
/// フォントファイルはアプリに同梱し、起動時に登録する（Info.plist の設定は不要）。
enum AppFont {
    static let medium = "RoundedMplus1c-Medium"
    static let bold = "RoundedMplus1c-Bold"
    static let extraBold = "RoundedMplus1c-ExtraBold"

    private static let files = ["MPLUSRounded1c-Medium", "MPLUSRounded1c-Bold", "MPLUSRounded1c-ExtraBold"]

    static func register() {
        for file in files {
            guard let url = Bundle.main.url(forResource: file, withExtension: "ttf") else {
                assertionFailure("フォントが見つからない: \(file).ttf")
                continue
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func name(for weight: Font.Weight) -> String {
        if weight == .heavy || weight == .black { return extraBold }
        if weight == .bold || weight == .semibold { return bold }
        return medium
    }

    /// SpriteKitの文字（効果音など）用
    static func uiFont(_ size: CGFloat, weight: Font.Weight = .heavy) -> UIFont {
        UIFont(name: name(for: weight), size: size) ?? .systemFont(ofSize: size, weight: .heavy)
    }
}
