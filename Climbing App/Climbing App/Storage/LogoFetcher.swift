import Foundation
import UIKit

/// Fetches a gym's logo from the gym's own website.
///
/// ## What this costs, and who decides
///
/// Trace ships no gym logos. They are trademarks and there is no licensed
/// source for six hundred of them, so the only place a gym's logo exists is on
/// the gym's own site. Asking for it is a request, and a request tells that
/// server somebody is interested in that gym, which is the one thing in Trace
/// that leaves the phone for a reason that is not the person's account or their
/// subscription.
///
/// So the privacy policy lists it rather than claiming nothing goes out, and
/// the request is kept to the minimum that can still answer the question.
/// Nothing about the person goes with it: no id, no account, no location, and
/// the session is ephemeral so no cookie survives it. What comes back is saved
/// on the phone and never asked for twice.
///
/// What it gets is the site's own icon, which for most gyms is their logo and
/// for a few is whatever their web host set. It is not guaranteed to be good.
enum LogoFetcher {

    enum Failure: LocalizedError {
        case noWebsite
        case nothingUsable
        case network(String)

        var errorDescription: String? {
            switch self {
            case .noWebsite:
                return "OpenStreetMap has no website for this gym, so there is nowhere to ask."
            case .nothingUsable:
                return "Their site did not offer an image big enough to use. You can still add a photo yourself."
            case .network(let why):
                return why
            }
        }
    }

    /// Smaller than this and it is a browser tab icon, not a logo.
    static let minimumSide: CGFloat = 48
    /// A logo is not megabytes. Anything bigger is something else.
    static let maximumBytes = 3_000_000

    static func logo(for venue: Venue) async throws -> Data {
        guard let site = venue.website,
              let base = URL(string: site),
              base.host != nil
        else { throw Failure.noWebsite }

        for candidate in try await candidates(at: base) {
            if let data = try? await fetch(candidate), usable(data) { return data }
        }
        throw Failure.nothingUsable
    }

    /// Where to look, in the order worth looking.
    ///
    /// What the page declares comes first, and that ordering is from checking
    /// real gym sites rather than from what ought to be true. The tidy guess is
    /// that `/apple-touch-icon.png` sits at the root of every site; on the
    /// three gyms tried it was a 404 on all three, while all the usable icons
    /// were declared in the page and served off a content network. Asking the
    /// root first therefore spent two requests to learn nothing, and on a
    /// feature whose whole justification is that it makes as few requests as
    /// possible, that is the wrong way round.
    ///
    /// The root paths stay as a fallback, and the classic favicon last, since
    /// it is usually sixteen pixels and gets rejected anyway.
    static func candidates(at base: URL) async throws -> [URL] {
        var out: [URL] = []
        if let html = try? await fetchText(base) {
            out += iconLinks(in: html, relativeTo: base)
        }
        for path in ["/apple-touch-icon.png", "/apple-touch-icon-precomposed.png", "/favicon.ico"] {
            if let u = URL(string: path, relativeTo: base) { out.append(u.absoluteURL) }
        }
        var seen = Set<String>()
        return out.filter { seen.insert($0.absoluteString).inserted }
    }

    /// The icon links a page declares, best first.
    ///
    /// Pure, so the parsing is testable without a network. Deliberately a
    /// scan for the attributes rather than a real HTML parse: this only has to
    /// survive the handful of shapes a link tag comes in, and a parser that
    /// could do more would also have more to go wrong.
    static func iconLinks(in html: String, relativeTo base: URL) -> [URL] {
        var found: [(size: Int, url: URL)] = []
        var search = html.startIndex

        // Scanned over the original string, not a lowercased copy. Tag and
        // attribute names are case insensitive but the href is a URL and a URL
        // path is not: lowercasing the whole document turns /Assets/Logo.PNG
        // into a four hundred and four.
        while let open = html.range(of: "<link", options: .caseInsensitive,
                                    range: search..<html.endIndex) {
            guard let close = html.range(of: ">", range: open.upperBound..<html.endIndex)
            else { break }
            let tag = String(html[open.upperBound..<close.lowerBound])
            search = close.upperBound

            let lower = tag.lowercased()
            guard lower.contains("icon"), lower.contains("rel=") else { continue }
            // A link tag is also how a page loads its CSS.
            if lower.contains("stylesheet") || lower.contains("preload") { continue }

            guard let href = attribute("href", in: tag),
                  let url = URL(string: href, relativeTo: base)?.absoluteURL
            else { continue }

            // "180x180" and the like, so the biggest declared icon goes first.
            let size = attribute("sizes", in: tag)
                .flatMap { $0.split(separator: "x").first.flatMap { Int($0) } } ?? 0
            found.append((size, url))
        }
        return found.sorted { $0.size > $1.size }.map(\.url)
    }

    /// An attribute's value, with its own casing intact.
    ///
    /// The name is matched case insensitively, because HTML attribute names
    /// are; the value is returned exactly as written, because a URL is not.
    static func attribute(_ name: String, in tag: String) -> String? {
        guard let at = tag.range(of: name + "=", options: .caseInsensitive) else { return nil }
        var rest = tag[at.upperBound...]
        guard let quote = rest.first, quote == "\"" || quote == "'" else {
            // Unquoted: run to the next space.
            let value = rest.prefix { !$0.isWhitespace }
            return value.isEmpty ? nil : String(value)
        }
        rest = rest.dropFirst()
        guard let end = rest.firstIndex(of: quote) else { return nil }
        let value = String(rest[rest.startIndex..<end])
        return value.isEmpty ? nil : value
    }

    // MARK: The network, kept small

    private static var session: URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 12
        c.timeoutIntervalForResource = 20
        c.httpAdditionalHeaders = ["User-Agent": "Trace/1.0 (climbing app; logo lookup)"]
        return URLSession(configuration: c)
    }

    private static func fetch(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw Failure.network("That site answered with an error.")
        }
        guard data.count <= maximumBytes else { throw Failure.nothingUsable }
        return data
    }

    private static func fetchText(_ url: URL) async throws -> String {
        let data = try await fetch(url)
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
    }

    static func usable(_ data: Data) -> Bool {
        guard let image = UIImage(data: data) else { return false }
        return image.size.width >= minimumSide && image.size.height >= minimumSide
    }
}
