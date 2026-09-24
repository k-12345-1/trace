import SwiftUI

/// Height and reach.
///
/// Two numbers, both optional, both doing real work. Height gives Trace a scale,
/// so speeds stop being body lengths and start being metres. Span sizes the
/// balance envelope on the overlay to your arms rather than to an average.
struct PersonalInfoScreen: View {
    @ObservedObject private var store = Store.shared
    @Environment(\.dismiss) private var dismiss

    @State private var imperial = false
    @State private var heightCM: Double?
    @State private var spanCM: Double?
    @FocusState private var focus: Field?

    enum Field: Hashable { case height, span }

    private var draft: BodyProfile {
        BodyProfile(heightCM: heightCM, spanCM: spanCM, usesImperial: imperial)
    }

    private var heightValid: Bool {
        heightCM == nil || BodyProfile.plausibleHeight(heightCM!)
    }
    private var spanValid: Bool {
        spanCM == nil || BodyProfile.plausibleSpan(spanCM!)
    }

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    units
                    measurement(
                        label: "Height",
                        help: "Standing, without shoes.",
                        value: $heightCM,
                        field: .height,
                        valid: heightValid,
                        complaint: "That is outside 90 to 240 cm. Check the units."
                    )
                    Hairline().padding(.horizontal, 20)
                    measurement(
                        label: "Reach",
                        help: "Arms straight out, fingertip to fingertip.",
                        value: $spanCM,
                        field: .span,
                        valid: spanValid,
                        complaint: "That is outside 90 to 260 cm. Check the units."
                    )
                    apeIndex
                    whatItChanges
                    save
                }
                .padding(.bottom, 96)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
        .onAppear {
            imperial = store.body.usesImperial
            heightCM = store.body.heightCM
            spanCM = store.body.spanCM
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Personal info")
                .font(Theme.heading(22))
                .foregroundStyle(Theme.ink)
            Text("Both are optional. Trace works without them, it just reports distances in body lengths instead of metres.")
                .font(Theme.body(13.5))
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .padding(.horizontal, Theme.gutter).padding(.top, 12).padding(.bottom, 22)
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
                             field: Field, valid: Bool, complaint: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(Theme.ui(18, .bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(draft.describe(value.wrappedValue))
                    .font(Theme.mono(12, weight: .medium)).monospacedDigit()
                    .foregroundStyle(value.wrappedValue == nil ? Theme.ink3 : Theme.blue)
            }
            Text(help)
                .font(Theme.body(12.5))
                .foregroundStyle(Theme.ink3)

            if imperial {
                FeetInchesField(cm: value, focus: $focus, field: field, valid: valid)
            } else {
                CentimetresField(cm: value, focus: $focus, field: field, valid: valid)
            }

            if !valid {
                Text(complaint)
                    .font(Theme.body(12.5))
                    .foregroundStyle(Theme.ember[3])
                    .fixedSize(horizontal: false, vertical: true)
            }
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
                    .font(Theme.mono(17, weight: .medium)).monospacedDigit()
                    .foregroundStyle(Theme.blue)
            }
            .padding(16)
            .background(Theme.blueWash)
            .clipShape(RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous))
            .padding(.horizontal, Theme.gutter)
        }
    }

    // MARK: What it buys

    private var whatItChanges: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("What these change")
            effect(
                "Height",
                on: heightCM != nil,
                text: "Speeds on the overlay read in metres per second instead of body lengths. Trace estimates the scale from the frame where you were most extended, so treat it as close rather than exact."
            )
            effect(
                "Reach",
                on: spanCM != nil,
                text: "The dashed circle on the overlay becomes your actual reach. A hold outside it needs a shift of weight before it needs more strength."
            )
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 26)
        .padding(.bottom, 26)
    }

    private func effect(_ title: String, on: Bool, text: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14))
                .foregroundStyle(on ? Theme.accent : Theme.ink3)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.ui(13.5, .semibold))
                    .foregroundStyle(on ? Theme.ink : Theme.ink2)
                Text(text)
                    .font(Theme.body(12.5))
                    .foregroundStyle(Theme.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Save

    private var save: some View {
        VStack(spacing: 10) {
            FlatButton(title: "Save", filled: true) {
                store.updateBody(draft)
                focus = nil
                dismiss()
            }
            .opacity(heightValid && spanValid ? 1 : 0.4)
            .disabled(!(heightValid && spanValid))

            if !store.body.isEmpty {
                Button {
                    heightCM = nil; spanCM = nil
                    store.updateBody(BodyProfile(usesImperial: imperial))
                } label: {
                    Text("CLEAR BOTH")
                        .font(Theme.mono(10.5, weight: .medium))
                        .tracking(1.2)
                        .foregroundStyle(Theme.ink3)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.gutter)
    }
}

// MARK: - Metric entry

private struct CentimetresField: View {
    @Binding var cm: Double?
    @FocusState.Binding var focus: PersonalInfoScreen.Field?
    let field: PersonalInfoScreen.Field
    let valid: Bool

    @State private var text = ""

    var body: some View {
        HStack(spacing: 8) {
            TextField("", text: $text, prompt: Text("0").foregroundStyle(Theme.ink3))
                .font(Theme.mono(17, weight: .medium))
                .keyboardType(.numberPad)
                .focused($focus, equals: field)
                .onChange(of: text) { _, new in
                    cm = Double(new.filter(\.isNumber))
                }
            Text("cm")
                .font(Theme.mono(12))
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
        if !valid { return Theme.ember[3] }
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
                .font(Theme.mono(17, weight: .medium))
                .keyboardType(.decimalPad)
                .focused($focus, equals: field)
            Text(unit)
                .font(Theme.mono(12))
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
        if !valid { return Theme.ember[3] }
        return focus == field ? Theme.accent : .clear
    }
}
