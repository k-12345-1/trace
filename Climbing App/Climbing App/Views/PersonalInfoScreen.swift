import SwiftUI

/// Height, reach and weight.
///
/// Three numbers, all optional, all doing real work. Height gives Trace a scale,
/// so speeds stop being body lengths and start being meters. Span sizes the
/// balance envelope on the overlay to your arms rather than to an average.
/// Weight turns the height your center of mass gained into joules.
struct PersonalInfoScreen: View {
    @ObservedObject private var store = Store.shared
    @Environment(\.dismiss) private var dismiss

    @State private var imperial = false
    @State private var heightCM: Double?
    @State private var spanCM: Double?
    @State private var massKG: Double?
    @State private var name = ""
    @State private var place = ""
    @StateObject private var whereabouts = Whereabouts()
    @StateObject private var places = PlaceSuggest()
    @FocusState private var focus: Field?

    enum Field: Hashable { case name, place, height, span, mass }

    private var draft: BodyProfile {
        BodyProfile(heightCM: heightCM, spanCM: spanCM, massKG: massKG,
                    usesImperial: imperial)
    }

    private var heightValid: Bool {
        heightCM == nil || BodyProfile.plausibleHeight(heightCM!)
    }
    private var spanValid: Bool {
        spanCM == nil || BodyProfile.plausibleSpan(spanCM!)
    }
    private var massValid: Bool {
        massKG == nil || BodyProfile.plausibleMass(massKG!)
    }
    private var allValid: Bool { heightValid && spanValid && massValid }

