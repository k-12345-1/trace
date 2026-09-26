import UIKit
import AVFoundation

/// A still from a climb, for the card to lead with.
///
/// Pulled at a third of the way in rather than at the start, because the first
/// second of most clips is an empty wall and a climber walking up to it.
/// Cached on disk: generating one costs a video decode, and the library shows
/// several at once.
enum Thumbnails {

    nonisolated static var directory: URL {
        let url = Store.documents.appendingPathComponent("Thumbs", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func url(for climb: Climb) -> URL {
        directory.appendingPathComponent("\(climb.id.uuidString).jpg")
    }

    /// The cached still, or nil if one has not been made yet.
    static func cached(for climb: Climb) -> UIImage? {
        UIImage(contentsOfFile: url(for: climb).path)
    }

    /// Makes the still if it is missing. Safe to call repeatedly.
    static func generate(for climb: Climb, maxWidth: CGFloat = 900) async -> UIImage? {
        if let existing = cached(for: climb) { return existing }

        let source = climb.videoURL
        guard FileManager.default.fileExists(atPath: source.path) else { return nil }

        let asset = AVURLAsset(url: source)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxWidth, height: maxWidth)

        let duration = (try? await asset.load(.duration).seconds) ?? 0
        let at = CMTime(seconds: max(0, duration / 3), preferredTimescale: 600)

        guard let cg = try? await generator.image(at: at).image else { return nil }
        let image = UIImage(cgImage: cg)
        if let data = image.jpegData(compressionQuality: 0.82) {
            try? data.write(to: url(for: climb), options: .atomic)
        }
        return image
    }

    /// One frame at a given moment, uncached.
    ///
    /// For showing a finding the thing it is describing. A sentence about bent
    /// arms is an assertion; the frame where they were bent is evidence, and
    /// evidence is shorter than prose.
    /// - Parameter maxWidth: the longest side of the extracted frame. Generous,
    ///   because the card this ends up on crops into it: a finding about two
    ///   feet is a box a hand's width across, and at six hundred pixels that
    ///   box was fifty pixels wide, blown up to a card three hundred and fifty
    ///   points across. The picture that arrived was a brown smear with two
    ///   rings drawn on it.
    static func frame(of climb: Climb, at seconds: Double,
                      maxWidth: CGFloat = 1400) async -> UIImage? {
        let source = climb.videoURL
        guard FileManager.default.fileExists(atPath: source.path) else { return nil }
        let asset = AVURLAsset(url: source)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxWidth, height: maxWidth)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)

        let duration = (try? await asset.load(.duration).seconds) ?? 0
        let at = CMTime(seconds: min(max(0, seconds), max(0, duration - 0.05)),
                        preferredTimescale: 600)
        guard let cg = try? await generator.image(at: at).image else { return nil }
        return UIImage(cgImage: cg)
    }

    static func remove(for climb: Climb) {
        try? FileManager.default.removeItem(at: url(for: climb))
    }
}

// MARK: - View

import SwiftUI

/// The still, or a placeholder while it is being made, or a placeholder for
/// good if the clip has gone.
struct ClimbThumbnail: View {
    let climb: Climb
    @State private var image: UIImage?

    var body: some View {
        // The ground is a flexible Color, so it takes whatever size the caller
        // proposes and the overlay is then clipped to that. Clipping a
        // scaledToFill image directly would clip to the image's own huge natural
        // size, which is no clipping at all, and it would spill over whatever
        // sits below it.
        Theme.surface2
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    // Quiet: this is a placeholder for a missing frame, not a
                    // second logo on the page.
                    MountainMark(inset: 0.3).opacity(0.18)
                }
            }
            .clipped()
            // clipped() clips drawing but not hit testing, so without this the
            // scaledToFill image keeps the touch area of its full natural size
            // and steals taps from whatever sits next to the card.
            .contentShape(Rectangle())
            .task {
                if image == nil { image = await Thumbnails.generate(for: climb) }
            }
    }
}
