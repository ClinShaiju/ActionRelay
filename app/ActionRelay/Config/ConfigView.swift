import SwiftUI

struct ConfigView: View {
    @State private var config = AppConfig.load()

    var body: some View {
        NavigationStack {
            Form {
                gestureSection("Single press", action: $config.press)
                gestureSection("Hold", action: $config.hold)
                gestureSection("Double press", action: $config.double)

                Section {
                    stepperRow("Press max", value: $config.pressMaxMs, range: 100...600)
                    stepperRow("Hold min", value: $config.holdMinMs, range: 300...1500)
                    stepperRow("Double window", value: $config.doubleWindowMs, range: 150...600)
                } header: {
                    Text("Timing (ms)")
                } footer: {
                    Text("Action changes apply on the next press. Timing changes need a listener restart (Stop → Start). Shortcuts run from the background via a private launch with a one-tap notification fallback; flashlight + media run with no tap.")
                }
            }
            .navigationTitle("Actions")
            // Auto-save: no Save button to forget. Action edits take effect on the
            // next press because the dispatcher reloads config each fire.
            .onChange(of: config) { _, newValue in newValue.save() }
        }
    }

    @ViewBuilder
    private func gestureSection(_ title: String, action: Binding<GestureAction>) -> some View {
        Section(title) {
            Picker("Action", selection: action.target) {
                ForEach(DispatchTarget.allCases) { Text($0.label).tag($0) }
            }
            if action.wrappedValue.target == .shortcut {
                TextField("Shortcut name (exact)", text: action.shortcutName)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            if action.wrappedValue.target == .webhook {
                TextField("https://…", text: action.webhookURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            }
        }
    }

    private func stepperRow(_ title: String, value: Binding<UInt64>,
                            range: ClosedRange<UInt64>) -> some View {
        Stepper(value: Binding(
            get: { Int(value.wrappedValue) },
            set: { value.wrappedValue = UInt64($0) }
        ), in: Int(range.lowerBound)...Int(range.upperBound), step: 25) {
            HStack { Text(title); Spacer(); Text("\(value.wrappedValue)").foregroundStyle(.secondary) }
        }
    }
}
