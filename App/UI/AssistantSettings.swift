import SwiftUI
import Speech

/// The one-time pairing with the TV: it shows a 6-digit code that only someone in front of the TV can read.
struct PairingCard: View {
    @EnvironmentObject var assistant: Assistant
    @State private var code = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch assistant.pairing {
            case .none:
                if assistant.isPaired {
                    Label("Paired with your TV", systemImage: "checkmark.seal.fill").font(.rounded(17, .semibold)).foregroundColor(.live)
                    Text("Only phones you've paired can talk to the assistant.")
                        .font(.rounded(14)).foregroundColor(.white.opacity(0.6))
                    pill("Forget this phone", filled: false) { assistant.forgetThisPhone() }
                } else {
                    Text("Pair this phone with your TV so only you can control it.")
                        .font(.rounded(15)).foregroundColor(.white.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
                    pill("Show a code on the TV", filled: true) { assistant.beginPairing() }
                        .disabled(!assistant.canReach)
                }
            case .requesting:
                Text("Asking the TV for a code\u{2026}").font(.rounded(15)).foregroundColor(.white.opacity(0.7))
            case .enterCode:
                Text("Enter the 6-digit code on your TV").font(.rounded(15, .semibold)).foregroundColor(.white)
                digits
                TextField("", text: $code)
                    .numberPad(oneTimeCode: true)
                    .focused($focused)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .onChange(of: code) { value in
                        let digitsOnly = String(value.filter(\.isNumber).prefix(6))
                        if digitsOnly != value { code = digitsOnly }
                        if digitsOnly.count == 6 {
                            assistant.finishPairing(code: digitsOnly)
                            code = ""
                        }
                    }
                    .onAppear { focused = true }
                pill("Cancel", filled: false) { assistant.cancelPairing() }
            case .verifying:
                Text("Checking\u{2026}").font(.rounded(15)).foregroundColor(.white.opacity(0.7))
            }
            if let e = assistant.pairingError {
                Text(e).font(.rounded(13, .medium)).foregroundColor(.danger).fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(.easeOut(duration: 0.2), value: assistant.pairing)
    }

    private var digits: some View {
        HStack(spacing: 8) {
            ForEach(0..<6, id: \.self) { i in
                let ch = i < code.count ? String(Array(code)[i]) : ""
                Text(ch)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 56)
                    .glass(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(i == code.count ? Color.accent : .clear, lineWidth: 2))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }

    private func pill(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.press()
            action()
        } label: {
            Text(title)
                .font(.rounded(15, .semibold))
                .foregroundColor(filled ? .black : .white)
                .padding(.horizontal, 18)
                .frame(height: 40)
                .background(Capsule().fill(filled ? Color.white : Color.white.opacity(0.12)))
        }
        .buttonStyle(PressScale())
    }
}

/// Everything about the assistant that you can change.
struct AssistantSettingsSection: View {
    @EnvironmentObject var assistant: Assistant
    @State private var apiKey = ""
    @State private var showKey = false