    var body: some View {
        ZStack {
            PaperGround()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    NavHeader(title: nil) { dismiss() }
                    header
                    you
                    Hairline().padding(.horizontal, 20)
                    units
                    measurement(
                        label: "Height",
                        help: "Standing, without shoes.",
                        value: $heightCM,
                        field: .height,
                        valid: heightValid,
                        complaint: "That is outside 90 to 240 cm. Check the units.",
                        effect: "Speeds on the overlay read in meters per second instead of body lengths. Trace estimates the scale from the frame where you were most extended, so treat it as close rather than exact."
                    )
                    Hairline().padding(.horizontal, 20)
                    measurement(
                        label: "Reach",
                        help: "Arms straight out, fingertip to fingertip.",
                        value: $spanCM,
                        field: .span,
                        valid: spanValid,
                        complaint: "That is outside 90 to 260 cm. Check the units.",
                        effect: "The dashed circle on the overlay becomes your actual reach. A hold outside it needs a shift of weight before it needs more strength."
                    )
                    Hairline().padding(.horizontal, 20)
                    weight
                    apeIndex
                    save
                }
                .padding(.bottom, 156)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
        .onAppear {
            imperial = store.body.usesImperial
            heightCM = store.body.heightCM
            spanCM = store.body.spanCM
            massKG = store.body.massKG
            name = store.account?.name ?? ""
            place = store.account?.place ?? ""
        }
        .onChange(of: whereabouts.placeName) { _, found in
            // Filled in once, then yours to edit. It does not keep correcting
            // itself, because the answer to "where do you climb" is not
            // wherever the phone happens to be sitting.
            if let found, place.isEmpty { place = found }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Personal info")
                .font(Theme.heading(22))
                .foregroundStyle(Theme.ink)
            Text("Everything here is optional and Trace works without it.")
                .font(Theme.body(13.5))
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .padding(.horizontal, Theme.gutter).padding(.top, 12).padding(.bottom, 22)
    }

    // MARK: Who you are

    /// Name and where you climb. Neither feeds the analysis: the name is what
    /// the app calls you, and the place is a label on your profile. They live
    /// here because this is the screen you open to change what Trace knows
    /// about you, and having to hunt for your own name elsewhere is worse than
    /// having two unrelated things on one page.
    private var you: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle("Name")
                TextField("", text: $name, prompt: Text("Name").foregroundStyle(Theme.ink3))
                    .font(Theme.ui(17, .medium))
                    .foregroundStyle(Theme.ink)
                    .textContentType(.name)
                    .focused($focus, equals: .name)
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .background(Theme.surface,
                                in: RoundedRectangle(cornerRadius: Theme.r, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.r, style: .continuous)
                        .stroke(focus == .name ? Theme.accent : .clear, lineWidth: 1.5))
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionTitle("Where you climb")
                HStack(spacing: 10) {
                    TextField("", text: $place,
                              prompt: Text("City, state").foregroundStyle(Theme.ink3))
                        .font(Theme.ui(17, .medium))
                        .foregroundStyle(Theme.ink)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .place)
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        .background(Theme.surface,
                                    in: RoundedRectangle(cornerRadius: Theme.r, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.r, style: .continuous)
                            .stroke(focus == .place ? Theme.accent : .clear, lineWidth: 1.5))

                    Button { whereabouts.find() } label: {
                        Group {
                            if case .asking = whereabouts.state {
                                ProgressView().controlSize(.small).tint(.white)
                            } else {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 50, height: 50)
                        .background(Theme.button, in: RoundedRectangle(cornerRadius: Theme.r, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: Theme.r, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Use my location")
                }

                // The guesses, which replace the paragraph that used to explain
                // what to type here. A list of real places says it better.
                if focus == .place, !places.results.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(places.results.enumerated()), id: \.offset) { i, guess in
                            if i > 0 { Hairline() }
                            Button {
                                // Focus goes first. The change handler below
                                // reads it, and picking a guess must not ask
                                // for guesses about the guess.
                                focus = nil
                                place = guess
                                places.clear()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "mappin.and.ellipse")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.ink3)
                                    Text(guess)
                                        .font(Theme.ui(15))
                                        .foregroundStyle(Theme.ink)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(Theme.surface,
                                in: RoundedRectangle(cornerRadius: Theme.r, style: .continuous))
                }

                if case .denied = whereabouts.state {
                    Text("Location is off for Trace. Type it instead, or turn it on in Settings.")
                        .font(Theme.ui(12.5))
                        .foregroundStyle(Theme.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .onChange(of: place) { _, typed in
                // Only while the field has the cursor. Filling it from the
                // location button, or arriving with it already set, must not
                // pop a list of alternatives to something nobody is editing.
                if focus == .place { places.suggest(typed) } else { places.clear() }
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 20)
    }

    // MARK: Units

    private var units: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Units")
            Picker("", selection: $imperial) {
                Text("Metric").tag(false)
                Text("Feet and inches").tag(true)
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, Theme.gutter).padding(.vertical, 18)
    }

    // MARK: One measurement

    @ViewBuilder
    private func measurement(label: String, help: String, value: Binding<Double?>,
                             field: Field, valid: Bool, complaint: String,
                             effect: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(Theme.ui(18, .bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(draft.describe(value.wrappedValue))
                    .font(Theme.ui(13, .medium)).monospacedDigit()
                    .foregroundStyle(value.wrappedValue == nil ? Theme.ink3 : Theme.blue)
            }
            Text(help)
                .font(Theme.body(12.5))
                .foregroundStyle(Theme.ink3)

            if imperial {
                FeetInchesField(cm: value, focus: $focus, field: field, valid: valid)
            } else {
                CentimetersField(cm: value, focus: $focus, field: field, valid: valid)
            }

            if !valid {
                Text(complaint)
                    .font(Theme.ui(13))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            buys(on: value.wrappedValue != nil, text: effect)
        }
        .padding(.horizontal, Theme.gutter).padding(.vertical, 18)
    }

    /// What a measurement buys, under the measurement itself.
    ///
    /// These used to be a list at the bottom of the screen, which meant reading
    /// about height four fields after typing it. A thing is best explained where
    /// it is asked for.
    /// What filling this in buys you. The line reads as live or not by its
    /// weight and color; it used to carry a checkbox as well, which made three
    /// short sentences look like a form to be completed.
    private func buys(on: Bool, text: String) -> some View {
        Text(text)
            .font(Theme.ui(12.5, on ? .medium : .regular))
            .foregroundStyle(on ? Theme.ink2 : Theme.ink3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 3)
    }

    // MARK: Weight

    private var weight: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text("Weight")
                    .font(Theme.ui(18, .bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(draft.describeMass(massKG))
                    .font(Theme.ui(13, .medium)).monospacedDigit()
                    .foregroundStyle(massKG == nil ? Theme.ink3 : Theme.blue)
            }
            Text("Climbing weight, shoes and harness included if you wear them.")
                .font(Theme.body(12.5))
                .foregroundStyle(Theme.ink3)

            MassField(kg: $massKG, imperial: imperial, focus: $focus, valid: massValid)

            if !massValid {
                Text("That is outside 25 to 200 kg. Check the units.")
                    .font(Theme.ui(13))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            buys(on: massKG != nil && heightCM != nil,
                 text: "With your height as well, the rise and fall of your center of mass reads in joules rather than as a ratio. It does not move your center of mass, which is a weighted average of where your limbs are and comes out in the same place whatever you weigh.")
        }
        .padding(.horizontal, Theme.gutter).padding(.vertical, 18)
    }

    // MARK: Ape index

    @ViewBuilder
    private var apeIndex: some View {
        if let label = draft.apeIndexLabel {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ape index")
                        .font(Theme.ui(15, .semibold))
                        .foregroundStyle(Theme.ink2)
                    Text("Reach minus height, the number climbers quote.")
                        .font(Theme.body(12.5))
                        .foregroundStyle(Theme.ink3)
                }
                Spacer(minLength: 12)
                Text(label)
                    .font(Theme.ui(17, .medium)).monospacedDigit()
                    .foregroundStyle(Theme.blue)
            }
            .padding(16)
            .background(Theme.blueWash)
            .clipShape(RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous))
            .padding(.horizontal, Theme.gutter)
        }
    }

    // MARK: Save

