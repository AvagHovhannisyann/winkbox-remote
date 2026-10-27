import SwiftUI

/// Settings, laid out like the iPhone's own Settings app: a grouped list under a large title, with Done at the top.
struct SettingsView: View {
    @EnvironmentObject var tv: TV
    @EnvironmentObject var assistant: Assistant
    @Environment(\.dismiss) private var dismiss
    @State private var host = ""

    var body: some View {
        NavigationShell {
            Form {
                AssistantSettingsSection()

                Section {
                    HStack(spacing: 12) {
                        SettingsIcon(symbol: "network", tint: Color(hex: 0x30D158))
                        TextField("192.168.1.8", text: $host)
                            .disableAutocorrection(true)
                            .numberPad()
                        Button("Connect") {
                            Haptics.press()
                            assistant.host = host.trimmingCharacters(in: .whitespaces)
                            assistant.stop()
                            assistant.start()
                            dismiss()
                        }
                        .buttonStyle(.borderless)
                        .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("WinkBox Address")
                } footer: {
                    Text("Found automatically on your Wi-Fi; only needed if your router blocks that. The address is on the TV in Settings \u{2192} Network.")
                }

                Section {
                    Text("Everything runs on the TV. This phone listens, turns your speech into text, and sends the words over your Wi-Fi to the assistant on the TV, which decides what to do and does it. Buttons and typing go the same way. Nothing goes through a computer.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text("How It Works")
                } footer: {
                    Text("WinkBox Remote 3.0").frame(maxWidth: .infinity).padding(.top, 14)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .onAppear { host = assistant.host }
        .preferredColorScheme(.dark)
    }
}
