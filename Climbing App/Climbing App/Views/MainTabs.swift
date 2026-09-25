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
    @State private var showAnalyzer = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var pendingURL: URL?

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.ground.ignoresSafeArea()

            Group {
                switch tab {
                case .home:
                    NavigationStack { HomeScreen() }.id(homeRoot)
                case .profile:
                    NavigationStack { ProfileScreen() }.id(profileRoot)
                }
            }

            // A solid band under the bar, fading in at its top edge.
            //
            // The bar floats, so without this the page scrolls through the gaps
            // beside and beneath it and the last card on every screen is shown
            // sliced. Painted in the page's own ground rather than a tint, so it
            // reads as the page ending rather than as a band laid over it.
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

            // Tapping anywhere off the panel closes it, which is the only way
            // out that a modal would have given us for free.
            if entryOpen {
                // Opaque. At anything less the masthead and the cards behind it
                // showed through, which made the panel read as a translucent
                // sheet over a page rather than as its own screen.
                Theme.ground
                    .ignoresSafeArea()
                    .onTapGesture { close() }
                    .transition(.opacity)
            }

            if entryOpen {
                AddPanel(
                    onRecord: { close(); showCapture = true },
                    // The second scan is where Trace asks. Entitlement is read
                    // from StoreKit, never from a flag of our own.
                    onScan: {
                        close()
                        if Store.shared.scanNeedsPro && !Subscription.shared.isPro {
                            showPaywall = true
                        } else {
                            showScan = true
                        }
                    },
                    onClose: close,
                    pickerItem: $pickerItem
                )
                .padding(.horizontal, 12)
                .padding(.top, 26)
                .padding(.bottom, 108)
                .transition(.opacity)
            }

            TabBar(tab: $tab, entryOpen: entryOpen, onPick: pick) {
                withAnimation(.easeOut(duration: 0.18)) { entryOpen.toggle() }
            }
            .padding(.horizontal, 10)
        }
        .fullScreenCover(isPresented: $showCapture) {
            CaptureScreen { url in
                showCapture = false
                if let url { pendingURL = url; showAnalyzer = true }
            }
        }
        .fullScreenCover(isPresented: $showScan) { ScanScreen() }
        .fullScreenCover(isPresented: $showPaywall) {
            NavigationStack {
                PaywallScreen { showScan = true }
            }
        }
        .fullScreenCover(isPresented: $showAnalyzer) {
            if let url = pendingURL {
                AnalyzingScreen(sourceURL: url) { showAnalyzer = false; pendingURL = nil }
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await loadPicked(item) }
        }
        .preferredColorScheme(.light)
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

    private func loadPicked(_ item: PhotosPickerItem) async {
        guard let movie = try? await item.loadTransferable(type: PickedMovie.self) else { return }
        pendingURL = movie.url
        pickerItem = nil
        close()
        showAnalyzer = true
    }
}

// MARK: - The bar

private struct TabBar: View {
    @Binding var tab: MainTabs.Tab
    let entryOpen: Bool
    let onPick: (MainTabs.Tab) -> Void
    let onCentre: () -> Void

    private let height: CGFloat = 64
    private let target: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                .fill(Theme.blue)

            HStack(spacing: 0) {
                item(.home)
                centre
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
                // the bar into a row of coloured blocks.
                Capsule()
                    .fill(Theme.blueLight)
                    .frame(width: active ? 14 : 0, height: 2)
                    .offset(y: 13)
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
    private var centre: some View {
        Button(action: onCentre) {
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
        .accessibilityLabel(entryOpen ? "Close" : "Add to Trace")
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
            ScrollView {
                VStack(spacing: 10) {
                    row(icon: "record.circle", title: "Record a climb",
                        detail: "Phone on the floor, square to the wall, whole boulder in frame.",
                        action: onRecord)

                    PhotosPicker(selection: $pickerItem, matching: .videos,
                                 photoLibrary: .shared()) {
                        rowBody(icon: "photo.on.rectangle", title: "Import a clip",
                                detail: "Use something you already filmed.")
                    }
                    .buttonStyle(.plain)

                    row(icon: "viewfinder", title: "Scan a route",
                        detail: "Photograph a wall and tap one hold. Trace picks out the rest by colour and saves it to your gym.",
                        action: onScan)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 18)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.blue)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
    }

    private var header: some View {
        ZStack {
            Text("Add to Trace")
                .font(Theme.serif(19, .semibold))
                .foregroundStyle(.white)

            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(.white.opacity(0.12)))
                        .overlay(Circle().stroke(.white.opacity(0.16), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private func row(icon: String, title: String, detail: String,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) { rowBody(icon: icon, title: title, detail: detail) }
            .buttonStyle(.plain)
    }

    private func rowBody(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(Theme.blue)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Theme.blueLight))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.ui(16, .semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(Theme.ui(13))
                    .foregroundStyle(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(.white.opacity(0.10), lineWidth: 1))
        .contentShape(Rectangle())
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
