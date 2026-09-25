import SwiftUI

struct AnalyzingScreen: View {
    let sourceURL: URL
    let onClose: () -> Void

    @StateObject private var analyzer = ClimbAnalyzer()
    @ObservedObject private var store = Store.shared
    @State private var label = ""
    @State private var started = false
    @State private var gymID: UUID?
    @State private var newGymName = ""
    @State private var addingGym = false

    var body: some View {
        NavigationStack {
            ZStack {
                PaperGround()
                switch analyzer.state {
                case .idle:     naming
                case .working:  working
                case .done(let climb): ResultsScreen(climb: climb, onClose: onClose)
                case .failed(let message): failure(message)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.light)
    }

    // MARK: Naming
    //
    // Free text, never validated against anything. It exists only so attempts on
    // the same climb can be grouped and compared against each other.

    private var naming: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: onClose) {
                    HStack(spacing: 7) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Cancel")
                            .font(Theme.ui(15, .semibold))
                    }
                    .foregroundStyle(Theme.ink2)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 9)
                    .background(Theme.surface, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 26)

            VStack(alignment: .leading, spacing: 18) {
                SectionHeader(micro: "Before we look", title: "What were you on?")

                Text("Anything you will recognize next time. Trace never checks this against a route list, it only uses it to group your attempts.")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.ink2)

                TextField("", text: $label, prompt: Text("Blue slab by the fan")
                    .foregroundStyle(Theme.ink3))
                    .font(Theme.body(16))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    // Clipped to the same shape as the border. Unclipped, the
                    // fill is a square sitting behind a rounded outline and its
                    // four corners show through as a halo.
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.r, style: .continuous))
                    .submitLabel(.done)

                if !Store.shared.attempts(matching: label).isEmpty {
                    let n = Store.shared.attempts(matching: label).count
                    MicroLabel(text: "Attempt \(n + 1) on this one", color: Theme.accentText)
                }

                whichGym

                FlatButton(title: "Analyze", filled: true) {
                    guard !started else { return }
                    started = true
                    let gym = gymID
                    Task { await analyzer.analyze(sourceURL: sourceURL, label: label, gymID: gym) }
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .onAppear { gymID = gymID ?? store.likelyGym?.id }
        .alert("New gym", isPresented: $addingGym) {
            TextField("Name", text: $newGymName)
            Button("Add") {
                let name = newGymName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { gymID = store.addGym(named: name).id }
                newGymName = ""
            }
            Button("Cancel", role: .cancel) { newGymName = "" }
        } message: {
            Text("Whatever you call it. Trace has no directory to check it against.")
        }
    }

    // MARK: Which gym

    /// Where this was filmed, so the climb files itself under the gym.
    ///
    /// Offered rather than demanded: a climb with no gym is a perfectly good
    /// climb, and one filmed outdoors has no right answer. The default is
    /// wherever you were last time, which is right nearly every session and
    /// costs one tap when it is not.
    private var whichGym: some View {
        VStack(alignment: .leading, spacing: 9) {
            MicroLabel(text: "Where")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.gyms) { gym in
                        chip(gym.name, on: gymID == gym.id) {
                            gymID = (gymID == gym.id) ? nil : gym.id
                        }
                    }
                    chip("New gym", on: false, dashed: true) { addingGym = true }
                }
                .padding(.horizontal, 1)
            }
            // Only up and down. A row whose contents already fit still
            // takes a sideways drag and rubber-bands, which on a page that
            // scrolls vertically reads as the page itself coming loose.
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            Text(gymID == nil
                 ? "Optional. Without it the climb still gets analyzed, it just will not show up under a gym."
                 : "This attempt, and the others on this route, will show under that gym.")
                .font(Theme.body(12))
                .foregroundStyle(Theme.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func chip(_ text: String, on: Bool, dashed: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(Theme.ui(13.5, .medium))
                .foregroundStyle(on ? .white : Theme.ink2)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(on ? Theme.button : Theme.surface, in: Capsule())
                .overlay(
                    Capsule().stroke(style: StrokeStyle(lineWidth: 1,
                                                        dash: dashed ? [4, 3] : []))
                        .foregroundStyle(dashed ? Theme.lineStrong : .clear)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Working

    private var working: some View {
        VStack(spacing: 22) {
            Spacer()
            MicroLabel(text: "Watching")
            Text("Tracking your movement")
                .font(Theme.heading(20))
                .foregroundStyle(Theme.ink)

            if case .working(let p) = analyzer.state {
                VStack(spacing: 10) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Theme.line).frame(height: 2)
                            Rectangle().fill(Theme.accent)
                                .frame(width: geo.size.width * p, height: 2)
                        }
                    }
                    .frame(height: 2)

                    Text("\(Int(p * 100)) %")
                        .font(Theme.mono(12))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink3)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.horizontal, 40)
            }

            Text("Every frame goes through movement analysis on this phone. Nothing is uploaded.")
                .font(Theme.body(13))
                .foregroundStyle(Theme.ink3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)
            Spacer()
        }
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 16) {
            MicroLabel(text: "Could not analyze")
            Text(message)
                .font(Theme.body(15))
                .foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)
            FlatButton(title: "Close") { onClose() }.frame(width: 180)
        }
        .padding(30)
    }
}
