import SwiftUI

struct RootView: View {
    enum Tab: String, CaseIterable {
        case remote = "Remote", apps = "Apps", type = "Type"

        var symbol: String {
            switch self {
            case .remote: return "appletvremote.gen4.fill"
            case .apps: return "square.grid.2x2.fill"
            case .type: return "keyboard"
            }
        }
    }

    @EnvironmentObject var tv: TV
    @State private var tab: Tab
    @State private var showSettings = false
    @Environment(\.scenePhase) private var phase

    init(tab: Tab = .remote) {
        _tab = State(initialValue: tab)
    }

    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 0) {
                Header(showSettings: $showSettings)
                    .padding(.horizontal, 22)
                    .padding(.top, 6)
                ZStack {
                    switch tab {
                    case .remote: RemoteView()
                    case .apps: AppsView()
                    case .type: KeyboardView()
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                TabBar(tab: $tab)
                    .padding(.bottom, 4)
            }
            StatusOverlay(showSettings: $showSettings)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(tv)
        }
        .onAppear {
            if tv.autoConnect, !tv.isConnected { tv.connect() }
        }
        .onChange(of: phase) { phase in
            guard tv.autoConnect else { return }
            switch phase {
            case .active:
                if !tv.isConnected { tv.connect() }
            case .background:
                tv.disconnect()
            default:
                break
            }
        }
    }
}

private struct Header: View {
    @EnvironmentObject var tv: TV
    @Binding var showSettings: Bool
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
            circleButton("gearshape.fill", tint: .white) { showSettings = true }
            circleButton("power", tint: .danger) { confirmPower = true }
        }
        .confirmationDialog("Turn the WinkBox off?", isPresented: $confirmPower, titleVisibility: .visible) {
            Button("Turn Off", role: .destructive) {
                Haptics.warning()
                tv.press(.power)
            }
        } message: {
            Text("It goes to standby, the same as its own power button.")
        }
    }

    private func circleButton(_ symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
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
    }
}

struct StatusLine: View {
    @EnvironmentObject var tv: TV

    var body: some View {
        Button {
            if case .failed = tv.status { tv.connect() }
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
        switch tv.status {
        case .connected: return .live
        case .connecting, .needsApproval, .idle: return .warn
        case .failed: return .danger
        }
    }

    private var text: String {
        switch tv.status {
        case .idle: return "Not connected"
        case .connecting: return "Connecting…"
        case .needsApproval: return "Allow on your TV"
        case .connected(let name): return "Connected · \(name)"
        case .failed: return "Offline · tap to retry"
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
        .padding(.horizontal, selected ? 20 : 18)
        .frame(height: 46)
        .background {
            if selected {
                Capsule().fill(Color.white).matchedGeometryEffect(id: "tab", in: ns)
            }
        }
    }
}

/// Explains what to do when the TV asks to allow the app, or when the box can't be reached.
private struct StatusOverlay: View {
    @EnvironmentObject var tv: TV
    @Binding var showSettings: Bool

    var body: some View {
        VStack {
            Spacer()
            switch tv.status {
            case .needsApproval:
                card(symbol: "tv.inset.filled", tint: .warn, title: "Allow on your TV",
                     text: "Your TV asks “Allow USB debugging?”. Tick “Always allow from this computer”, then choose OK with the TV remote.") {
                    EmptyView()
                }
            case .failed(let why):
                card(symbol: "wifi.exclamationmark", tint: .danger, title: "Can't reach your WinkBox",
                     text: "\(why) Check the iPhone is on the home Wi-Fi and the box is on.") {
                    HStack(spacing: 10) {
                        pill("Try again", filled: true) { tv.connect() }
                        pill("Address", filled: false) { showSettings = true }
                    }
                }
            default:
                EmptyView()
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 74)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: tv.status)
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

struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
