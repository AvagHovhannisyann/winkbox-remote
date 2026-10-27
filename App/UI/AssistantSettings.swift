import SwiftUI
import Speech

/// The one-time pairing with the TV: it shows a 6-digit code that only someone in front of the TV can read.
/// Sits in one row of the Settings list, so every button in it is borderless (a list row with plain buttons fires them all).
struct PairingCard: View {
    @EnvironmentObject var assistant: Assistant
    @State private var code = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch assistant.pairing {
            case .none:
                if assistant.isPaired {
                    Label("Paired with your TV", systemImage: "checkmark.seal.fill").font(.body.weight(.semibold)).foregroundStyle(Color.live)
                    Text("Only phones you\u{2019}ve paired can talk to the assistant.").font(.subheadline).foregroundStyle(.secondary)
                    Button("Forget This Phone", role: .destructive) {
                        Haptics.warning()
                        assistant.forgetThisPhone()
                    }
                } else {
                    Text("Pair this phone with your TV so only you can control it.")
                        .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button {
                        Haptics.press()
                        assistant.beginPairing()
                    } label: {
                        Label("Show a Code on the TV", systemImage: "number.square")
                    }
                    .disabled(!assistant.canReach)
                }
            case .requesting:
                HStack(spacing: 10) { ProgressView(); Text("Asking the TV for a code\u{2026}").foregroundStyle(.secondary) }
            case .enterCode:
                Text("Enter the 6-digit code on your TV").font(.body.weight(.semibold))
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
                Button("Cancel") { assistant.cancelPairing() }
            case .verifying:
                HStack(spacing: 10) { ProgressView(); Text("Checking\u{2026}").foregroundStyle(.secondary) }
            }
            if let e = assistant.pairingError {
                Text(e).font(.footnote.weight(.medium)).foregroundStyle(Color.danger).fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 4)
        .animation(.easeOut(duration: 0.2), value: assistant.pairing)
    }

    /// Six boxes, like the iPhone's own verification codes.
    private var digits: some View {
        HStack(spacing: 8) {
            ForEach(0..<6, id: \.self) { i in
                let ch = i < code.count ? String(Array(code)[i]) : ""
                Text(ch)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .frame(width: 42, height: 54)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(i == code.count ? Color.accentColor : Color.white.opacity(0.1), lineWidth: i == code.count ? 2 : 1))
                if i == 2 { Capsule().fill(.secondary).frame(width: 9, height: 3) }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }
}

/// Everything about the assistant that you can change, as sections of the Settings list.
struct AssistantSettingsSection: View {
    @EnvironmentObject var assistant: Assistant
    @State private var apiKey = ""
    @State private var showKey = false

    private let models: [(String, String)] = [("Opus 5.5 \u{00B7} smartest", "claude-opus-5-5"), ("Sonnet 5.5 \u{00B7} faster", "claude-sonnet-5-5"),
                                              ("Haiku 5.5 \u{00B7} fastest", "claude-haiku-5-5")]
    private let efforts: [(String, String)] = [("Low", "low"), ("Medium", "medium"), ("High", "high")]

