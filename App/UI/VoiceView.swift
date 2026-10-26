import SwiftUI

/// Talk to the TV. Tap the orb to start (it stops when you pause), or hold it and let go when you're done.
struct VoiceView: View {
    @EnvironmentObject var assistant: Assistant
    @ObservedObject var speech: SpeechListener
    @State private var stateAt = Date()
    @State private var pressStart: Date?
    @State private var pressedPhase: Assistant.Phase = .idle
    @State private var hintIndex = 0

    private let hints = ["play some classic Italian music", "set a timer for ten minutes", "turn the volume to thirty",
                         "open YouTube", "pause", "what time is it", "mute it and set a timer for five minutes"]

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 6)
            transcript
                .frame(minHeight: 110)
                .padding(.horizontal, 26)
            orb
            statusLine
                .padding(.top, 2)
                .padding(.horizontal, 26)
            replyCard
                .padding(.top, 14)
                .padding(.horizontal, 22)
            Spacer(minLength: 4)
            chips
                .padding(.bottom, 10)
        }
        .onChange(of: assistant.phase) { _ in stateAt = Date() }
        .onReceive(Timer.publish(every: 4.5, on: .main, in: .common).autoconnect()) { _ in
            if assistant.phase == .idle { withAnimation(.easeInOut(duration: 0.5)) { hintIndex = (hintIndex + 1) % hints.count } }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: pieces

    private var transcript: some View {
        let idle = assistant.phase == .idle && assistant.transcript.isEmpty
        return Text(idle ? "\u{201C}\(hints[hintIndex])\u{201D}" : assistant.transcript.isEmpty ? " " : assistant.transcript)
            .font(.rounded(idle ? 22 : 30, .semibold))
            .foregroundColor(.white.opacity(idle ? 0.32 : 0.96))
            .multilineTextAlignment(.center)
            .lineLimit(4)
            .minimumScaleFactor(0.6)
            .id(idle ? "hint\(hintIndex)" : "live")
            .transition(.opacity)
            .animation(.easeOut(duration: 0.15), value: assistant.transcript)
    }

    private var orb: some View {
        OrbView(phase: assistant.phase, level: speech.level, stateAt: stateAt)
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 330, maxHeight: 330)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard pressStart == nil else { return }
                        pressStart = Date()
                        pressedPhase = assistant.phase
                        switch pressedPhase {
                        case .idle, .done, .asking: assistant.startListening(answering: pressedPhase == .asking)
                        default: break
                        }
                    }
                    .onEnded { _ in
                        let held = Date().timeIntervalSince(pressStart ?? Date())
                        pressStart = nil
                        switch pressedPhase {
                        case .listening, .thinking, .acting, .speaking: assistant.micTapped()
                        default: if held > 0.45 { assistant.holdReleased() }
                        }
                    }
            )
            .accessibilityLabel("Microphone")
            .accessibilityHint("Double tap and speak to the TV")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { assistant.micTapped() }
    }

    private var statusLine: some View {
        Text(statusText)
            .font(.rounded(15, .semibold))
            .foregroundColor(statusColor)
            .lineLimit(1)
            .frame(height: 22)
            .animation(.easeOut(duration: 0.2), value: statusText)
    }

    private var statusText: String {
        switch assistant.link {
        case .searching: return "Looking for your TV\u{2026}"
        case .connecting: return "Connecting\u{2026}"
        case .needsPairing: return "Pair with your TV in Settings"
        case .offline: return "Can't reach your TV"
        case .ready:
            switch assistant.phase {
            case .idle: return "Tap to talk"
            case .listening: return "Listening\u{2026}"
            case .thinking: return "Thinking\u{2026}"
            case .acting(let a): return Self.verb(a)
            case .speaking: return "Speaking\u{2026}"
            case .done(let ok): return ok ? "Done" : "Couldn't do that"
            case .asking: return "Tap and answer"
            }
        }
    }

    private var statusColor: Color {
        if case .done(let ok) = assistant.phase { return ok ? .live : .danger }
        if assistant.link != .ready { return .warn }
        return Color.white.opacity(0.55)
    }

    static func sourceName(_ source: String) -> String { source == "local" ? "On the TV" : "Cloud" }

    static func duration(_ ms: Int) -> String { ms < 1000 ? "\(ms) ms" : String(format: "%.1f s", Double(ms) / 1000) }

    static func verb(_ action: String) -> String {
        switch action {
        case "volume": return "Adjusting the volume"
        case "media": return "Controlling playback"
        case "navigate": return "Navigating"
        case "open_app": return "Opening the app"
        case "timer": return "Setting the timer"
        case "open_setting": return "Opening settings"
        case "power": return "Power"
        case "play_music": return "Finding your music"
        default: return "Working on it"
        }
    }

    @ViewBuilder
    private var replyCard: some View {
        if !assistant.reply.isEmpty, assistant.phase != .listening {
            VStack(alignment: .leading, spacing: 6) {
                Text(assistant.reply)
                    .font(.rounded(19, .semibold))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                if !assistant.alternative.isEmpty {
                    Text(assistant.alternative)
                        .font(.rounded(14))
                        .foregroundColor(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if assistant.lastMs > 0, case .done = assistant.phase {
                    HStack(spacing: 5) {
                        Image(systemName: assistant.lastSource == "local" ? "bolt.fill" : "cloud.fill").font(.system(size: 10, weight: .bold))
                        Text("\(Self.sourceName(assistant.lastSource)) \u{00B7} \(Self.duration(assistant.lastMs))")
                            .font(.rounded(11, .medium))
                    }
                    .foregroundColor(.white.opacity(0.38))
                    .padding(.top, 2)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: assistant.reply)
        }
    }

    @ViewBuilder
    private var chips: some View {
        let items: [String] = chipItems
        if !items.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(items, id: \.self) { item in
                        Button {
                            Haptics.press()
                            tapped(item)
                        } label: {
                            Text(item)
                                .font(.rounded(15, .semibold))
                                .foregroundColor(.white.opacity(0.9))
                                .padding(.horizontal, 16)
                                .frame(height: 40)
                                .glass(Capsule())
                        }
                        .buttonStyle(PressScale())
                    }
                }
                .padding(.horizontal, 22)
            }
            .transition(.opacity)
        }
    }

    private var chipItems: [String] {
        guard assistant.link == .ready else { return [] }
        switch assistant.phase {
        case .asking: return assistant.question?.options ?? []
        case .thinking, .acting: return ["Cancel"]
        case .listening: return []
        default: return ["Volume 30", "Pause", "Mute", "Open YouTube", "Timer 10 minutes", "Go home"]
        }
    }

    private func tapped(_ item: String) {
        if item == "Cancel" { assistant.cancelRequest() } else { assistant.say(item.lowercased()) }
    }
}

