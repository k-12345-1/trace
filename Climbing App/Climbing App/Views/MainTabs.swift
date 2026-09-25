import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// The shell: two places to be, and one button in the middle that adds things.
///
/// Built to the same pattern as the Lineage Health bar: a full-width pill inset
/// from both edges, even columns, a solid dark ground with light icons, and an
/// active tab marked by a short rule under it rather than by a filled shape.
///
/// Explore and the library are screens rather than tabs. They are reached from
/// Home, which keeps the bar down to the two places you actually switch between
/// and the one action you take from either of them.
///
/// The middle button behaves like that app's three-dot control. It is not a
/// modal: the panel rises over the page while the bar stays put, the plus turns
/// into a cross, and pressing it again puts it back. Nothing is covered that you
/// were looking at, and there is never a question about how to get out.
struct MainTabs: View {
    enum Tab: String, CaseIterable {
        case home, profile

        var label: String {
            switch self {
            case .home:    return "Home"
            case .profile: return "You"
            }
        }
        /// Drawn rather than taken from the system set, so the two icons match
        /// the reference exactly at the same stroke weight.
        @ViewBuilder
        func icon(size: CGFloat, color: Color) -> some View {
            switch self {
            case .home:    StrokeIcon(shape: Ic.Home(), size: size, color: color)
            case .profile: StrokeIcon(shape: Ic.User(), size: size, color: color)
            }
        }
    }

    @State private var tab: Tab = .home
    // Tapping the tab you are already on pops it back to its root. Without this
    // a screen three levels deep inside Home has no answer to the house icon,
    // which is the one thing every iOS user tries.
    //
    // Done by identity rather than by a NavigationPath binding, because every
    // link in the app is a destination link (`NavigationLink { Screen() }`) and
    // a path binding only ever sees value links: clearing it would leave the
    // stack exactly where it was. Changing the stack's id rebuilds it at its
    // root, which also returns the page to the top, and that is what the gesture
    // is asking for anyway.
    @State private var homeRoot = 0
    @State private var profileRoot = 0
    @State private var entryOpen = false
    @State private var showCapture = false
    @State private var showScan = false
    @State private var showPaywall = false
    @State private var pickerItem: PhotosPickerItem?
    /// True while a chosen clip is being copied in.
    ///
    /// Photos hands back a reference, not a file, so the clip has to be copied
    /// out of the library before anything can read it. On a long clip, or one
    /// that has to come down from iCloud first, that is seconds of a screen
    /// that looks like it ignored the tap.
    @State private var importing = false
    /// Why an import did not happen. Nil the rest of the time.
    @State private var importProblem: String?
    /// The clip waiting to be analyzed.
    ///
    /// An item rather than a flag beside an optional. A cover driven by
    /// `isPresented` whose body is `if let url = pendingURL` can be raised with
    /// nothing in it, and what that draws is a white screen: exactly what you
    /// got after pressing stop.
    @State private var pending: PendingClip?
    /// Set by whichever screen is showing, if it wants the page to run under
    /// the floating bar rather than end above it.
    @State private var fullBleed = false

    struct PendingClip: Identifiable {
        let url: URL
        var id: String { url.path }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            PaperGround()

            Group {
                switch tab {
                case .home:
                    NavigationStack { HomeScreen() }.id(homeRoot)
                case .profile:
                    NavigationStack { ProfileScreen() }.id(profileRoot)
                }
            }
            .onPreferenceChange(FullBleedKey.self) { fullBleed = $0 }

            // A solid band under the bar, fading in at its top edge.
            //
            // Not on a screen that says it runs underneath: a map is not a page
            // with a bottom, and a hundred and thirty points of cream across it
            // is a hundred and thirty points of the country missing.
            //
            // The bar floats, so without this the page scrolls through the gaps
            // beside and beneath it and the last card on every screen is shown
            // sliced. Painted in the page's own ground rather than a tint, so it
            // reads as the page ending rather than as a band laid over it.
            if !fullBleed {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                LinearGradient(
                    stops: [
                        .init(color: Theme.ground.opacity(0), location: 0),
                        .init(color: Theme.ground, location: 1)
                    ],
                    startPoint: .top, endPoint: .bottom)
                    .frame(height: 20)
                // Fixed height plus a spacer above it, rather than a fixed
                // height alone: the solid part has to reach the physical bottom
                // of the screen, not the bottom of the safe area, or the page
                // shows through under the home indicator.
                Theme.ground.frame(height: 130)
            }
            .allowsHitTesting(false)
            .ignoresSafeArea()
            .ignoresSafeArea(.keyboard, edges: .bottom)
            }

