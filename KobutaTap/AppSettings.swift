import Foundation

/// 設定画面で切り替える値（端末にだけ保存する）
enum AppSettings {
    /// 音（BGM と効果音）
    static let soundKey = "settings_sound"
    /// 振動
    static let hapticsKey = "settings_haptics"

    /// 起動時に呼ぶ。保存した値が無いときは、音も振動もオン
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [soundKey: true, hapticsKey: true])
    }

    static var isSoundOn: Bool { UserDefaults.standard.bool(forKey: soundKey) }
    static var isHapticsOn: Bool { UserDefaults.standard.bool(forKey: hapticsKey) }
}
