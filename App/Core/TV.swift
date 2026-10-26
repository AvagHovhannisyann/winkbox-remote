import Foundation
import Combine

/// Buttons, as Linux input key codes. The box's keypad (aml_keypad, /dev/input/event0) maps them to Android keys
/// through /vendor/usr/keylayout/Vendor_0001_Product_0001.kl, exactly as if its own remote had sent them.
enum RemoteKey: UInt16 {
    case up = 103, down = 108, left = 105, right = 106, select = 28
    case back = 158, home = 102, menu = 139
    case playPause = 164, next = 163, previous = 165, rewind = 168, fastForward = 208
    case volumeUp = 115, volumeDown = 114, mute = 113, power = 116
    case channelUp = 402, channelDown = 403, info = 358, guide = 362
}

/// An app on the box, launched the way its home screen launches it. Its tile is drawn by `BrandArt`.
struct TVApp: Identifiable, Hashable {
    let id: String          // package
    let name: String
    let command: String     // shell command that opens it
    let tint: UInt32        // tile background

    static func activity(_ pkg: String, _ activity: String, name: String, tint: UInt32) -> TVApp {
        TVApp(id: pkg, name: name,
              command: "am start -a android.intent.action.MAIN -c android.intent.category.LEANBACK_LAUNCHER -f 0x10200000 -n \(pkg)/\(activity)",
              tint: tint)
    }

    static let all: [TVApp] = [
        .activity("org.smarttube.stable", "com.liskovsoft.smartyoutubetv2.tv.ui.main.SplashActivity",
                  name: "YouTube", tint: 0x181818),
        TVApp(id: "ru.rt.itv.stb.wink", name: "Wink TV",
              command: "am start -a android.intent.action.VIEW -d wink://target -p ru.rt.itv.stb.wink --es query '{\"type\":\"channels\",\"link\":{}}'",
              tint: 0x181818),
        .activity("com.apple.atve.androidtv.appletv", ".MainActivity", name: "Apple TV", tint: 0x111111),
        .activity("com.spotify.tv.android", ".SpotifyTVActivity", name: "Spotify", tint: 0x121212),
        .activity("com.plexapp.android", "tv.plex.app.MainActivity", name: "Plex", tint: 0x000000),
        .activity("com.amazon.amazonvideo.livingroom", "com.amazon.ignition.IgnitionActivity", name: "Prime Video", tint: 0x1A98FF),
        .activity("org.xbmc.kodi", ".Splash", name: "Kodi", tint: 0xE9E9E9),
        .activity("org.videolan.vlc", ".StartActivity", name: "VLC", tint: 0xFF8800),
        .activity("com.phlox.tvwebbrowser", ".activity.main.MainActivity", name: "TV Bro", tint: 0xFFE81F),
        .activity("io.github.jqssun.airplay", ".MainActivity", name: "AirPlay", tint: 0x23232D),
        TVApp(id: "settings", name: "Settings", command: "am start -a android.settings.SETTINGS", tint: 0x37474F),
    ]
}

/// The box, as the app sees it: one ADB connection with a raw stream into the keypad for instant button presses,
/// and a shell that runs the slower commands (typing, opening apps) in order.
final class TV: ObservableObject {
    enum Status: Equatable {
        case idle
        case connecting
        case needsApproval
        case connected(String)
        case failed(String)
    }

    @Published var status: Status = .idle
    @Published var host: String {
        didSet { UserDefaults.standard.set(host, forKey: "host") }
    }
    /// Off only for the Mac preview renderer, which must never connect to the box.
    var autoConnect = true

    private var adb: ADBConnection?
    private var keys: ADBStream?
    private var shell: ADBStream?
    private var keysReady = false
    private var queuedKeys: [Data] = []
    private var retryWork: DispatchWorkItem?
    private let keyDevice = "/dev/input/event0"

    init() {
        host = UserDefaults.standard.string(forKey: "host") ?? "192.168.1.8"
    }

    var isConnected: Bool {
        if case .connected = status { return true }
        return false
    }

    // MARK: - Connection

