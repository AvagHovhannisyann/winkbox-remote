// Renders the app's screens on the Mac (SwiftUI for macOS) at iPhone size, to check the design without a device.
// usage: preview <outdir>
import AppKit
import SwiftUI

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
app.appearance = NSAppearance(named: .darkAqua)
let size = NSSize(width: 393, height: 852)     // iPhone 15 / 16 Pro, in points

/// The iPhone's status bar and home indicator, drawn into the safe areas.
struct PhoneFrame<Content: View>: View {
    let content: Content

    var body: some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    Text("9:41").font(.system(size: 17, weight: .semibold))
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: "cellularbars")
                        Image(systemName: "wifi")
                        Image(systemName: "battery.100")
                    }
                    .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 34)
                .frame(height: 54)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Capsule().fill(Color.white.opacity(0.9)).frame(width: 140, height: 5).frame(height: 30)
            }
    }
}

func render<V: View>(_ view: V, _ name: String) {
    let root = PhoneFrame(content: view).frame(width: size.width, height: size.height).environment(\.colorScheme, .dark)
    let host = NSHostingView(rootView: root)
    host.frame = NSRect(origin: .zero, size: size)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .darkAqua)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.8))
    let scale: CGFloat = 2
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    host.cacheDisplay(in: host.bounds, to: rep)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
    print("\(outDir)/\(name).png")
}

func tv(_ status: TV.Status) -> TV {
    let t = TV()
    t.autoConnect = false
    t.status = status
    return t
}

/// An assistant in a given state. It never opens a connection (autoConnect is off).
@MainActor func assistant(link: Assistant.Link = .ready, phase: Assistant.Phase = .idle, _ setup: @MainActor (Assistant) -> Void = { _ in }) -> Assistant {
    let a = Assistant()
    a.autoConnect = false
    a.link = link
    a.phase = phase
    a.tv = Assistant.TVStatus(adb: "CONNECTED", brain: true, keySet: true)
    setup(a)
    return a
}

func root(_ tab: RootView.Tab, _ t: TV, _ a: Assistant) -> some View {
    RootView(tab: tab).environmentObject(t).environmentObject(a)
}

@MainActor func renderAll() {
    let connected = TV.Status.connected("WinkBox 2")
    UserDefaults.standard.set("touch", forKey: "padMode")

    // The voice screen in each state.
    render(root(.voice, tv(connected), assistant()), "01-voice-idle")
    render(root(.voice, tv(connected), assistant(phase: .listening) { a in
        a.transcript = "Play some classic Italian music"
        a.speech.level = 0.55
    }), "02-voice-listening")
    render(root(.voice, tv(connected), assistant(phase: .thinking) { a in
        a.transcript = "Play some classic Italian music"
    }), "03-voice-thinking")
    render(root(.voice, tv(connected), assistant(phase: .done(true)) { a in
        a.transcript = "Set a timer for ten minutes"
        a.reply = "Timer set for 10 minutes."
        a.lastMs = 31
        a.lastSource = "local"
    }), "04-voice-done")
    render(root(.voice, tv(connected), assistant(phase: .asking) { a in
        a.transcript = "Open the music"
        a.question = Assistant.Question(text: "Which one: Spotify, Plex or Kodi?", options: ["Spotify", "Plex", "Kodi"])
        a.reply = "Which one: Spotify, Plex or Kodi?"
    }), "05-voice-asking")
    render(root(.voice, tv(connected), assistant(phase: .done(false)) { a in
        a.transcript = "Open Netflix"
        a.reply = "Netflix won't play on this box, it isn't certified for it."
        a.alternative = "Try YouTube or Prime Video instead."
    }), "06-voice-error")
    render(root(.voice, tv(.idle), assistant(link: .needsPairing)), "07-needs-pairing")
    render(root(.voice, tv(.idle), assistant(link: .offline("The request timed out."))), "08-offline")

    // The remote tabs, as before.
    render(root(.remote, tv(connected), assistant()), "10-remote-touch")
    UserDefaults.standard.set("arrows", forKey: "padMode")
    render(root(.remote, tv(connected), assistant()), "11-remote-arrows")
    UserDefaults.standard.set("touch", forKey: "padMode")
    render(root(.apps, tv(connected), assistant()), "12-apps")
    render(root(.type, tv(connected), assistant()), "13-type")
    render(root(.remote, tv(.needsApproval), assistant { a in a.tv.adb = "WAITING_APPROVAL" }), "14-approve")

    // Settings and history.
    render(SettingsView().environmentObject(tv(connected)).environmentObject(assistant(link: .needsPairing) { a in a.tv.keySet = false; a.tv.brain = false }), "20-settings-unpaired")
    render(SettingsView().environmentObject(tv(connected)).environmentObject(assistant { a in a.pairing = .enterCode }), "21-settings-pairing")
    render(HistoryView().environmentObject(assistant { a in
        let now = Date()
        a.entries = [
            Assistant.Entry(id: "1", said: "Play some classic Italian music", reply: "Playing Italian classics on YouTube.", ok: true, action: "play_music", ms: 1840, source: "cloud", at: now.addingTimeInterval(-60)),
            Assistant.Entry(id: "2", said: "Set a timer for ten minutes", reply: "Timer set for 10 minutes.", ok: true, action: "timer", ms: 31, source: "local", at: now.addingTimeInterval(-600)),
            Assistant.Entry(id: "3", said: "Open Netflix", reply: "Netflix won't play on this box.", ok: false, action: "open_app", ms: 22, source: "local", at: now.addingTimeInterval(-3600)),
        ]
    }), "22-history")
}

// The Assistant and its views belong to the main actor, so the renders run there; the app loop keeps the main queue going.
Task { @MainActor in
    renderAll()
    exit(0)
}
app.run()