    var body: some View {
        Group {
            Section {
                status("TV link", symbol: "wifi", tint: .blue, value: linkText, color: linkColor)
                status("TV control", symbol: "appletvremote.gen4.fill", tint: Color(hex: 0x8E8E93), value: controlText,
                       color: assistant.tv.adb == "CONNECTED" ? .live : .warn)
                status("Assistant", symbol: "sparkles", tint: Color(hex: 0xBF5AF2), value: assistant.tv.brain ? "Ready" : "Needs an API key",
                       color: assistant.tv.brain ? .live : .warn)
            } header: {
                Text("Voice Assistant")
            } footer: {
                if assistant.tv.adb == "WAITING_APPROVAL" {
                    Text("Your TV is asking \u{201C}Allow USB debugging?\u{201D} for WinkBox Assistant. Tick \u{201C}Always allow\u{201D} and choose OK with the TV remote.")
                }
            }

            Section {
                PairingCard()
            } header: {
                Text("Pairing")
            }

            Section {
                HStack(spacing: 10) {
                    Group {
                        if showKey { TextField("sk-ant-\u{2026}", text: $apiKey) } else { SecureField("sk-ant-\u{2026}", text: $apiKey) }
                    }
                    .disableAutocorrection(true)
                    .noAutocapitalization()
                    Button { showKey.toggle() } label: {
                        Image(systemName: showKey ? "eye.slash" : "eye").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(showKey ? "Hide the key" : "Show the key")
                }
                Button("Save to TV") {
                    Haptics.press()
                    assistant.saveAPIKey(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
                    apiKey = ""
                    showKey = false
                }
                .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty || !assistant.isPaired || assistant.link != .ready)
                if assistant.tv.keySet {
                    Button("Remove from TV", role: .destructive) {
                        Haptics.warning()
                        assistant.saveAPIKey("")
                    }
                    .disabled(assistant.link != .ready)
                }
            } header: {
                Text("Anthropic API Key")
            } footer: {
                Text("The key travels to your TV encrypted, is stored there, and is never kept on this phone or written to any log.")
            }

            Section {
                Picker("Model", selection: $assistant.model) {
                    ForEach(models, id: \.1) { Text($0.0).tag($0.1) }
                }
                Picker("Thinking", selection: $assistant.effort) {
                    ForEach(efforts, id: \.1) { Text($0.0).tag($0.1) }
                }
                .pickerStyle(.segmented)
                Toggle("Fast mode", isOn: $assistant.fast)
            } header: {
                Text("Intelligence")
            } footer: {
                Text("Thinking: Medium is the default; lower answers faster, higher is for harder requests. Fast mode makes Opus answer noticeably faster, at twice the price (a research preview).")
            }
            // On this one section only: modifiers on the Group around the sections would be copied onto every section.
            .onChange(of: assistant.model) { _ in assistant.pushSettings() }
            .onChange(of: assistant.effort) { _ in assistant.pushSettings() }
            .onChange(of: assistant.fast) { _ in assistant.pushSettings() }

            Section {
                Picker("Language", selection: $assistant.language) {
                    ForEach(Self.locales, id: \.0) { Text($0.1).tag($0.0) }
                }
                Picker("Speak replies", selection: $assistant.speakMode) {
                    ForEach(Assistant.SpeakMode.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Voice")
            } footer: {
                Text("Speech is turned into text on your iPhone, on the device itself when your language supports it. Only the words go to the TV.")
            }

            Section {
                ForEach(assistant.favorites, id: \.self) { f in
                    item(f.name, f.query)
                }
                .onDelete { rows in
                    Haptics.warning()
                    for i in rows where i < assistant.favorites.count { assistant.say("remove \(assistant.favorites[i].name) from my favorites") }
                }
            } header: {
                Text("Favorites")
            } footer: {
                Text(assistant.favorites.isEmpty ? "Play something, then say \u{201C}add this to my favorites\u{201D}. Favorites become buttons on the Voice screen."
                                                 : "Swipe left on a favorite to remove it.")
            }

            Section {
                ForEach(assistant.routines, id: \.self) { r in
                    item(r, "Say \u{201C}run my \(r) routine\u{201D}")
                }
                .onDelete { rows in
                    Haptics.warning()
                    for i in rows where i < assistant.routines.count { assistant.say("delete the \(assistant.routines[i]) routine") }
                }
            } header: {
                Text("Routines")
            } footer: {
                Text(assistant.routines.isEmpty ? "A routine is a list of things to do in order. Tell the assistant: \u{201C}make a routine called movie night that mutes the TV and opens Plex\u{201D}."
                                                : "Swipe left on a routine to delete it.")
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
        case "WAITING_APPROVAL": return "Waiting for you"
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

    private func status(_ title: String, symbol: String, tint: Color, value: String, color: Color) -> some View {
        HStack(spacing: 12) {
            SettingsIcon(symbol: symbol, tint: tint)
            Text(title)
            Spacer(minLength: 8)
            Circle().fill(color).frame(width: 8, height: 8)
            Text(value).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private func item(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).lineLimit(1)
            Text(detail).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}
