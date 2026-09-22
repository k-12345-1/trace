import SwiftUI

struct AnalyzingScreen: View {
    let sourceURL: URL
    let onClose: () -> Void

    @StateObject private var analyzer = ClimbAnalyzer()
    @State private var label = ""
    @State private var started = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ground.ignoresSafeArea()
                switch analyzer.state {
                case .idle:     naming
                case .working:  working
                case .done(let climb): ResultsScreen(climb: climb, onClose: onClose)
                case .failed(let message): failure(message)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Naming
    //
    // Free text, never validated against anything. It exists only so attempts on
    // the same climb can be grouped and compared against each other.

    private var naming: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button("CANCEL") { onClose() }
                    .font(Theme.mono(11, weight: .medium))
                    .tracking(1.3)
                    .foregroundStyle(Theme.ink2)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 26)

            VStack(alignment: .leading, spacing: 18) {
                SectionHeader(micro: "Before we look", title: "What were you on?")

                Text("Anything you will recognise next time. Spotter never checks this against a route list, it only uses it to group your attempts.")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.ink2)

                TextField("", text: $label, prompt: Text("Blue slab by the fan")
                    .foregroundStyle(Theme.ink3))
                    .font(Theme.body(16))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .background(Theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: Theme.r)
                        .stroke(Theme.lineStrong, lineWidth: 1))
                    .submitLabel(.done)

                if !Store.shared.attempts(matching: label).isEmpty {
                    let n = Store.shared.attempts(matching: label).count
                    MicroLabel(text: "Attempt \(n + 1) on this one", color: Theme.accentText)
                }

                FlatButton(title: "Analyse", filled: true) {
                    guard !started else { return }
                    started = true
                    Task { await analyzer.analyse(sourceURL: sourceURL, label: label) }
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 20)

            Spacer()
        }
    }

    // MARK: Working

    private var working: some View {
        VStack(spacing: 22) {
            Spacer()
            MicroLabel(text: "Watching")
            Text("Tracking your centre of mass")
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

            Text("Every frame goes through pose estimation on this phone. Nothing is uploaded.")
                .font(Theme.body(13))
                .foregroundStyle(Theme.ink3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)
            Spacer()
        }
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 16) {
            MicroLabel(text: "Could not analyse")
            Text(message)
                .font(Theme.body(15))
                .foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)
            FlatButton(title: "Close") { onClose() }.frame(width: 180)
        }
        .padding(30)
    }
}
