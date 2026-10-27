import SwiftUI

/// The remote: a touch surface (or classic arrows) above the buttons of a Siri Remote.
struct RemoteView: View {
    @EnvironmentObject var tv: TV
    @AppStorage("padMode") private var padMode = "touch"

    /// The keys keep their size; the pad takes what's left, so everything fits from an SE to a Pro Max.
    private func layout(_ size: CGSize) -> (key: CGFloat, spacing: CGFloat, pad: CGFloat) {
        let key: CGFloat = size.height < 600 ? 56 : 62
        let spacing: CGFloat = 14
        let picker: CGFloat = 10 + 30 + 16
        let keys: CGFloat = key * 3 + spacing * 2
        let fixed: CGFloat = picker + 18 + keys + 8
        let pad: CGFloat = max(180, min(320, size.width - 48, size.height - fixed))
        return (key, spacing, pad)
    }

    var body: some View {
        GeometryReader { geo in
            let l = layout(geo.size)
            let key = l.key, spacing = l.spacing, pad = l.pad
            VStack(spacing: 0) {
                ModePicker(mode: $padMode)
                    .padding(.bottom, 16)
                ZStack {
                    if padMode == "arrows" {
                        DPad().transition(.opacity.combined(with: .scale(scale: 0.96)))
                    } else {
                        ClickPad().transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
                .frame(width: pad, height: pad)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: padMode)
                .padding(.bottom, 18)
                Keys(size: key, spacing: spacing)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
        }
    }
}

private struct ModePicker: View {
    @Binding var mode: String

    var body: some View {
        HStack(spacing: 2) {
            item("hand.point.up.left.fill", "Touch", "touch")
            item("dpad.fill", "Arrows", "arrows")
        }
        .padding(3)
        .glass(Capsule())
    }

    private func item(_ symbol: String, _ title: String, _ value: String) -> some View {
        Button {
            Haptics.gentle()
            mode = value
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11, weight: .bold))
                Text(title).font(.sf(13, .semibold))
            }
            .foregroundColor(mode == value ? .black : .white.opacity(0.7))
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(Capsule().fill(mode == value ? Color.white : Color.clear))
        }
        .buttonStyle(.plain)
    }
}

/// Swipe to move focus, tap to select, tap an edge to click that way, hold to long-press: the Siri Remote's clickpad.
struct ClickPad: View {
    @EnvironmentObject var tv: TV
    @State private var touch: CGPoint?
    @State private var anchor = CGPoint.zero
    @State private var moved = false
    @State private var flash: RemoteKey?
    @State private var selectGlow = false
    @State private var longPress: DispatchWorkItem?
    @State private var holding = false

