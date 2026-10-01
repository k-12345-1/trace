import UIKit

extension UIImage {
    /// The same picture with its pixels the way up it is shown.
    ///
    /// A camera still is stored sideways with a note saying which way is up,
    /// and `cgImage` is the sideways pixels. Everything the scanner measures
    /// is a position in those pixels, and everything the screen draws is a
    /// position in the picture as shown, so on a photograph taken in the app
    /// every outline landed where its hold would have been with the phone on
    /// its side. Redrawn once here, there is one set of pixels and one way up.
    var upright: UIImage {
        guard imageOrientation != .up || scale != 1 else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
