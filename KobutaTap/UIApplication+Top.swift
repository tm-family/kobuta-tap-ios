import UIKit

extension UIApplication {
    /// いちばん手前に出ている画面。ランキング・広告・同意の画面は、ここに重ねて出す
    var topViewController: UIViewController? {
        var top = connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?
            .rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