    private let step: CGFloat = 34
    private let corner: CGFloat = 46

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
            ZStack {
                shape.fill(LinearGradient(colors: [Color.panelTop, Color.panel], startPoint: .top, endPoint: .bottom))
                if let p = touch {
                    RadialGradient(colors: [Color.white.opacity(0.17), Color.white.opacity(0.04), .clear],
                                   center: UnitPoint(x: p.x / size.width, y: p.y / size.height),
                                   startRadius: 0, endRadius: 150)
                        .clipShape(shape)
                        .transition(.opacity)
                }
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.03)],
                                                  startPoint: .top, endPoint: .bottom), lineWidth: 1)

                chevron(.up).position(x: size.width / 2, y: 28)
                chevron(.down).position(x: size.width / 2, y: size.height - 28)
                chevron(.left).position(x: 28, y: size.height / 2)
                chevron(.right).position(x: size.width - 28, y: size.height / 2)

                Circle()
                    .strokeBorder(Color.white.opacity(selectGlow ? 0.55 : 0.12), lineWidth: selectGlow ? 2 : 1.2)
                    .frame(width: 76, height: 76)
                    .scaleEffect(selectGlow ? 1.18 : 1)
                    .shadow(color: .white.opacity(selectGlow ? 0.35 : 0), radius: 12)
                Circle()
                    .fill(Color.white.opacity(selectGlow ? 0.5 : 0.18))
                    .frame(width: 7, height: 7)

                if touch == nil {
                    Text("Swipe to move · Tap to select")
                        .font(.sf(12, .medium))
                        .foregroundColor(.white.opacity(0.28))
                        .position(x: size.width / 2, y: size.height / 2 + 62)
                }
            }
            .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
            .contentShape(shape)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { changed($0) }
                    .onEnded { ended($0, size) }
            )
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func chevron(_ key: RemoteKey) -> some View {
        let lit = flash == key
        return Image(systemName: Self.symbol(key))
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(lit ? .white : .white.opacity(0.28))
            .scaleEffect(lit ? 1.4 : 1)
            .shadow(color: lit ? Color.white.opacity(0.8) : .clear, radius: 10)
    }

    static func symbol(_ key: RemoteKey) -> String {
        switch key {
        case .up: return "chevron.up"
        case .down: return "chevron.down"
        case .left: return "chevron.left"
        default: return "chevron.right"
        }
    }

    private func changed(_ v: DragGesture.Value) {
        if touch == nil {
            withAnimation(.easeOut(duration: 0.12)) { touch = v.location }
            anchor = v.location
            moved = false
            let work = DispatchWorkItem {
                guard !moved else { return }
                holding = true
                Haptics.click()
                tv.hold(.select, down: true)
                withAnimation(.easeOut(duration: 0.2)) { selectGlow = true }
            }
            longPress = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
        touch = v.location
        let dx = v.location.x - anchor.x
        let dy = v.location.y - anchor.y
        if !moved, max(abs(dx), abs(dy)) > 9 {
            moved = true
            longPress?.cancel()
        }
        guard !holding, max(abs(dx), abs(dy)) >= step else { return }
        if abs(dx) > abs(dy) {
            fire(dx > 0 ? .right : .left)
            anchor = CGPoint(x: anchor.x + (dx > 0 ? step : -step), y: v.location.y)
        } else {
            fire(dy > 0 ? .down : .up)
            anchor = CGPoint(x: v.location.x, y: anchor.y + (dy > 0 ? step : -step))
        }
    }

    private func ended(_ v: DragGesture.Value, _ size: CGSize) {
        longPress?.cancel()
        withAnimation(.easeOut(duration: 0.3)) { touch = nil }
        if holding {
            holding = false
            tv.hold(.select, down: false)
            withAnimation(.easeOut(duration: 0.3)) { selectGlow = false }
            return
        }
        if !moved {
            // A tap near an edge clicks that way, like pressing the rim of the Siri Remote; elsewhere it selects.
            let ex = v.location.x / size.width - 0.5
            let ey = v.location.y / size.height - 0.5
            if max(abs(ex), abs(ey)) > 0.33 {
                fire(abs(ex) > abs(ey) ? (ex > 0 ? .right : .left) : (ey > 0 ? .down : .up), click: true)
            } else {
                Haptics.click()
                tv.press(.select)
                withAnimation(.easeOut(duration: 0.08)) { selectGlow = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.easeOut(duration: 0.35)) { selectGlow = false }
                }
            }
            return
        }
        // A quick flick carries on for a few more steps, for long rows and lists.
        let vx = v.predictedEndLocation.x - v.location.x
        let vy = v.predictedEndLocation.y - v.location.y
        let extra = Int(min(4, max(abs(vx), abs(vy)) / 110))
        guard extra > 0 else { return }
        let key: RemoteKey = abs(vx) > abs(vy) ? (vx > 0 ? .right : .left) : (vy > 0 ? .down : .up)
        for i in 1...extra {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08 * Double(i)) { fire(key) }
        }
    }

    private func fire(_ key: RemoteKey, click: Bool = false) {
        if click { Haptics.click() } else { Haptics.step() }
        tv.press(key)
        withAnimation(.easeOut(duration: 0.08)) { flash = key }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.easeOut(duration: 0.35)) {
                if flash == key { flash = nil }
            }
        }
    }
}