/// The orb: one shape that carries the state, drawn the same way as on the TV so the two feel like one product.
struct OrbView: View {
    let phase: Assistant.Phase
    let level: Float
    let stateAt: Date

    var body: some View {
        TimelineView(.animation) { ctx in
            Canvas { gc, size in draw(gc, size, ctx.date) }
        }
    }

    private func draw(_ gc: GraphicsContext, _ size: CGSize, _ date: Date) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let r = min(size.width, size.height) * 0.2
        let t = date.timeIntervalSinceReferenceDate
        let st = date.timeIntervalSince(stateAt)
        var g = gc

        switch phase {
        case .idle:
            let breathe = 1 + 0.035 * sin(t * 1.6)
            orb(&g, c, r * breathe, 0xFFC46B, 0xFF6A2C, 0xE5391B, glow: 0.55, dim: 0.78)
        case .listening:
            for k in 0..<3 {
                let p = (t * 0.55 + Double(k) / 3).truncatingRemainder(dividingBy: 1)
                ring(&g, c, r * (1.05 + 1.15 * p), Color(red: 1, green: 0.42, blue: 0.17).opacity((1 - p) * 0.4), 2)
            }
            orb(&g, c, r * (1 + 0.3 * CGFloat(level)), 0xFFC46B, 0xFF6A2C, 0xE5391B, glow: 1, dim: 1)
        case .thinking, .acting:
            let acting: Bool = { if case .acting = phase { return true } else { return false } }()
            ring(&g, c, r, .white.opacity(0.14), 3.5)
            var arc = Path()
            let a = t * (acting ? 620 : 310)
            arc.addArc(center: c, radius: r, startAngle: .degrees(a), endAngle: .degrees(a + 290), clockwise: false)
            g.stroke(arc, with: .conicGradient(Gradient(colors: [Color(red: 1, green: 0.42, blue: 0.17).opacity(0), Color(red: 1, green: 0.6, blue: 0.32)]),
                                               center: c, angle: .degrees(a)), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
            orb(&g, c, r * (acting ? 0.7 : 0.45 + 0.05 * sin(t * 5)), 0xFFC46B, 0xFF6A2C, 0xE5391B, glow: 0.8, dim: 1)
        case .speaking:
            for k in 0..<3 {
                let w = 0.5 + 0.5 * sin(t * (3 + Double(k)) + Double(k))
                ring(&g, c, r * (1.12 + 0.16 * CGFloat(k) * CGFloat(w)), Color(red: 1, green: 0.42, blue: 0.17).opacity(0.28 - Double(k) * 0.07), 2)
            }
            orb(&g, c, r * (1 + 0.05 * sin(t * 9)), 0xFFC46B, 0xFF6A2C, 0xE5391B, glow: 1, dim: 1)
        case .done(let ok):
            if ok {
                let spring = 1 - exp(-6 * st) * cos(14 * st)
                orb(&g, c, r * (0.55 + 0.45 * spring), 0x7BF0A5, 0x2FCB6A, 0x148A45, glow: 1, dim: 1)
                let p = max(0, min(1, (st - 0.08) / 0.3))
                var path = Path()
                path.move(to: CGPoint(x: c.x - 0.46 * r, y: c.y + 0.02 * r))
                path.addLine(to: CGPoint(x: c.x - 0.1 * r, y: c.y + 0.38 * r))
                path.addLine(to: CGPoint(x: c.x + 0.5 * r, y: c.y - 0.32 * r))
                g.stroke(path.trimmedPath(from: 0, to: p), with: .color(.white), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            } else {
                let shake = CGFloat(sin(st * 42) * exp(-st * 6)) * 8
                let cc = CGPoint(x: c.x + shake, y: c.y)
                orb(&g, cc, r, 0xFF8F80, 0xFF5A4A, 0xC93A2C, glow: 1, dim: 1)
                var bar = Path()
                bar.move(to: CGPoint(x: cc.x, y: cc.y - 0.46 * r))
                bar.addLine(to: CGPoint(x: cc.x, y: cc.y + 0.1 * r))
                g.stroke(bar, with: .color(.white), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                g.fill(Path(ellipseIn: CGRect(x: cc.x - 3.2, y: cc.y + 0.46 * r - 3.2, width: 6.4, height: 6.4)), with: .color(.white))
            }
        case .asking:
            orb(&g, c, r * (1 + 0.04 * sin(t * 4)), 0xB0A5FF, 0x7B6CF0, 0x4B3BC8, glow: 1, dim: 1)
            g.draw(Text("?").font(.system(size: r * 1.2, weight: .bold, design: .rounded)).foregroundColor(.white), at: CGPoint(x: c.x, y: c.y + r * 0.02))
        }
    }

    private func ring(_ g: inout GraphicsContext, _ c: CGPoint, _ radius: CGFloat, _ color: Color, _ width: CGFloat) {
        g.stroke(Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)), with: .color(color), lineWidth: width)
    }

