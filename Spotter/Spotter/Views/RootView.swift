import SwiftUI
import PhotosUI

struct RootView: View {
    @StateObject private var store = Store.shared
    @State private var showCapture = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var pendingURL: URL?
    @State private var showAnalyzer = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        masthead
                        Hairline()
                        focusBanner
                        entryPoints
                        Hairline()
                        history
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(isPresented: $showCapture) {
                CaptureScreen { url in
                    showCapture = false
                    if let url {
                        pendingURL = url
                        showAnalyzer = true
                    }
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
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Masthead

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("SPOTTER")
                    .font(.system(size: 16, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(Theme.ink)
                Spacer()
                MicroLabel(text: "\(store.climbs.count) climb\(store.climbs.count == 1 ? "" : "s")")
            }
            Text("The partner who watches you climb.")
                .font(Theme.body(14))
                .foregroundStyle(Theme.ink2)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 20)
    }

    // MARK: The session opening
    //
    // A partner picks up where you left off rather than greeting you blank.

    @ViewBuilder
    private var focusBanner: some View {
        if let focus = store.focus {
            NavigationLink {
                ProgressScreen()
            } label: {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        MicroLabel(
                            text: focus.isResolved
                                ? "Cleared"
                                : "Working on · day \(focus.daysActive)",
                            color: focus.isResolved ? Theme.ok : Theme.accentText
                        )
                        Spacer()
                        Text(focus.readout)
                            .font(Theme.mono(12, weight: .medium)).monospacedDigit()
                            .foregroundStyle(focus.isResolved ? Theme.ok : Theme.accentText)
                    }
                    Text(focus.kind.title)
                        .font(Theme.heading(17))
                        .foregroundStyle(Theme.ink)
                    Text(FocusEngine.greeting(for: focus))
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(focus.isResolved ? Theme.surface : Theme.accentWash)
                .overlay(Rectangle().stroke(
                    focus.isResolved ? Theme.line : Theme.lineStrong, lineWidth: 1))
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Entry points

    private var entryPoints: some View {
        VStack(spacing: 12) {
            FlatButton(title: "Record a climb", filled: true) { showCapture = true }

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
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
    }

    // MARK: History

    private var history: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                MicroLabel(text: "Your climbs")
                Spacer()
                if store.climbs.contains(where: { $0.metrics.isTrustworthy }) {
                    NavigationLink {
                        ProgressScreen()
                    } label: {
                        Text("OVER TIME →")
                            .font(Theme.mono(10, weight: .medium))
                            .tracking(1.2)
                            .foregroundStyle(Theme.accentText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            if store.climbs.isEmpty {
                Text("Nothing yet. Record a boulder or import a clip you already have, and Spotter will tell you where the energy went.")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.ink2)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
            } else {
                LazyVStack(spacing: 1) {
                    ForEach(store.climbs) { climb in
                        NavigationLink {
                            ResultsScreen(climb: climb)
                        } label: {
                            ClimbRow(climb: climb)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                store.delete(climb)
                            } label: {
                                Label("Delete this climb", systemImage: "trash")
                            }
                        }
                    }
                }
                .background(Theme.line)
                .padding(.bottom, 40)
            }
        }
    }

    private func loadPicked(_ item: PhotosPickerItem) async {
        guard let movie = try? await item.loadTransferable(type: PickedMovie.self) else { return }
        pendingURL = movie.url
        pickerItem = nil
        showAnalyzer = true
    }
}

// MARK: - Row

struct ClimbRow: View {
    let climb: Climb

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(climb.label.isEmpty ? "Untitled climb" : climb.label)
                    .font(Theme.heading(16))
                    .foregroundStyle(Theme.ink)
                HStack(spacing: 10) {
                    Text(climb.recordedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.ink3)
                    if climb.metrics.isTrustworthy {
                        Text("H \(String(format: "%.2f", climb.metrics.entropy))")
                            .font(Theme.mono(10.5))
                            .foregroundStyle(Theme.accentText)
                    } else {
                        Text("LOW TRACKING")
                            .font(Theme.mono(9.5))
                            .tracking(1)
                            .foregroundStyle(Theme.ink3)
                    }
                }
            }
            Spacer(minLength: 0)
            if let top = climb.findings.first {
                Rectangle()
                    .fill(Theme.ember[min(top.severity.rawValue, Theme.ember.count - 1)])
                    .frame(width: 3, height: 34)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.ground)
        .contentShape(Rectangle())
    }
}

// MARK: - Photos transfer
//
// PhotosPicker hands over a file that disappears, so it is copied immediately.

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
