import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xff) / 255, green: Double(hex >> 8 & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255, opacity: opacity)
    }

    static let ink = Color(hex: 0x07080C)
    static let panel = Color(hex: 0x15161C)
    static let panelTop = Color(hex: 0x1D1E26)
    static let accent = Color(hex: 0xFF6A2C)        // the orange of Wink's chevron
    static let live = Color(hex: 0x34D399)
    static let warn = Color(hex: 0xFBBF24)
    static let danger = Color(hex: 0xFF453A)
}

extension Font {
    /// SF Pro, the iPhone's own typeface, at a fixed size.
    static func sf(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

/// Haptics for presses and swipe steps; silent on the Mac preview build.
enum Haptics {
    #if os(iOS)
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let notify = UINotificationFeedbackGenerator()
    #endif

    static func step() {
        #if os(iOS)
        light.impactOccurred(intensity: 0.7)
        #endif
    }

    static func press() {
        #if os(iOS)
        medium.impactOccurred()
        #endif
    }

    static func click() {
        #if os(iOS)
        rigid.impactOccurred()
        #endif
    }

    static func gentle() {
        #if os(iOS)
        soft.impactOccurred()
        #endif
    }

    static func success() {
        #if os(iOS)
        notify.notificationOccurred(.success)
        #endif
    }

    static func warning() {
        #if os(iOS)
        notify.notificationOccurred(.warning)
        #endif
    }
}

/// The deep, softly lit backdrop behind every screen.
struct Backdrop: View {
    var body: some View {
        ZStack {
            Color.ink
            RadialGradient(colors: [Color(hex: 0x3B2FA8, opacity: 0.45), .clear],
                           center: UnitPoint(x: 0.15, y: 0.0), startRadius: 0, endRadius: 420)
            RadialGradient(colors: [Color(hex: 0x0E7C86, opacity: 0.28), .clear],
                           center: UnitPoint(x: 1.0, y: 0.75), startRadius: 0, endRadius: 380)
            RadialGradient(colors: [Color(hex: 0xFF6A2C, opacity: 0.10), .clear],
                           center: UnitPoint(x: 0.0, y: 1.0), startRadius: 0, endRadius: 300)
        }
        .ignoresSafeArea()
    }
}

/// Liquid Glass on iOS 26 (the system's own material, which lights up under a finger); before that, a frosted surface with a
/// hairline highlight along its top edge.
struct GlassSurface<S: InsettableShape>: ViewModifier {
    var shape: S
    var pressed = false

    func body(content: Content) -> some View {
        #if compiler(>=6.2) && os(iOS)
        if #available(iOS 26.0, *) {
            content.glassEffect(pressed ? .regular.tint(.white.opacity(0.14)).interactive() : .regular.interactive(), in: shape)
        } else {
            frosted(content)
        }
        #else
        frosted(content)
        #endif
    }

    private func frosted(_ content: Content) -> some View {
        content
            .background(
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(LinearGradient(colors: [Color.white.opacity(pressed ? 0.16 : 0.07),
                                                       Color.white.opacity(pressed ? 0.10 : 0.02)],
                                              startPoint: .top, endPoint: .bottom))
                    shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0.04)],
                                                      startPoint: .top, endPoint: .bottom), lineWidth: 1)
                }
            )
            .clipShape(shape)
    }
}

extension View {
    func glass<S: InsettableShape>(_ shape: S, pressed: Bool = false) -> some View {
        modifier(GlassSurface(shape: shape, pressed: pressed))
    }
}

/// A button that reports touch-down and touch-up, so holding repeats like a real remote.
struct HoldButton<Label: View>: View {
    var onDown: () -> Void
    var onUp: () -> Void
    @ViewBuilder var label: (Bool) -> Label
    @State private var pressed = false

    var body: some View {
        label(pressed)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !pressed {
                            pressed = true
                            onDown()
                        }
                    }
                    .onEnded { _ in
                        pressed = false
                        onUp()
                    }
            )
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: pressed)
    }
}

/// Round glass key with an SF Symbol.
struct RoundKey: View {
    let symbol: String
    var size: CGFloat = 66
    var tint: Color = .white
    var onDown: () -> Void
    var onUp: () -> Void

    var body: some View {
        HoldButton(onDown: onDown, onUp: onUp) { pressed in
            Image(systemName: symbol)
                .font(.system(size: size * 0.32, weight: .semibold))
                .foregroundColor(tint.opacity(pressed ? 1 : 0.9))
                .frame(width: size, height: size)
                .glass(Circle(), pressed: pressed)
                .scaleEffect(pressed ? 0.92 : 1)
                .shadow(color: .black.opacity(0.35), radius: pressed ? 2 : 8, y: pressed ? 1 : 4)
        }
    }
}

/// iPhone text-entry hints that don't exist in the Mac preview build.
extension View {
    @ViewBuilder func numberPad(oneTimeCode: Bool = false) -> some View {
        #if os(iOS)
        if oneTimeCode { keyboardType(.numberPad).textContentType(.oneTimeCode) } else { keyboardType(.decimalPad) }
        #else
        self
        #endif
    }
}

/// A navigation stack on the iPhone (large title, a bar with Done); the Mac preview build has none and shows the content alone.
struct NavigationShell<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        #if os(iOS)
        NavigationStack { content }
        #else
        content
        #endif
    }
}

extension View {
    /// The iPhone's inset grouped list: the look of the Settings app.
    @ViewBuilder func groupedList() -> some View {
        #if os(iOS)
        self.listStyle(.insetGrouped)
        #else
        self
        #endif
    }
}

/// The small rounded-square icons of the Settings app: a white symbol on a coloured tile.
struct SettingsIcon: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 29, height: 29)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint))
    }
}
