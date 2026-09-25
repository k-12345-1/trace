import SwiftUI
import UIKit

/// The picture saved for a gym, decoded once.
///
/// Trace still ships no gym logos. This is whatever the person put there: a
/// photograph of the place, or the logo pulled from that gym's own website by
/// pressing the button that says it is going to do exactly that. Once it is on
/// the phone it is a picture like any other, and there is no reason the only
/// screen that shows it should be the one where it was set.
///
/// Decoding is cached because this is read from a view body, which runs
/// whenever anything on the screen changes: without it a list of gyms decodes a
/// JPEG per row per frame while it scrolls. The key carries the file's
/// modification date as well as its name, because the name is the gym's id and
/// does not change when the picture is replaced, so a name-only cache would
/// hand back the old logo forever.
@MainActor
enum GymPicture {
    private static var cache: [String: UIImage] = [:]
    /// Enough for a long list, and small enough that the whole thing can be
    /// thrown away rather than aged.
    private static let limit = 80

    static func image(for gym: Gym?) -> UIImage? {
        guard let url = gym?.imageURL else { return nil }
        let changed = (try? FileManager.default
            .attributesOfItem(atPath: url.path)[.modificationDate] as? Date)??
            .timeIntervalSince1970 ?? 0
        let key = "\(url.lastPathComponent)|\(changed)"
        if let hit = cache[key] { return hit }
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else { return nil }
        if cache.count >= limit { cache.removeAll() }
        cache[key] = image
        return image
    }
}

/// A gym's picture, square.
///
/// Fitted on paper rather than cropped to fill. A logo is usually wider than it
/// is tall and comes with its own margins built in; filling a square with one
/// cuts the ends off the name, which is the one thing a logo is for.
struct GymPictureSquare: View {
    let image: UIImage
    var size: CGFloat = 54
    var radius: CGFloat? = nil
    /// Share of the square left as margin.
    ///
    /// A photograph you took wants a little air around it. A logo does not: a
    /// site icon is drawn to fill a rounded square already, and leaving a ring
    /// of cream around one makes it look like a sticker of a logo rather than
    /// the logo.
    var inset: Double = 0.10

    var body: some View {
        Theme.surface
            .overlay {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(size * inset)
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: radius ?? size * 0.22,
                                        style: .continuous))
    }
}
