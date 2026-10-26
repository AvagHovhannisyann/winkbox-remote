import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var tv: TV
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

                    section("WinkBox address") {
                        HStack(spacing: 12) {
                            TextField("192.168.1.8", text: $host)
                                .textFieldStyle(.plain)
                                .font(.rounded(20, .medium))
                                .foregroundColor(.white)
                                .disableAutocorrection(true)
                                .numbersKeyboard()
                            Button {
                                Haptics.press()
                                tv.host = host.trimmingCharacters(in: .whitespaces)
                                tv.connect()
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
                        Text("Shown on the TV in Settings → Network. The box keeps it unless the router changes it.")
                            .font(.rounded(13))
                            .foregroundColor(.white.opacity(0.5))
                    }

                    section("Status") {
                        StatusLine()
                    }

                    section("First connection") {
                        Text("The TV asks “Allow USB debugging?” the first time. Tick “Always allow from this computer” and choose OK with the TV remote. If you chose Cancel, open the app again to get the question back.")
                            .font(.rounded(14))
                            .foregroundColor(.white.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    section("How it works") {
                        Text("The app talks to the box directly over your Wi-Fi, through the debugging connection the box has switched on (ADB, port 5555). Button presses go straight into the box's own remote-control input, so they arrive instantly. Nothing goes through the internet.")
                            .font(.rounded(14))
                            .foregroundColor(.white.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("WinkBox Remote 1.0")
                        .font(.rounded(12, .medium))
                        .foregroundColor(.white.opacity(0.35))
                        .frame(maxWidth: .infinity)
                }
                .padding(22)
            }
        }
        .onAppear { host = tv.host }
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

extension View {
    @ViewBuilder
    func numbersKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.decimalPad)
        #else
        self
        #endif
    }
}
