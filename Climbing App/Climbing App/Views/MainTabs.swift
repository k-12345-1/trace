import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// The shell: two places to be, and one button that starts a climb.
///
/// Recording is not a tab. It is an action, so it gets the raised button in the
/// middle rather than a page of its own, and it returns you to wherever you were.
struct MainTabs: View {
    enum Tab { case home, profile }

    @State private var tab: Tab = .home
    @State private var showEntry = false
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
                case .profile: NavigationStack { ProfileScreen() }
                }
            }

            TabBar(tab: $tab) { showEntry = true }
        }
        .sheet(isPresented: $showEntry) {
            EntrySheet(
                onRecord: { showEntry = false; showCapture = true },
                onScan:   { showEntry = false; showScan = true },
                pickerItem: $pickerItem
            )
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

    private func loadPicked(_ item: PhotosPickerItem) async {
        guard let movie = try? await item.loadTransferable(type: PickedMovie.self) else { return }
        pendingURL = movie.url
        pickerItem = nil
        showEntry = false
        showAnalyzer = true
    }
}

// MARK: - The bar

private struct TabBar: View {
    @Binding var tab: MainTabs.Tab
    let onPlus: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            item(.home, symbol: "house")
            plus
            item(.profile, symbol: "person")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(Theme.ground)
                .overlay(Capsule().stroke(Theme.lineStrong, lineWidth: 1))
                .shadow(color: Theme.blue.opacity(0.10), radius: 14, y: 4)
        )
        .padding(.bottom, 6)
    }

    private func item(_ which: MainTabs.Tab, symbol: String) -> some View {
        let active = tab == which
        return Button { tab = which } label: {
            VStack(spacing: 5) {
                Image(systemName: active ? "\(symbol).fill" : symbol)
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(active ? Theme.accent : Theme.ink3)
                // The highlight, rather than a filled pill: it marks where you
                // are without turning the whole bar into a coloured object.
                Capsule()
                    .fill(active ? Theme.accent : .clear)
                    .frame(width: 16, height: 2.5)
            }
            .frame(width: 74, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var plus: some View {
        Button(action: onPlus) {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Theme.accent))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }
}

// MARK: - What the plus opens

/// Three ways to put something into Trace. Kept as a sheet rather than a screen:
/// it is a fork in the road, not a destination.
private struct EntrySheet: View {
    let onRecord: () -> Void
    let onScan: () -> Void
    @Binding var pickerItem: PhotosPickerItem?

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                MicroLabel(text: "Add to Trace")

                FlatButton(title: "Record a climb", filled: true, action: onRecord)

                PhotosPicker(selection: $pickerItem, matching: .videos, photoLibrary: .shared()) {
                    Text("IMPORT A CLIP")
                        .font(Theme.mono(11, weight: .medium))
                        .tracking(1.3)
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .overlay(RoundedRectangle(cornerRadius: Theme.r)
                            .stroke(Theme.lineStrong, lineWidth: 1))
                }

                Text("Phone on the floor, square to the wall, whole boulder in frame. Side on is best.")
                    .font(Theme.body(12.5))
                    .foregroundStyle(Theme.ink3)
                    .fixedSize(horizontal: false, vertical: true)

                Hairline().padding(.vertical, 2)

                FlatButton(title: "Scan a route", action: onScan)

                Text("Photograph a wall and tap one hold. Trace picks out the rest of the route by colour and saves it to your gym.")
                    .font(Theme.body(12.5))
                    .foregroundStyle(Theme.ink3)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(22)
        }
        .presentationDetents([.height(378)])
        .preferredColorScheme(.light)
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
