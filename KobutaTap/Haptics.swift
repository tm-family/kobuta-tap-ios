import UIKit

/// 振動。設定でオフにしていたら何もしない。
/// 振動させるのは、おおかみに触れたとき・りんごを失ったとき・レンガを取ったときだけ（こぶたやりんごのタップでは振動させない）
@MainActor
enum Haptics {
    private static let impact = UIImpactFeedbackGenerator(style: .light)
    private static let notification = UINotificationFeedbackGenerator()

    /// プレイの始めに呼び、最初の振動の遅れを減らす
    static func prepare() {
        guard AppSettings.isHapticsOn else { return }
        impact.prepare()
        notification.prepare()
    }

    /// おおかみに触れてミスになった
    static func wolf() {
        guard AppSettings.isHapticsOn else { return }
        notification.notificationOccurred(.error)
    }

    /// レンガで守られている間に、おおかみに触れた
    static func wolfBlocked() {
        guard AppSettings.isHapticsOn else { return }
        impact.impactOccurred()
    }

    /// りんごを失った
    static func appleLost() {
        guard AppSettings.isHapticsOn else { return }
        notification.notificationOccurred(.warning)
    }

    /// レンガを取った
    static func brick() {
        guard AppSettings.isHapticsOn else { return }
        impact.impactOccurred()
    }
}
