import SwiftUI

/// The climber's own account of a climb, on the attempt it belongs to.
///
/// It sits high on the screen, under the name and above the measurements,
/// because it is the one part of this page nobody but the climber can fill in
/// and the moment to fill it in is now, between burns, not later.
///
/// Nothing here is required and nothing is defaulted. A scale nobody has
/// touched shows no answer rather than a middle one, and clearing everything
/// takes the note off the climb entirely.
struct NotesCard: View {
    let climb: Climb

    @ObservedObject private var store = Store.shared
    @State private var draft = ClimbNotes()
    @State private var loaded = false
    @FocusState private var writing: Bool

    private var live: ClimbNotes {
        store.climbs.first { $0.id == climb.id }?.notes ?? ClimbNotes()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionTitle("How it went")

            scale(title: "How it felt",
                  ends: ClimbNotes.effortEnds,
                  value: draft.effort,
                  name: ClimbNotes.effortLabel) { draft.effort = $0; save() }

            scale(title: "The holds",
                  ends: ClimbNotes.holdEnds,
                  value: draft.holds,
                  name: ClimbNotes.holdLabel) { draft.holds = $0; save() }

            tags(title: "The wall", options: ClimbNotes.WallAngle.allCases.map { ($0.rawValue, $0.label) },
                 chosen: draft.angle.map { [$0.rawValue] } ?? []) { raw in
                let a = ClimbNotes.WallAngle(rawValue: raw)
                draft.angle = draft.angle == a ? nil : a
                save()
            }

            tags(title: "Made of", options: ClimbNotes.HoldType.allCases.map { ($0.rawValue, $0.label) },
                 chosen: Set(draft.holdTypes.map(\.rawValue))) { raw in
                guard let h = ClimbNotes.HoldType(rawValue: raw) else { return }
                if draft.holdTypes.contains(h) { draft.holdTypes.remove(h) } else { draft.holdTypes.insert(h) }
                save()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Anything else")
                    .font(Theme.ui(13.5, .semibold))
                    .foregroundStyle(Theme.ink2)
                TextField("The heel hook was the whole climb", text: $draft.note, axis: .vertical)
                    .font(Theme.ui(15))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1...4)
                    .focused($writing)
                    .submitLabel(.done)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 11)
                    .background(Theme.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.r, style: .continuous))
                    // Written on the way out rather than on every keystroke,
                    // which would be a file write per letter.
                    .onChange(of: writing) { _, nowWriting in if !nowWriting { save() } }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, 20)
        .task {
            guard !loaded else { return }
            draft = live
            loaded = true
        }
        .onDisappear { save() }
    }

    private func save() {
        guard loaded, draft != live else { return }
        store.setNotes(draft, for: climb)
    }

    /// Five steps, with both ends named and the chosen one said out loud.
    ///
    /// Tapping the step that is already chosen takes the answer back, because a
    /// scale with no way off it is a scale people learn not to touch.
    private func scale(title: String, ends: (low: String, high: String),
                       value: Int?, name: @escaping (Int) -> String,
                       set: @escaping (Int?) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(Theme.ui(13.5, .semibold))
                    .foregroundStyle(Theme.ink2)
                Spacer(minLength: 8)
                Text(value.map(name) ?? "Not said")
                    .font(Theme.ui(13.5, value == nil ? .regular : .semibold))
                    .foregroundStyle(value == nil ? Theme.ink3 : Theme.accentText)
            }

            HStack(spacing: 7) {
                ForEach(1...5, id: \.self) { step in
                    let on = value != nil && step <= value!
                    Button { set(value == step ? nil : step) } label: {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(on ? Theme.blue : Theme.surface2)
                            .frame(height: 34)
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(Theme.line, lineWidth: on ? 0 : 1))
                            .overlay(
                                Text("\(step)")
                                    .font(Theme.ui(13, .semibold))
                                    .foregroundStyle(on ? .white : Theme.ink3))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title), \(name(step))")
                }
            }

            HStack {
                Text(ends.low)
                Spacer()
                Text(ends.high)
            }
            .font(Theme.ui(11.5))
            .foregroundStyle(Theme.ink3)
        }
    }
}

extension NotesCard {
    /// A row of tags to tap on and off. What the route was, said once, so the
    /// progress screen can sort routes by what they were made of.
    fileprivate func tags(title: String, options: [(String, String)], chosen: Set<String>,
                          tap: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(Theme.ui(13.5, .semibold))
                .foregroundStyle(Theme.ink2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(options, id: \.0) { raw, label in
                        let on = chosen.contains(raw)
                        Button { tap(raw) } label: {
                            Text(label)
                                .font(Theme.ui(12.5, .semibold))
                                .foregroundStyle(on ? .white : Theme.ink3)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(on ? Theme.blue : Theme.surface2, in: Capsule())
                                .overlay(Capsule().stroke(Theme.line, lineWidth: on ? 0 : 1))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(title), \(label)")
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 1)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
    }
}

/// The same account, said in a line, for a list of attempts.
struct NotesLine: View {
    let notes: ClimbNotes

    var body: some View {
        if let text = NotesLine.text(notes) {
            Text(text)
                .font(Theme.ui(13))
                .foregroundStyle(Theme.ink3)
                .lineLimit(1)
        }
    }

    /// Nil when there is nothing to say, so a row does not grow an empty line.
    static func text(_ notes: ClimbNotes) -> String? {
        var parts: [String] = []
        if let effort = notes.effort { parts.append(ClimbNotes.effortLabel(effort)) }
        if let holds = notes.holds { parts.append("\(ClimbNotes.holdLabel(holds)) holds") }
        if let angle = notes.angle { parts.append(angle.label) }
        if !notes.holdTypes.isEmpty {
            parts.append(ClimbNotes.HoldType.allCases.filter { notes.holdTypes.contains($0) }
                            .map(\.label).joined(separator: ", "))
        }
        if parts.isEmpty, !notes.note.isEmpty { parts.append(notes.note) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