            // Tapping anywhere off the panel closes it, which is the only way
            // out that a modal would have given us for free.
            if entryOpen {
                // Opaque. At anything less the masthead and the cards behind it
                // showed through, which made the panel read as a translucent
                // sheet over a page rather than as its own screen.
                PaperGround()
                    .onTapGesture { close() }
                    .transition(.opacity)
            }

            if entryOpen {
                AddPanel(
                    onRecord: { leave { showCapture = true } },
                    // The second scan is where Trace asks. Entitlement is read
                    // from StoreKit, never from a flag of our own.
                    onScan: {
                        leave {
                            if Store.shared.scanNeedsPro && !Subscription.shared.isPro {
                                showPaywall = true
                            } else {
                                showScan = true
                            }
                        }
                    },
                    onClose: close,
                    pickerItem: $pickerItem
                )
                .padding(.horizontal, 12)
                .padding(.top, 30)
                .padding(.bottom, 92)
                .transition(.opacity)
            }

            // The bar hangs off a full height layer of its own.
            //
            // The keyboard is a safe area inset like any other, so it shrinks
            // whatever it is inside and anything anchored to the bottom of that
            // rides up on top of the keys. Putting the modifier on the bar does
            // not help: the bar is not what got shorter, its parent is. So the
            // parent here is a clear layer that keeps its height, and the bar
            // is anchored to the bottom of that instead.
            //
            // The pages still get the inset, so a field being typed into is
            // still scrolled clear of the keyboard.
            if importing { bringingItIn }

            VStack(spacing: 0) {
                // A spacer rather than a clear color. A Color fills the screen
                // and takes every tap that lands on it, which would make the
                // whole page under the bar dead; a Spacer occupies the same
                // room and hit-tests nothing.
                Spacer(minLength: 0)
                TabBar(tab: $tab, entryOpen: entryOpen, onPick: pick) {
                    withAnimation(.easeOut(duration: 0.18)) { entryOpen.toggle() }
                }
                .padding(.horizontal, 10)
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .fullScreenCover(isPresented: $showCapture) {
            CaptureScreen { url in
                showCapture = false
                guard let url else { return }   // backing out lands on the panel
                // The next turn of the run loop: raising a cover inside the
                // transaction that dismisses another gives UIKit two
                // presentations to settle at once.
                done()
                next { pending = PendingClip(url: url) }
            }
        }
        .fullScreenCover(isPresented: $showScan) { ScanScreen() }
        .fullScreenCover(isPresented: $showPaywall) {
            NavigationStack {
                PaywallScreen { showScan = true }
            }
        }
        .fullScreenCover(item: $pending) { clip in
            AnalyzingScreen(sourceURL: clip.url) { pending = nil }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            importing = true
            Task { await loadPicked(item) }
        }
        .alert("That clip did not come through",
               isPresented: Binding(get: { importProblem != nil },
                                    set: { if !$0 { importProblem = nil } })) {
            Button("OK", role: .cancel) { importProblem = nil }
        } message: {
            Text(importProblem ?? "")
        }
        .preferredColorScheme(.light)
    }

