import Testing
import Foundation
import CoreGraphics
import UIKit
@testable import ClimbingApp

/// How far a finding's still is allowed to zoom in.
///
/// The card crops to whatever the marks are drawn on, and for a finding about
/// two feet that is a box a hand's width across. With no floor under it, a
/// fifty pixel box was blown up to a card three hundred and fifty points wide:
/// a brown smear with two rings on it, and nothing in the picture to say it was
/// a foot. Twice now the fix for an unreadable card has been to crop tighter,
/// so this is the arithmetic that says when tighter stops helping.
@Suite("Finding stills")
struct StillTests {

    private let phoneFrame = CGSize(width: 1080, height: 1920)

    /// Two ankles, a hand apart, near the bottom of the frame.
    private let feet = CGRect(x: 0.46, y: 0.78, width: 0.05, height: 0.02)

    @Test("A tiny subject is not zoomed past the photograph")
    func aTinySubjectKeepsItsContext() {
        let crop = FindingStill.crop(subject: feet, pixels: phoneFrame)
        #expect(crop.width >= FindingStill.minimumShare)
        #expect(crop.height >= FindingStill.minimumShare)
        #expect(crop.width * phoneFrame.width >= FindingStill.minimumPixels - 1,
                "the crop was \(Int(crop.width * phoneFrame.width)) pixels wide")
    }

    /// The subject still has to be in the picture afterwards.
    @Test("The subject stays inside the crop")
    func theSubjectIsStillThere() {
        let crop = FindingStill.crop(subject: feet, pixels: phoneFrame)
        #expect(crop.minX <= feet.minX && crop.maxX >= feet.maxX,
                "\(crop) does not contain \(feet) across")
        #expect(crop.minY <= feet.minY && crop.maxY >= feet.maxY,
                "\(crop) does not contain \(feet) down")
    }

    /// And the crop cannot wander off the edge of the photograph, which is how
    /// a card ends up with a band of nothing down one side.
    @Test("The crop stays on the photograph")
    func theCropStaysInBounds() {
        for subject in [CGRect(x: 0.0, y: 0.0, width: 0.03, height: 0.03),
                        CGRect(x: 0.97, y: 0.97, width: 0.03, height: 0.03),
                        CGRect(x: 0.5, y: 0.0, width: 0.02, height: 0.02)] {
            let crop = FindingStill.crop(subject: subject, pixels: phoneFrame)
            #expect(crop.minX >= -0.0001 && crop.maxX <= 1.0001, "\(crop)")
            #expect(crop.minY >= -0.0001 && crop.maxY <= 1.0001, "\(crop)")
        }
    }

    /// A subject already bigger than the floor is left alone: the floor is a
    /// minimum, not a target, and a wandering line drawn over the whole wall
    /// must not be shrunk to it.
    @Test("A large subject is not pulled in")
    func aLargeSubjectIsLeftAlone() {
        let line = CGRect(x: 0.2, y: 0.1, width: 0.5, height: 0.75)
        let crop = FindingStill.crop(subject: line, pixels: phoneFrame)
        #expect(crop.width >= line.width)
        #expect(crop.height >= line.height)
    }

    /// A photograph too small to satisfy the pixel floor gives up the whole of
    /// itself rather than pretending.
    @Test("A small photograph gives everything it has")
    func aSmallPhotographGivesEverything() {
        let crop = FindingStill.crop(subject: feet, pixels: CGSize(width: 320, height: 240))
        #expect(crop.width == 1, "a 320 pixel wide frame cropped to \(crop.width)")
    }

    /// Nothing to point at means the whole photograph, not an empty rectangle.
    @Test("No subject is the whole picture")
    func noSubjectIsEverything() {
        let crop = FindingStill.crop(subject: nil, pixels: phoneFrame)
        #expect(crop == CGRect(x: 0, y: 0, width: 1, height: 1))
    }
}