    private func orb(_ g: inout GraphicsContext, _ c: CGPoint, _ r: CGFloat, _ c0: UInt32, _ c1: UInt32, _ c2: UInt32, glow: Double, dim: Double) {
        let glowRect = CGRect(x: c.x - r * 2.2, y: c.y - r * 2.2, width: r * 4.4, height: r * 4.4)
        g.fill(Path(ellipseIn: glowRect), with: .radialGradient(Gradient(colors: [Color(hex: c1, opacity: 0.34 * glow), Color(hex: c1, opacity: 0)]),
                                                                center: c, startRadius: 0, endRadius: r * 2.2))
        let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        g.fill(Path(ellipseIn: rect), with: .radialGradient(
            Gradient(colors: [Color(hex: c0, opacity: dim), Color(hex: c1, opacity: dim), Color(hex: c2, opacity: dim)]),
            center: CGPoint(x: c.x - r * 0.3, y: c.y - r * 0.35), startRadius: 0, endRadius: r * 1.5))
    }
}

/// What was asked and what happened, newest first. Tap one to do it again.
struct HistoryView: View {
    @EnvironmentObject var assistant: Assistant
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Backdrop()
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("History").font(.rounded(28, .bold)).foregroundColor(.white)
                    Spacer()
                    Button("Done") { dismiss() }
                        .buttonStyle(.plain)
                        .font(.rounded(17, .semibold))
                        .foregroundColor(.accent)
                }
                if assistant.entries.isEmpty {
                    Text("Nothing yet. Tap the orb and say something.")
                        .font(.rounded(16))
                        .foregroundColor(.white.opacity(0.55))
                        .padding(.top, 20)
                }
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(assistant.entries) { e in
                            Button {
                                Haptics.press()
                                dismiss()
                                assistant.say(e.said)
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: e.ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(e.ok ? .live : .danger)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(e.said).font(.rounded(17, .semibold)).foregroundColor(.white).multilineTextAlignment(.leading)
                                        Text(e.reply).font(.rounded(14)).foregroundColor(.white.opacity(0.6)).multilineTextAlignment(.leading)
                                        Text("\(VoiceView.sourceName(e.source)) \u{00B7} \(VoiceView.duration(e.ms))")
                                            .font(.rounded(11, .medium)).foregroundColor(.white.opacity(0.35))
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .glass(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                            .buttonStyle(PressScale())
                        }
                    }
                }
            }
            .padding(22)
        }
        .preferredColorScheme(.dark)
    }
}