    /// Shown while a chosen clip is copied out of the photo library.
    private var bringingItIn: some View {
        ZStack {
            Theme.ground.opacity(0.94).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView().controlSize(.large)
                Text("Bringing the clip in")
                    .font(Theme.serif(19, .semibold))
                    .foregroundStyle(Theme.ink)
                Text("Copying it out of your photo library. A long clip, or one still in iCloud, takes a moment.")
                    .font(Theme.ui(13.5))
                    .foregroundStyle(Theme.ink3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 44)
            }
        }
        .transition(.opacity)
    }

    /// Picking a tab. Three things happen here rather than one.
    ///
    /// The add panel closes, because it is not a modal and nothing else would
    /// dismiss it: tapping a tab underneath it and having it stay put is the
    /// panel behaving like a sheet that forgot to be one. Tapping the tab you
    /// are already on empties its stack. And otherwise it just switches.
    private func pick(_ which: Tab) {
        if entryOpen { close() }
        if tab == which {
            switch which {
            case .home:    homeRoot += 1
            case .profile: profileRoot += 1
            }
        } else {
            tab = which
        }
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.18)) { entryOpen = false }
    }

    /// The panel is already open behind every cover it raised, so backing out
    /// of one needs nothing done at all. This exists for the paths that close
    /// it: finishing a recording, or picking a clip, both of which move you on
    /// rather than back.
    private func done() {
        entryOpen = false
    }

    /// Opens something from the panel, and leaves the panel where it is.
    ///
    /// Underneath a full screen cover the panel is invisible, so leaving it up
    /// costs nothing while the camera is running and pays for itself when the
    /// camera goes away: the panel is already on screen, with no animation to
    /// wait through and no glimpse of the page behind it. Closing it first and
    /// reopening it afterwards is what produced the flash of Home on the way
    /// out.
    ///
    /// It also avoids the defect that killed the record button. Raising a cover
    /// inside the same transaction that animates the panel away gives UIKit two
    /// presentations to settle at once, and it resolves them by drawing the
    /// cover while leaving the dismissing view's window in front of it: the
    /// screen looks right and every tap lands on a scrim that is already gone.
    /// There is no dismissal here to collide with.
    private func leave(_ present: @escaping () -> Void) {
        present()
    }

    /// One turn of the run loop later. Every handoff between two covers goes
    /// through here.
    private func next(_ work: @escaping () -> Void) {
        DispatchQueue.main.async(execute: work)
    }

    /// Copying a chosen clip somewhere Trace can read it.
    ///
    /// Every way this can fail now says so. It used to be one `try?` with a bare
    /// return, so a clip still in iCloud, or one in a container the importer
    /// could not open, produced no analysis and no message: the same nothing as
    /// a button that was never pressed.
    private func loadPicked(_ item: PhotosPickerItem) async {
        defer { importing = false }
        do {
            guard let movie = try await item.loadTransferable(type: PickedMovie.self) else {
                pickerItem = nil
                importProblem = "That clip could not be read. If it is stored in iCloud, open it in Photos once to bring it down to the phone, then try again."
                return
            }
            pickerItem = nil
            done()
            next { pending = PendingClip(url: movie.url) }
        } catch {
            pickerItem = nil
            importProblem = error.localizedDescription
        }
    }
}

// MARK: - The bar

private struct TabBar: View {
    @Binding var tab: MainTabs.Tab
    let entryOpen: Bool
    let onPick: (MainTabs.Tab) -> Void
    let onCenter: () -> Void

    private let height: CGFloat = 64
    private let target: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                .fill(Theme.blue)

            HStack(spacing: 0) {
                item(.home)
                center
                item(.profile)
            }
            .padding(.horizontal, 6)
        }
        .frame(height: height)
        .shadow(color: Theme.blue.opacity(0.22), radius: 16, y: 5)
    }

    private func item(_ which: MainTabs.Tab) -> some View {
        let active = tab == which && !entryOpen
        return Button { onPick(which) } label: {
            ZStack(alignment: .bottom) {
                which.icon(size: 23, color: active ? Theme.blueLight : .white.opacity(0.82))
                // A short rule, not a pill. It marks the tab without turning
                // the bar into a row of colored blocks.
                Capsule()
                    .fill(Theme.blueLight)
                    .frame(width: active ? 14 : 0, height: 2)
                    .offset(y: 8)
            }
            .frame(width: target, height: target)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(which.label)
    }

    /// A plus, which becomes a cross while the panel is up.
    ///
    /// It looks like a plus and behaves like the Lineage Health three dot
    /// control: it toggles rather than presenting, so the way out is the same
    /// button you came in by.
    private var center: some View {
        Button(action: onCenter) {
            ZStack {
                Circle().fill(Theme.blueLight)
                Image(systemName: "plus")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(entryOpen ? 45 : 0))
            }
            .frame(width: target + 4, height: target + 4)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entryOpen ? "Close" : "Trace a Climb")
    }
}

// MARK: - What the middle button opens

