import SwiftUI

struct RootView: View {
    enum Tab: String, CaseIterable {
        case voice = "Voice", remote = "Remote", apps = "Apps", type = "Type"

        var symbol: String {
            switch self {
            case .voice: return "waveform"
            case .remote: return "appletvremote.gen4.fill"
            case .apps: return "square.grid.2x2.fill"
            case .type: return "keyboard"
            }
        }
    }

    @EnvironmentObject var tv: TV
    @EnvironmentObject var assistant: Assistant
    @State private var tab: Tab
    @State private var sheet: Sheet?
    @Environment(\.scenePhase) private var phase

    enum Sheet: String, Identifiable {
        case settings, history
        var id: String { rawValue }
    }

    init(tab: Tab = .voice) {
        _tab = State(initialValue: tab)
    }

    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 0) {
                Header(open: { sheet = $0 })
                    .padding(.horizontal, 22)
                    .padding(.top, 6)
                ZStack {
                    switch tab {
                    case .voice: VoiceView(speech: assistant.speech)
                    case .remote: RemoteView()
                    case .apps: AppsView()
                    case .type: KeyboardView()
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                TabBar(tab: $tab)
                    .padding(.bottom, 4)
            }
            StatusOverlay(open: { sheet = $0 })
            Banner()
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .settings: SettingsView().environmentObject(tv).environmentObject(assistant)
            case .history: HistoryView().environmentObject(assistant)
            }
        }
        .onAppear {
            assistant.start()
            wireRelay()
        }
        .onChange(of: assistant.link) { _ in wireRelay() }
        .onChange(of: phase) { phase in
            switch phase {
            case .active: assistant.start()
            case .background: assistant.stop()
            default: break
            }
        }
    }

    /// Buttons, typing and app launches go through the paired assistant whenever it is connected.
    private func wireRelay() {
        tv.relay = assistant.link == .ready ? { [weak assistant] obj in Task { @MainActor [weak assistant] in assistant?.sendRaw(obj) } } : nil
    }
}

private struct Header: View {
    @EnvironmentObject var tv: TV
    @EnvironmentObject var assistant: Assistant
    var open: (RootView.Sheet) -> Void
    @State private var confirmPower = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("WinkBox")
                    .font(.rounded(30, .bold))
                    .foregroundColor(.white)
                StatusLine()
            }
            Spacer()
            circleButton("clock.arrow.circlepath", tint: .white, label: "History") { open(.history) }
            circleButton("gearshape.fill", tint: .white, label: "Settings") { open(.settings) }
            if assistant.tv.awake {
                circleButton("power", tint: .danger, label: "Turn the TV off") { confirmPower = true }
            } else {
                circleButton("power", tint: .live, label: "Wake the TV") {
                    Haptics.success()
                    tv.press(.power)
                }
            }
        }
        .confirmationDialog("Turn the WinkBox off?", isPresented: $confirmPower, titleVisibility: .visible) {
            Button("Turn Off", role: .destructive) {
                Haptics.warning()
                tv.press(.power)
            }
        } message: {
            Text("It goes to standby. Tap the power button again to wake it.")
        }
    }

    private func circleButton(_ symbol: String, tint: Color, label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.gentle()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 44, height: 44)
                .glass(Circle())
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(label)
    }
}

struct StatusLine: View {
    @EnvironmentObject var assistant: Assistant

    var body: some View {
        Button {
            if case .offline = assistant.link { assistant.retryNow() }
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .shadow(color: color.opacity(0.9), radius: 4)
                Text(text)
                    .font(.rounded(13, .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    private var color: Color {
        switch assistant.link {
        case .ready: return !assistant.tv.awake ? .warn : assistant.tv.adb == "CONNECTED" ? .live : .warn
        case .searching, .connecting, .needsPairing: return .warn
        case .offline: return .danger
        }
    }

    private var text: String {
        switch assistant.link {
        case .searching: return "Looking for your TV\u{2026}"
        case .connecting: return "Connecting\u{2026}"
        case .needsPairing: return "Not paired \u{00B7} open Settings"
        case .ready:
            if !assistant.tv.awake { return "Standby \u{00B7} tap power" }
            return assistant.tv.adb == "CONNECTED" ? "Connected \u{00B7} WinkBox" : "Approve on the TV"
        case .offline: return "Offline \u{00B7} tap to retry"
        }
    }
}

private struct TabBar: View {
    @Binding var tab: RootView.Tab
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            ForEach(RootView.Tab.allCases, id: \.self) { t in
                Button {
                    Haptics.gentle()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { tab = t }
                } label: {
                    item(t, selected: tab == t)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .glass(Capsule())
        .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
    }

    private func item(_ t: RootView.Tab, selected: Bool) -> some View {
        let fg: Color = selected ? .black : Color.white.opacity(0.72)
        return HStack(spacing: 7) {
            Image(systemName: t.symbol).font(.system(size: 15, weight: .semibold))
            if selected {
                Text(t.rawValue).font(.rounded(15, .semibold))
            }
        }
        .foregroundColor(fg)
        .padding(.horizontal, selected ? 18 : 15)
        .frame(height: 46)
        .background {
            if selected {
                Capsule().fill(Color.white).matchedGeometryEffect(id: "tab", in: ns)
            }
        }
    }
}

/// What to do when the TV can't be reached or the phone isn't paired yet.
private struct StatusOverlay: View {
    @EnvironmentObject var assistant: Assistant
    var open: (RootView.Sheet) -> Void

    var body: some View {
        VStack {
            Spacer()
            switch assistant.link {
            case .needsPairing:
                card(symbol: "lock.shield.fill", tint: .warn, title: "Pair with your TV",
                     text: "Your TV will show a 6-digit code. Enter it here once, and only this phone can control it.") {
                    pill("Pair now", filled: true) {
                        open(.settings)
                        assistant.beginPairing()
                    }
                }
            case .offline:
                card(symbol: "wifi.exclamationmark", tint: .danger, title: "Can't reach your TV",
                     text: "Check the TV is on and this phone is on the same Wi-Fi. If its address changed, set it in Settings.") {
                    HStack(spacing: 10) {
                        pill("Try again", filled: true) { assistant.retryNow() }
                        pill("Settings", filled: false) { open(.settings) }
                    }
                }
            default:
                EmptyView()
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 74)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: assistant.link)
    }

    private func card<Actions: View>(symbol: String, tint: Color, title: String, text: String,
                                     @ViewBuilder actions: () -> Actions) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(tint)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(tint.opacity(0.16)))
                Text(title).font(.rounded(18, .bold)).foregroundColor(.white)
            }
            Text(text)
                .font(.rounded(14))
                .foregroundColor(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            actions()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
        .transition(.move(edge: .bottom).combined(with: .opacity))
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

/// A short message from the TV (a timer going off, a setting saved), shown at the top for a few seconds.
private struct Banner: View {
    @EnvironmentObject var assistant: Assistant

    var body: some View {
        VStack {
            if let n = assistant.notice {
                HStack(spacing: 10) {
                    Image(systemName: "bell.fill").font(.system(size: 14, weight: .bold)).foregroundColor(.accent)
                    Text(n).font(.rounded(15, .semibold)).foregroundColor(.white)
                }
                .padding(.horizontal, 18)
                .frame(height: 44)
                .glass(Capsule())
                .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: n) {
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    assistant.notice = nil
                }
            }
            Spacer()
        }
        .padding(.top, 8)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: assistant.notice)
        .allowsHitTesting(false)
    }
}

struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