    private let models: [(String, String)] = [("Opus 5.5 \u{00B7} smartest", "claude-opus-5-5"), ("Sonnet 5.5 \u{00B7} faster", "claude-sonnet-5-5"),
                                              ("Haiku 5.5 \u{00B7} fastest", "claude-haiku-5-5")]
    private let efforts: [(String, String)] = [("Low", "low"), ("Medium", "medium"), ("High", "high")]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            card("Voice assistant") {
                row("TV link", linkText, linkColor)
                row("TV control", controlText, assistant.tv.adb == "CONNECTED" ? .live : .warn)
                row("Assistant brain", assistant.tv.brain ? "Ready" : "Needs an API key", assistant.tv.brain ? .live : .warn)
                if assistant.tv.adb == "WAITING_APPROVAL" {
                    note("Your TV is asking \u{201C}Allow USB debugging?\u{201D} for WinkBox Assistant. Tick \u{201C}Always allow\u{201D} and choose OK with the TV remote.")
                }
            }
            card("Pairing") { PairingCard() }
            card("Anthropic API key") {
                HStack(spacing: 10) {
                    Group {
                        if showKey { TextField("sk-ant-\u{2026}", text: $apiKey) } else { SecureField("sk-ant-\u{2026}", text: $apiKey) }
                    }
                    .textFieldStyle(.plain)
                    .font(.rounded(17, .medium))
                    .foregroundColor(.white)
                    .disableAutocorrection(true)
                    .noAutocapitalization()
                    Button { showKey.toggle() } label: {
                        Image(systemName: showKey ? "eye.slash" : "eye").foregroundColor(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.08)))
                HStack {
                    pill("Save to TV", filled: true) {
                        assistant.saveAPIKey(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
                        apiKey = ""
                        showKey = false
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty || !assistant.isPaired || assistant.link != .ready)
                    if assistant.tv.keySet {
                        pill("Remove from TV", filled: false) { assistant.saveAPIKey("") }.disabled(assistant.link != .ready)
                    }
                }
                note("The key travels to your TV encrypted, is stored there, and is never kept on this phone or written to any log.")
            }
            card("Intelligence") {
                Picker("Model", selection: $assistant.model) {
                    ForEach(models, id: \.1) { Text($0.0).tag($0.1) }
                }
                .pickerStyle(.menu)
                .tint(.white)
                .onChange(of: assistant.model) { _ in assistant.pushSettings() }
                Picker("Thinking", selection: $assistant.effort) {
                    ForEach(efforts, id: \.1) { Text($0.0).tag($0.1) }
                }
                .pickerStyle(.segmented)
                .onChange(of: assistant.effort) { _ in assistant.pushSettings() }
                note("Medium is the default. Lower thinks less and answers faster; higher is for harder requests.")
                Toggle(isOn: $assistant.fast) {
                    Text("Fast mode").font(.rounded(16, .semibold)).foregroundColor(.white)
                }
                .tint(.accent)
                .onChange(of: assistant.fast) { _ in assistant.pushSettings() }
                note("Opus answers noticeably faster, at twice the price. Anthropic calls it a research preview.")
            }
            card("Voice") {
                Picker("Language", selection: $assistant.language) {
                    ForEach(Self.locales, id: \.0) { Text($0.1).tag($0.0) }
                }
                .pickerStyle(.menu)
                .tint(.white)
                Picker("Speak replies", selection: $assistant.speakMode) {
                    ForEach(Assistant.SpeakMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .tint(.white)
                note("Speech is turned into text on your iPhone, on the device itself when your language supports it. Only the words go to the TV.")
            }
        }
    }

    private var linkText: String {
        switch assistant.link {
        case .searching: return "Searching"
        case .connecting: return "Connecting"
        case .needsPairing: return "Not paired"
        case .ready: return "Connected"
        case .offline: return "Offline"
        }
    }

    private var linkColor: Color { assistant.link == .ready ? .live : assistant.link == .needsPairing ? .warn : .danger }

    private var controlText: String {
        switch assistant.tv.adb {
        case "CONNECTED": return "Allowed"
        case "WAITING_APPROVAL": return "Waiting for you on the TV"
        default: return "Not connected"
        }
    }

    /// Languages Apple can recognise on this phone, by name.
    static let locales: [(String, String)] = {
        let current = Locale(identifier: "en_US")
        return SFSpeechRecognizer.supportedLocales()
            .map { ($0.identifier.replacingOccurrences(of: "_", with: "-"), current.localizedString(forIdentifier: $0.identifier) ?? $0.identifier) }
            .sorted { $0.1 < $1.1 }
    }()

    // MARK: pieces

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased()).font(.rounded(12, .bold)).foregroundColor(.white.opacity(0.45))
            VStack(alignment: .leading, spacing: 12) { content() }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glass(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private func row(_ title: String, _ value: String, _ color: Color) -> some View {
        HStack {
            Text(title).font(.rounded(16, .semibold)).foregroundColor(.white)
            Spacer()
            Circle().fill(color).frame(width: 8, height: 8)
            Text(value).font(.rounded(15)).foregroundColor(.white.opacity(0.65))
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.rounded(13)).foregroundColor(.white.opacity(0.5)).fixedSize(horizontal: false, vertical: true)
    }

    private func pill(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.press()
            action()
        } label: {
            Text(title)
                .font(.rounded(15, .semibold))
                .foregroundColor(filled ? .black : .white)
                .padding(.horizontal, 18)
                .frame(height: 40)
                .background(Capsule().fill(filled ? Color.white : Color.white.opacity(0.12)))
        }
        .buttonStyle(PressScale())
    }
}