/// Classic arrows around an OK button; holding an arrow repeats, holding OK long-presses.
struct DPad: View {
    @EnvironmentObject var tv: TV
    @State private var pressed: RemoteKey?

    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            ZStack {
                Circle().fill(LinearGradient(colors: [Color.panelTop, Color.panel], startPoint: .top, endPoint: .bottom))
                Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.03)],
                                                     startPoint: .top, endPoint: .bottom), lineWidth: 1)
                ForEach([RemoteKey.up, .right, .down, .left], id: \.self) { key in
                    Wedge(angle: Self.angle(key))
                        .fill(Color.white.opacity(pressed == key ? 0.10 : 0))
                    Image(systemName: ClickPad.symbol(key))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(pressed == key ? .white : .white.opacity(0.75))
                        .shadow(color: pressed == key ? Color.white.opacity(0.7) : .clear, radius: 8)
                        .offset(x: cos(Self.angle(key) * .pi / 180) * d * 0.355,
                                y: sin(Self.angle(key) * .pi / 180) * d * 0.355)
                }
                Text("OK")
                    .font(.sf(21, .bold))
                    .foregroundColor(.white)
                    .frame(width: d * 0.38, height: d * 0.38)
                    .glass(Circle(), pressed: pressed == .select)
                    .scaleEffect(pressed == .select ? 0.94 : 1)
                    .shadow(color: .black.opacity(0.45), radius: 10, y: 5)
            }
            .frame(width: d, height: d)
            .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let key = segment(at: v.location, diameter: d)
                        guard key != pressed else { return }
                        if let old = pressed { tv.hold(old, down: false) }
                        withAnimation(.easeOut(duration: 0.1)) { pressed = key }
                        if let key = key {
                            if key == .select { Haptics.click() } else { Haptics.step() }
                            tv.hold(key, down: true)
                        }
                    }
                    .onEnded { _ in
                        if let old = pressed { tv.hold(old, down: false) }
                        withAnimation(.easeOut(duration: 0.25)) { pressed = nil }
                    }
            )
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    static func angle(_ key: RemoteKey) -> Double {
        switch key {
        case .up: return -90
        case .right: return 0
        case .down: return 90
        default: return 180
        }
    }

    private func segment(at p: CGPoint, diameter d: CGFloat) -> RemoteKey? {
        let x = p.x - d / 2
        let y = p.y - d / 2
        let r = (x * x + y * y).squareRoot()
        if r < d * 0.19 { return .select }
        if r > d * 0.52 { return nil }
        return abs(x) > abs(y) ? (x > 0 ? .right : .left) : (y > 0 ? .down : .up)
    }
}

/// A quarter of the ring around OK, centred on `angle` degrees.
private struct Wedge: Shape {
    var angle: Double

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2 - 2
        let inner = outer * 0.42
        var p = Path()
        p.addArc(center: c, radius: outer, startAngle: .degrees(angle - 43), endAngle: .degrees(angle + 43), clockwise: false)
        p.addArc(center: c, radius: inner, startAngle: .degrees(angle + 43), endAngle: .degrees(angle - 43), clockwise: true)
        p.closeSubpath()
        return p
    }
}

/// Back, TV, play/pause and mute, with the volume rocker alongside.
private struct Keys: View {
    @EnvironmentObject var tv: TV
    let size: CGFloat
    let spacing: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: size * 0.42) {
            VStack(spacing: spacing) {
                key("chevron.backward", .back)
                key("playpause.fill", .playPause)
                key("speaker.slash.fill", .mute)
            }
            VStack(spacing: spacing) {
                key("tv", .home)
                VolumeRocker(width: size, height: size * 2 + spacing)
            }
            VStack(spacing: spacing) {
                key("line.3.horizontal", .menu)
                key("backward.fill", .rewind)
                key("forward.fill", .fastForward)
            }
        }
    }

    private func key(_ symbol: String, _ key: RemoteKey) -> some View {
        RoundKey(symbol: symbol, size: size, onDown: {
            Haptics.press()
            tv.hold(key, down: true)
        }, onUp: {
            tv.hold(key, down: false)
        })
    }
}

private struct VolumeRocker: View {
    @EnvironmentObject var tv: TV
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            half("plus", .volumeUp)
            Rectangle().fill(Color.white.opacity(0.10)).frame(width: 26, height: 1)
            half("minus", .volumeDown)
        }
        .frame(width: width, height: height)
        .glass(Capsule())
        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
    }

    private func half(_ symbol: String, _ key: RemoteKey) -> some View {
        HoldButton(onDown: {
            Haptics.press()
            tv.hold(key, down: true)
        }, onUp: {
            tv.hold(key, down: false)
        }) { pressed in
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white.opacity(pressed ? 1 : 0.9))
                .frame(width: width, height: (height - 1) / 2)
                .background(Color.white.opacity(pressed ? 0.12 : 0))
        }
    }
}
