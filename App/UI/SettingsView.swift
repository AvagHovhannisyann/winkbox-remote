import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var tv: TV
    @EnvironmentObject var assistant: Assistant
    @Environment(\.dismiss) private var dismiss
    @State private var host = ""

    var body: some View {
        ZStack {
            Backdrop()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Text("Settings").font(.rounded(28, .bold)).foregroundColor(.white)
                        Spacer()
                        Button("Done") { dismiss() }
                            .buttonStyle(.plain)
                            .font(.rounded(17, .semibold))
                            .foregroundColor(.accent)
                    }

                    AssistantSettingsSection()

                    section("WinkBox address") {
                        HStack(spacing: 12) {
                            TextField("192.168.1.8", text: $host)
                                .textFieldStyle(.plain)
                                .font(.rounded(20, .medium))
                                .foregroundColor(.white)
                                .disableAutocorrection(true)
                                .numberPad()
                            Button {
                                Haptics.press()
                                assistant.host = host.trimmingCharacters(in: .whitespaces)
                                assistant.stop()
                                assistant.start()
                                dismiss()
                            } label: {
                                Text("Connect")
                                    .font(.rounded(15, .semibold))
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 16)
                                    .frame(height: 38)
                                    .background(Capsule().fill(Color.white))
                            }
                            .buttonStyle(PressScale())
                        }
                        Text("Found automatically on your Wi-Fi. Only needed if your router blocks that. The address is on the TV in Settings \u{2192} Network.")
                            .font(.rounded(13))
                            .foregroundColor(.white.opacity(0.5))
                    }

                    section("How it works") {
                        Text("Everything runs on the TV. This phone listens, turns your speech into text, and sends the words over your Wi-Fi to the assistant on the TV, which decides what to do and does it. Buttons and typing go the same way. Nothing goes through a computer.")
                            .font(.rounded(14))
                            .foregroundColor(.white.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("WinkBox Remote 2.0")
                        .font(.rounded(12, .medium))
                        .foregroundColor(.white.opacity(0.35))
                        .frame(maxWidth: .infinity)
                }
                .padding(22)
            }
        }
        .onAppear { host = assistant.host }
        .preferredColorScheme(.dark)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.rounded(12, .bold))
                .foregroundColor(.white.opacity(0.45))
            VStack(alignment: .leading, spacing: 10) { content() }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glass(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }
}