    private var save: some View {
        VStack(spacing: 10) {
            FlatButton(title: "Save", filled: true) {
                store.updateBody(draft)
                store.updateAccount(name: name, place: place)
                focus = nil
                dismiss()
            }
            .opacity(allValid ? 1 : 0.4)
            .disabled(!allValid)

            if !store.body.isEmpty {
                Button {
                    heightCM = nil; spanCM = nil; massKG = nil
                    store.updateBody(BodyProfile(usesImperial: imperial))
                } label: {
                    Text("Clear the measurements")
                        .font(Theme.ui(14, .semibold))
                        .foregroundStyle(Theme.ink3)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.gutter)
    }
}

// MARK: - Metric entry

private struct CentimetersField: View {
    @Binding var cm: Double?
    @FocusState.Binding var focus: PersonalInfoScreen.Field?
    let field: PersonalInfoScreen.Field
    let valid: Bool

    @State private var text = ""

    var body: some View {
        HStack(spacing: 8) {
            TextField("", text: $text, prompt: Text("0").foregroundStyle(Theme.ink3))
                .font(Theme.ui(17, .medium)).monospacedDigit()
                .keyboardType(.numberPad)
                .focused($focus, equals: field)
                .onChange(of: text) { _, new in
                    cm = Double(new.filter(\.isNumber))
                }
            Text("cm")
                .font(Theme.ui(13))
                .foregroundStyle(Theme.ink3)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.r, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.r, style: .continuous)
            .stroke(border, lineWidth: 1.5))
        .onAppear { text = cm.map { String(Int($0.rounded())) } ?? "" }
    }

    private var border: Color {
        if !valid { return Theme.blue }
        return focus == field ? Theme.accent : .clear
    }
}

// MARK: - Imperial entry

private struct FeetInchesField: View {
    @Binding var cm: Double?
    @FocusState.Binding var focus: PersonalInfoScreen.Field?
    let field: PersonalInfoScreen.Field
    let valid: Bool

    @State private var feet = ""
    @State private var inches = ""

    var body: some View {
        HStack(spacing: 8) {
            part($feet, unit: "ft")
            part($inches, unit: "in")
        }
        .onAppear {
            guard let cm else { return }
            let (f, i) = BodyProfile.feetInches(fromCM: cm)
            feet = String(f)
            inches = i == i.rounded() ? String(Int(i)) : String(i)
        }
        .onChange(of: feet) { _, _ in recompute() }
        .onChange(of: inches) { _, _ in recompute() }
    }

    private func part(_ text: Binding<String>, unit: String) -> some View {
        HStack(spacing: 6) {
            TextField("", text: text, prompt: Text("0").foregroundStyle(Theme.ink3))
                .font(Theme.ui(17, .medium)).monospacedDigit()
                .keyboardType(.decimalPad)
                .focused($focus, equals: field)
            Text(unit)
                .font(Theme.ui(13))
                .foregroundStyle(Theme.ink3)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.r, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.r, style: .continuous)
            .stroke(border, lineWidth: 1.5))
    }

    /// Empty in both boxes means not set, rather than zero.
    private func recompute() {
        let f = Int(feet.filter(\.isNumber)) ?? 0
        let i = Double(inches.filter { $0.isNumber || $0 == "." }) ?? 0
        cm = (f == 0 && i == 0) ? nil : BodyProfile.cm(feet: f, inches: i)
    }

    private var border: Color {
        if !valid { return Theme.blue }
        return focus == field ? Theme.accent : .clear
    }
}


// MARK: - Weight entry

/// One box, whose unit follows the picker above it.
///
/// Stored in kilogrammes whichever way the picker is set, so switching units
/// re-reads the same number rather than re-typing it.
private struct MassField: View {
    @Binding var kg: Double?
    let imperial: Bool
    @FocusState.Binding var focus: PersonalInfoScreen.Field?
    let valid: Bool

    @State private var text = ""

    var body: some View {
        HStack(spacing: 8) {
            TextField("", text: $text, prompt: Text("0").foregroundStyle(Theme.ink3))
                .font(Theme.ui(17, .medium)).monospacedDigit()
                .keyboardType(.decimalPad)
                .focused($focus, equals: .mass)
                .onChange(of: text) { _, new in
                    let typed = Double(new.filter { $0.isNumber || $0 == "." })
                    kg = typed.map { imperial ? BodyProfile.kg(pounds: $0) : $0 }
                }
            Text(imperial ? "lb" : "kg")
                .font(Theme.ui(13))
                .foregroundStyle(Theme.ink3)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.r, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.r, style: .continuous)
            .stroke(border, lineWidth: 1.5))
        .onAppear { show() }
        .onChange(of: imperial) { _, _ in show() }
    }

    private func show() {
        guard let kg else { text = ""; return }
        let shown = imperial ? kg * BodyProfile.poundsPerKG : kg
        text = String(Int(shown.rounded()))
    }

    private var border: Color {
        if !valid { return Theme.blue }
        return focus == .mass ? Theme.accent : .clear
    }
}