/// The add screen, built like the Lumi panel in the Lineage Health app: a dark
/// rounded sheet that covers the page but stops above the bar, so the bar stays
/// visible with its button already showing the way out. It fades into place
/// rather than sliding, which is what stops it reading as a modal.
private struct AddPanel: View {
    let onRecord: () -> Void
    let onScan: () -> Void
    let onClose: () -> Void
    @Binding var pickerItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 0) {
            header
            // Three rows sharing the height rather than stacked at the top of
            // it. The panel is nearly full screen, so a fixed height row leaves
            // most of it empty and the sheet reads as having failed to load.
            // No scroll view: three is all there is, and a scroll view that
            // never scrolls is only a way to hide that something was cut off.
            VStack(spacing: 16) {
                row(icon: "record.circle", title: "Record a climb",
                    detail: "Phone on the floor, square to the wall, whole boulder in frame.",
                    action: onRecord)

                // No `photoLibrary: .shared()`. That argument asks for the in-process
                // picker, which needs the person to have granted this app access to
                // their whole library; without the grant it opens nothing and says
                // nothing, which is exactly what "I pressed import and nothing
                // happened" looks like. The plain picker runs out of process, hands
                // back only the clip that was chosen, and needs no permission. It is
                // also the more private of the two, which makes it the right default
                // for this app regardless.
                PhotosPicker(selection: $pickerItem, matching: .videos) {
                    rowBody(icon: "photo.on.rectangle", title: "Import a clip",
                            detail: "Use something you already filmed.")
                }
                .buttonStyle(.plain)

                row(icon: "viewfinder", title: "Scan a route",
                    detail: "Photograph a wall. Trace reads the route colors on it and saves the one you pick to your gym.",
                    action: onScan)
            }
            .padding(.horizontal, 14)
            // The rows take the room rather than sitting in the top third of
            // it. They are still capped, because the fix for a panel that
            // looked empty is not three cards four hundred points tall with
            // their text floating in the middle of them.
            .frame(maxHeight: .infinity)
            .padding(.top, 18)
            // The same margin the title has above it. Because the rows absorb
            // whatever is left over, this is the whole of the gap under the
            // last card rather than a minimum it might exceed.
            .padding(.bottom, Self.margin)
        }
        // Full height, with rows that keep their own size inside it.
        //
        // The panel being tall was never the problem. Stretching the rows to
        // fill it was: three rows of two lines each became cards over four
        // hundred points high with their text floating in the middle. The rows
        // sit at the top at a sensible size and the space below them is space,
        // which is what the panel looked like before any of this.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.blue)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
    }

    /// The blue showing at either end of the panel: above the title and below
    /// the last card. One number, used twice, so the sheet is not top heavy.
    private static let margin: CGFloat = 30

    private var header: some View {
        ZStack {
            Text("Trace a Climb")
                .font(Theme.serif(19, .semibold))
                .foregroundStyle(.white)

            HStack {
                Spacer()
                // The app's own ring, not a filled disc. Every other way out of
                // a screen in Trace is a dashed ring, and a circle that almost
                // matches one reads as a different app's control.
                Button(action: onClose) {
                    CloseRing(color: .white, size: 36)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
        }
        // Ten, not eighteen: the ring sits four points inside its tap target,
        // so this is what puts its edge on the same line as the cards below.
        .padding(.horizontal, 10)
        // Four short of the margin, because the ring sits four points inside
        // its forty-four point tap target. What has to land on the margin is
        // the ring's edge, not the box around it: the ring is the highest ink
        // on the panel and the card below is the lowest, so measuring between
        // those two is what makes the blue at either end the same.
        .padding(.top, Self.margin - 4)
        .padding(.bottom, 16)
    }

    private func row(icon: String, title: String, detail: String,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) { rowBody(icon: icon, title: title, detail: detail) }
            .buttonStyle(.plain)
    }

    private func rowBody(icon: String, title: String, detail: String) -> some View {
        // The card fills its share of the sheet; the content sits in the middle
        // of it. Stacking the icon at the top and the text at the bottom of a
        // tall card, which is what this did, opens a gap down the middle that
        // reads as something having failed to load.
        HStack(alignment: .center, spacing: 15) {
            Image(systemName: icon)
                .font(.system(size: 23, weight: .regular))
                .foregroundStyle(Theme.blue)
                .frame(width: 52, height: 52)
                .background(Circle().fill(Theme.blueLight))

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(Theme.serif(19, .semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(Theme.ui(13.5))
                    .foregroundStyle(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        // The ceiling is high enough that the three cards still fill the
        // tallest phone between them. If they stopped short of it, the slack
        // would be split above and below the stack and the blue under the last
        // card would no longer match the blue above the title.
        .frame(maxWidth: .infinity, minHeight: 112, maxHeight: 200, alignment: .leading)
        .background(.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(.white.opacity(0.10), lineWidth: 1))
        .contentShape(Rectangle())
    }
}

// MARK: - Running under the bar

/// A screen saying it fills the phone.
///
/// The bar floats, and the band behind it exists so a scrolling page does not
/// show through the gaps beside and beneath it. A map has no bottom to show
/// through: it is the screen, and the band just paints over the part of it
/// nearest you. So a screen can opt out, and only the map does.
struct FullBleedKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension View {
    func runsUnderTheBar(_ on: Bool = true) -> some View {
        preference(key: FullBleedKey.self, value: on)
    }
}

// MARK: - Importing from the library

/// A clip picked out of Photos, copied somewhere Trace can read it.
struct PickedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).mov")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return PickedMovie(url: dest)
        }
    }
}
