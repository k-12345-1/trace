import SwiftUI

/// Every route you have recorded.
///
/// Lifted out of Home once the bar grew to five columns. Home is what you are
/// working on right now; this is the whole record, and it needs a screen rather
/// than the bottom third of another one.
struct LibraryScreen: View {
    @ObservedObject private var store = Store.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let entries = store.library()
        ZStack {
            Theme.ground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    NavHeader(title: nil) { dismiss() }
                    header(count: entries.count)
                    if entries.isEmpty {
                        Text("Nothing yet. Record a boulder or import a clip you already have, and Trace will tell you where the energy went.")
                            .font(Theme.ui(15))
                            .foregroundStyle(Theme.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, Theme.gutter)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 13),
                                            GridItem(.flexible(), spacing: 13)], spacing: 16) {
                            ForEach(entries) { entry in
                                NavigationLink { ClimbCardScreen(entry: entry) } label: {
                                    LibraryCard(entry: entry)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, Theme.gutter)
                    }
                }
                .padding(.bottom, 156)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
    }

    private func header(count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your library")
                    .font(Theme.title(30))
                    .foregroundStyle(Theme.ink)
                Text("\(count) route\(count == 1 ? "" : "s") · \(store.climbs.count) climb\(store.climbs.count == 1 ? "" : "s")")
                    .font(Theme.ui(14))
                    .foregroundStyle(Theme.ink3)
            }
            Spacer(minLength: 12)
            if store.climbs.contains(where: { $0.metrics.isTrustworthy }) {
                NavigationLink { ProgressScreen() } label: {
                    Text("Over time")
                        .font(Theme.ui(14, .semibold))
                        .foregroundStyle(Theme.accentText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 12)
    }
}