    func connect() {
        retryWork?.cancel()
        adb?.stop()
        keys = nil
        shell = nil
        keysReady = false
        status = .connecting

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        guard let key = try? ADBKey.loadOrCreate(directory: support) else {
            status = .failed("The app couldn't create its key.")
            return
        }
        let connection = ADBConnection(host: host, key: key, keyName: "WinkBox Remote@iPhone")
        connection.onState = { [weak self, weak connection] state in
            DispatchQueue.main.async {
                guard let self = self, let connection = connection, connection === self.adb else { return }
                switch state {
                case .connecting:
                    self.status = .connecting
                case .waitingForApproval:
                    self.status = .needsApproval
                case .connected(let device):
                    self.status = .connected(device)
                    self.openChannels(on: connection)
                case .failed(let why):
                    self.status = .failed(why)
                    self.adb = nil
                    self.scheduleRetry()
                }
            }
        }
        adb = connection
        connection.start()
    }

    func disconnect() {
        retryWork?.cancel()
        adb?.stop()
        adb = nil
        status = .idle
    }

    /// Reconnects quietly a few seconds after a drop (the box restarting, Wi-Fi hiccups).
    private func scheduleRetry() {
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.adb == nil else { return }
            self.connect()
        }
        retryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    private func openChannels(on connection: ADBConnection) {
        keys = connection.open("exec:cat > \(keyDevice)") { [weak self] s in
            s.onOpen = { DispatchQueue.main.async { self?.keysOpened() } }
            s.onClose = { DispatchQueue.main.async { self?.keysReady = false } }
        }
        shell = connection.open("shell:")
    }

    private func keysOpened() {
        keysReady = true
        queuedKeys.forEach { keys?.write($0) }
        queuedKeys.removeAll()
    }

    // MARK: - Buttons

    /// A full press (down and up).
    func press(_ key: RemoteKey) {
        send(events(key, 1) + events(key, 0))
    }

    /// Holding a button: the box repeats arrows and turns a long OK into a long press, like its own remote.
    func hold(_ key: RemoteKey, down: Bool) {
        send(events(key, down ? 1 : 0))
    }

    private func send(_ data: Data) {
        guard isConnected else {
            if case .failed = status { connect() }
            return
        }
        if keysReady, let keys = keys {
            keys.write(data)
        } else {
            queuedKeys.append(data)
        }
    }

    /// One key transition plus the sync that delivers it: two `struct input_event`s for the box's 32-bit kernel.
    private func events(_ key: RemoteKey, _ value: Int32) -> Data {
        var d = Data(capacity: 32)
        func event(_ type: UInt16, _ code: UInt16, _ value: Int32) {
            var raw = (Int32(0), Int32(0), type.littleEndian, code.littleEndian, value.littleEndian)
            withUnsafeBytes(of: &raw) { d.append(contentsOf: $0) }
        }
        event(1, key.rawValue, value)
        event(0, 0, 0)
        return d
    }

    // MARK: - Commands

    func run(_ command: String) {
        guard isConnected, let shell = shell else {
            if case .failed = status { connect() }
            return
        }
        shell.write(command + " >/dev/null 2>&1\n")
    }

    func open(_ app: TVApp) { run(app.command) }

    /// Types text into the focused field on the TV, after deleting `deleting` characters. `input text` takes ASCII
    /// only; spaces are sent as %s.
    func type(_ text: String, deleting: Int = 0) {
        var parts: [String] = []
        if deleting > 0 {
            parts.append("input keyevent " + Array(repeating: "67", count: min(deleting, 200)).joined(separator: " "))
        }
        let ascii = String(text.unicodeScalars.filter { $0.isASCII && $0.value >= 0x20 && $0.value < 0x7f })
        if !ascii.isEmpty {
            let escaped = ascii.replacingOccurrences(of: "'", with: "'\\''").replacingOccurrences(of: " ", with: "%s")
            parts.append("input text '\(escaped)'")
        }
        guard !parts.isEmpty else { return }
        run(parts.joined(separator: "; "))
    }

    /// The keyboard's Enter / Search key.
    func submit() { run("input keyevent 66") }
}
