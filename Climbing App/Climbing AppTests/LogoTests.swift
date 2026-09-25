import Testing
import Foundation
import UIKit
@testable import ClimbingApp

/// Reading a site's declared icons. Pure parsing, no network.
@Suite("Logo lookup")
struct LogoTests {

    private let base = URL(string: "https://example.com/")!

    @Test func itFindsADeclaredAppleTouchIcon() {
        let html = """
        <html><head>
        <link rel="apple-touch-icon" sizes="180x180" href="/icons/touch.png">
        </head></html>
        """
        let urls = LogoFetcher.iconLinks(in: html, relativeTo: base)
        #expect(urls.first?.absoluteString == "https://example.com/icons/touch.png")
    }

    /// The biggest declared icon is the one worth having.
    @Test func theLargestDeclaredSizeComesFirst() {
        let html = """
        <link rel="icon" sizes="32x32" href="/small.png">
        <link rel="apple-touch-icon" sizes="180x180" href="/big.png">
        <link rel="icon" sizes="64x64" href="/medium.png">
        """
        let urls = LogoFetcher.iconLinks(in: html, relativeTo: base)
        #expect(urls.map(\.lastPathComponent) == ["big.png", "medium.png", "small.png"])
    }

    /// A link tag is also how a page loads its CSS, and a stylesheet is not a
    /// logo however much its filename looks like one.
    @Test func stylesheetsAndPreloadsAreIgnored() {
        let html = """
        <link rel="stylesheet" href="/icons.css">
        <link rel="preload" as="image" href="/hero-icon.png">
        <link rel="icon" href="/real.png">
        """
        let urls = LogoFetcher.iconLinks(in: html, relativeTo: base)
        #expect(urls.map(\.lastPathComponent) == ["real.png"])
    }

    @Test func singleQuotesAndOddOrderingWork() {
        let html = "<link href='/a.png' rel='shortcut icon'>"
        #expect(LogoFetcher.iconLinks(in: html, relativeTo: base).first?.lastPathComponent == "a.png")
    }

    /// URLs are case sensitive even though tag names are not, so the href has
    /// to come back in its original casing.
    @Test func theHrefKeepsItsCase() {
        let html = #"<LINK REL="ICON" HREF="/Assets/LogoMark.PNG">"#
        let urls = LogoFetcher.iconLinks(in: html, relativeTo: base)
        #expect(urls.first?.absoluteString == "https://example.com/Assets/LogoMark.PNG")
    }

    @Test func anAbsoluteHrefIsLeftAlone() {
        let html = #"<link rel="icon" href="https://cdn.example.net/logo.png">"#
        #expect(LogoFetcher.iconLinks(in: html, relativeTo: base).first?.absoluteString
                == "https://cdn.example.net/logo.png")
    }

    @Test func aPageWithNoIconsGivesNothing() {
        #expect(LogoFetcher.iconLinks(in: "<html><body>hello</body></html>",
                                      relativeTo: base).isEmpty)
        #expect(LogoFetcher.iconLinks(in: "", relativeTo: base).isEmpty)
    }

    /// A malformed tag must not spin or crash the scan.
    @Test func anUnclosedTagEndsTheScan() {
        let html = #"<link rel="icon" href="/a.png"><link rel="icon" href="/b.png"#
        let urls = LogoFetcher.iconLinks(in: html, relativeTo: base)
        #expect(urls.map(\.lastPathComponent) == ["a.png"])
    }

    // MARK: What counts as usable

    /// A sixteen pixel favicon is a browser tab icon, not a logo.
    @Test func aTinyIconIsRejected() {
        #expect(!LogoFetcher.usable(pngData(side: 16)))
        #expect(!LogoFetcher.usable(pngData(side: 32)))
        #expect(LogoFetcher.usable(pngData(side: 180)))
    }

    @Test func rubbishIsRejected() {
        #expect(!LogoFetcher.usable(Data("not an image".utf8)))
        #expect(!LogoFetcher.usable(Data()))
    }

    /// A gym with no website has nowhere to ask, and says so rather than
    /// failing silently.
    @Test func aGymWithNoWebsiteExplainsItself() async {
        let gym = Gym(name: "Nowhere", venueID: nil)
        do {
            _ = try await LogoFetcher.logo(for: gym)
            Issue.record("expected a failure")
        } catch let e as LogoFetcher.Failure {
            #expect(e.errorDescription?.contains("no website") == true)
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    /// A PNG of exactly `side` pixels.
    ///
    /// The renderer works in points and defaults to the screen's scale, so
    /// asking for sixteen on a three times device writes a forty eight pixel
    /// file. `UIImage(data:)` reads a file back at scale one, so the sizes have
    /// to be pinned here or the fixture tests the wrong number.
    private func pngData(side: Int) -> Data {
        let size = CGSize(width: side, height: side)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        return image.pngData() ?? Data()
    }
}
