import SwiftUI

/// Every route you have recorded.
///
/// Lifted out of Home once the bar grew to five columns. Home is what you are
/// working on right now; this is the whole record, and it needs a screen rather
/// than the bottom third of another one.
struct LibraryScreen: View {
    @ObservedObject private var store = Store.shared
    @Environment(\.dismiss) private var dismiss
    @State private var order: LibraryOrder = .recent
    /// The other end of whichever question is being asked.
    @State private var reversed = false

    var body: some View {
        let entries = LibraryOrder.sort(store.library(), by: order,
                                        reversed: reversed, cost: EfficiencyCache.cost)
        ZStack {
            PaperGround()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    NavHeader(title: nil) { dismiss() }
                    header(count: entries.count)
                    if !entries.isEmpty { arranging }
                    if entries.isEmpty {
                        Text("Nothing yet. Record a boulder or import a clip you already have, and Trace will analyze your movement pattern.")
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

    /// Three questions you might be asking of the list, and the answer to the
    /// one being asked, in words. Pressing the one already chosen turns it
    /// around, which is the other half of every one of them: the worst-climbed
    /// routes are what to work on and the best-climbed are what worked.
    private var arranging: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                ForEach(LibraryOrder.allCases) { which in
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            if order == which { reversed.toggle() }
                            else { order = which; reversed = false }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(which.label)
                                .font(Theme.ui(13.5, .semibold))
                            if order == which {
                                Image(systemName: reversed ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 9, weight: .bold))
                            }
                        }
                        .foregroundStyle(order == which ? .white : Theme.ink2)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(order == which ? Theme.button : Theme.surface,
                                    in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(which.label), \(which.heading(reversed: order == which && reversed))")
                }
                Spacer(minLength: 0)
            }

            Text(order.heading(reversed: reversed))
                .font(Theme.ui(12.5))
                .foregroundStyle(Theme.ink3)
        }
        .padding(.horizontal, Theme.gutter)
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
