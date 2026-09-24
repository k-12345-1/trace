import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// The shell: four places to be, and one button in the middle that adds things.
///
/// Built to the same pattern as the Lineage Health bar, because it is a pattern
/// that already works on a phone: a full-width pill inset from both edges, five
/// even columns, a solid dark ground with light icons, and an active tab marked
/// by a short rule under it rather than by a filled shape.
///
/// The middle button behaves like that app's three-dot control. It is not a
/// modal: the panel rises over the page while the bar stays put, the dots turn
/// into a cross, and pressing it again puts them back. Nothing is covered that
/// you were looking at, and there is never a question about how to get out.
struct MainTabs: View {
    enum Tab: String, CaseIterable {
        case home, explore, library, profile

        var label: String {
            switch self {
            case .home:    return "Home"
            case .explore: return "Explore"
            case .library: return "Library"
            case .profile: return "You"
            }
        }
        var symbol: String {
            switch self {
            case .home:    return "house"
            case .explore: return "map"
            case .library: return "square.grid.2x2"
            case .profile: return "person"
            }
        }
    }

    @State private var tab: Tab = .home
    @State private var entryOpen = false
    @State private var showCapture = false
    @State private var showScan = false
    @State private var showAnalyzer = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var pendingURL: URL?

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.ground.ignoresSafeArea()

            Group {
                switch tab {
                case .home:    NavigationStack { HomeScreen() }
                case .explore: NavigationStack { ExploreScreen() }
                case .library: NavigationStack { LibraryScreen() }
                case .profile: NavigationStack { ProfileScreen() }
                }
            }

            // Tapping anywhere off the panel closes it, which is the only way
            // out that a modal would have given us for free.
            if entryOpen {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .onTapGesture { close() }
                    .transition(.opacity)
            }

            VStack(spacing: 12) {
                if entryOpen {
                    EntryPanel(
                        onRecord: { close(); showCapture = true },
                        onScan:   { close(); showScan = true },
                        pickerItem: $pickerItem
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                TabBar(tab: $tab, entryOpen: entryOpen) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        entryOpen.toggle()
                    }
                }
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

    private func close() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { entryOpen = false }
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
    let onCentre: () -> Void

    private let height: CGFloat = 64
    private let target: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                .fill(Theme.blue)

            HStack(spacing: 0) {
                item(.home)
                item(.explore)
                centre
                item(.library)
                item(.profile)
            }
            .padding(.horizontal, 6)
        }
        .frame(height: height)
        .shadow(color: Theme.blue.opacity(0.22), radius: 16, y: 5)
    }

    private func item(_ which: MainTabs.Tab) -> some View {
        let active = tab == which && !entryOpen
        return Button { tab = which } label: {
            ZStack(alignment: .bottom) {
                Image(systemName: active ? "\(which.symbol).fill" : which.symbol)
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(active ? Theme.blueLight : .white.opacity(0.82))
                // A short rule, not a pill. It marks the tab without turning
                // the bar into a row of coloured blocks.
                Capsule()
                    .fill(Theme.blueLight)
                    .frame(width: active ? 14 : 0, height: 2)
                    .offset(y: 15)
            }
            .frame(width: target, height: target)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(which.label)
    }

    /// Three dots, which become a cross while the panel is up.
    private var centre: some View {
        Button(action: onCentre) {
            ZStack {
                Circle().fill(Theme.blueLight)
                if entryOpen {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                } else {
                    HStack(spacing: 4.5) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle().fill(.white).frame(width: 4.5, height: 4.5)
                        }
                    }
                }
            }
            .frame(width: target, height: target)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entryOpen ? "Close" : "Add to Trace")
    }
}

// MARK: - What the middle button opens

/// Three ways to put something into Trace, on a card that rises over the page
/// with the bar still visible beneath it.
private struct EntryPanel: View {
    let onRecord: () -> Void
    let onScan: () -> Void
    @Binding var pickerItem: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add to Trace")
                .font(Theme.serif(19, .semibold))
                .foregroundStyle(Theme.ink)
                .padding(.bottom, 2)

            row(icon: "record.circle", title: "Record a climb",
                detail: "Phone on the floor, square to the wall, side on.",
                action: onRecord)

            PhotosPicker(selection: $pickerItem, matching: .videos, photoLibrary: .shared()) {
                rowBody(icon: "photo.on.rectangle", title: "Import a clip",
                        detail: "Use something you already filmed.")
            }
            .buttonStyle(.plain)

            row(icon: "viewfinder", title: "Scan a route",
                detail: "Tap one hold and Trace finds the rest by colour.",
                action: onScan)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.ground)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: Theme.blue.opacity(0.16), radius: 22, y: 8)
    }

    private func row(icon: String, title: String, detail: String,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) { rowBody(icon: icon, title: title, detail: detail) }
            .buttonStyle(.plain)
    }

    private func rowBody(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(Theme.blue)
                .frame(width: 42, height: 42)
                .background(Theme.accentWash)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.ui(16, .semibold))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(Theme.ui(13))
                    .foregroundStyle(Theme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
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
