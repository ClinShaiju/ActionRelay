import SwiftUI

struct ConfigView: View {
    @State private var config = AppConfig.load()

    var body: some View {
        NavigationStack {
            Form {
                Section("On press") {
                    Picker("Action", selection: $config.target) {
                        Text("Local notification").tag(DispatchTarget.notification)
                        Text("Webhook (POST)").tag(DispatchTarget.webhook)
                    }
                    if config.target == .webhook {
                        TextField("https://…", text: $config.webhookURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    }
                }

                Section {
                    stepperRow("Press max", value: $config.pressMaxMs, range: 100...600)
                    stepperRow("Hold min", value: $config.holdMinMs, range: 300...1500)
                    stepperRow("Double window", value: $config.doubleWindowMs, range: 150...600)
                } header: {
                    Text("Timing (ms)")
                } footer: {
                    Text("Classifier tunables (§8.1). Restart the listener to apply.")
                }

                Section {
                    Button("Save") { config.save() }
                }
            }
            .navigationTitle("Action")
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
