import Foundation
import Network
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// The voice assistant as the phone sees it: finds the TV, pairs with it, listens, sends what you said, and shows and
/// speaks what comes back. The TV does the thinking and the doing; this is the microphone, the ears and the face.
@MainActor
final class Assistant: ObservableObject {
    enum Link: Equatable {
        case searching, connecting, needsPairing, ready
        case offline(String)
    }

    enum Phase: Equatable {
        case idle, listening, thinking
        case acting(String)
        case speaking
        case done(Bool)
        case asking
    }

    enum PairingStep: Equatable { case none, requesting, enterCode, verifying }

    enum SpeakMode: String, CaseIterable, Identifiable {
        case answers, always, off
        var id: String { rawValue }
        var title: String {
            switch self {
            case .answers: return "Answers and questions"
            case .always: return "Everything"
            case .off: return "Never"
            }
        }
    }

    /// A tappable suggestion: what it says on the button, and what saying it means.
    struct Chip: Equatable, Hashable {
        var label: String
        var say: String
    }

    struct Favorite: Equatable, Hashable {
        var name: String
        var query: String
    }

    struct Question: Equatable {
        var text: String
        var options: [Chip]
    }

    struct Entry: Identifiable, Equatable {
        let id: String
        let said: String
        let reply: String
        let ok: Bool
        let action: String
        let ms: Int
        let source: String
        let at: Date
    }

    struct TVStatus: Equatable {
        var adb = "UNKNOWN"
        var brain = false
        var keySet = false
        /// False while the box is in standby; it stays on the network, so the power button can wake it.
        var awake = true
    }

    static let port = 8731

    @Published var link: Link = .searching
    @Published var phase: Phase = .idle
    @Published var pairing: PairingStep = .none
    @Published var pairingError: String?
    @Published var transcript = ""
    @Published var reply = ""
    @Published var alternative = ""
    @Published var question: Question?
    @Published var entries: [Entry] = []
    @Published var tv = TVStatus()
    @Published var favorites: [Favorite] = []
    @Published var routines: [String] = []
    @Published var lastAction = ""
    @Published var lastMs = 0
    @Published var lastSource = ""
    @Published var notice: String?
    @Published var host: String { didSet { defaults.set(host, forKey: "tv.host") } }
    @Published var speakMode: SpeakMode { didSet { defaults.set(speakMode.rawValue, forKey: "speak.mode") } }
    @Published var language: String { didSet { defaults.set(language, forKey: "speech.locale") } }
    @Published var model: String { didSet { defaults.set(model, forKey: "ai.model") } }
    @Published var effort: String { didSet { defaults.set(effort, forKey: "ai.effort") } }
    @Published var fast: Bool { didSet { defaults.set(fast, forKey: "ai.fast") } }

    let speech = SpeechListener()
    let voice = Speaker()

    /// Off only for the Mac preview renderer, which must never open a network connection.
    var autoConnect = true

    private let defaults = UserDefaults.standard
    private var task: URLSessionWebSocketTask?
    private var browser: NWBrowser?
    private var identity: PairedIdentity?
    private var connectionNonce = Data()
    private var challenge: (tvPub: Data, nonce: Data)?
    private var pendingPair: WBCrypto.Pairing?
    private var currentId: String?
    private var sentAt = Date()
    private var retryAfter: TimeInterval = 2
    private var retryWork: DispatchWorkItem?
    private var lastPartialSent = Date.distantPast
    private var doneWork: DispatchWorkItem?
    private var continuousAnswer = false

    init() {
        host = defaults.string(forKey: "tv.host") ?? ""
        speakMode = SpeakMode(rawValue: defaults.string(forKey: "speak.mode") ?? "") ?? .answers
        language = defaults.string(forKey: "speech.locale") ?? "en-US"
        model = defaults.string(forKey: "ai.model") ?? "claude-opus-5-5"
        effort = defaults.string(forKey: "ai.effort") ?? "medium"
        fast = defaults.bool(forKey: "ai.fast")
        if let d = Keychain.load("identity"), let id = try? JSONDecoder().decode(PairedIdentity.self, from: d) { identity = id }

        speech.onPartial = { [weak self] text in self?.heardPartial(text) }
        speech.onFinal = { [weak self] text in self?.heardFinal(text) }
        speech.onFailure = { [weak self] failure in self?.heardFailure(failure) }
        voice.onFinish = { [weak self] in self?.spokeAll() }
    }

    var isPaired: Bool { identity != nil }

    /// True once the TV answers (paired or not), so pairing can start.
    var canReach: Bool {
        switch link {
        case .needsPairing, .ready: return true
        default: return false
        }
    }

    /// Sends a remote-control message (button, text, app) to the paired TV.
    func sendRaw(_ object: [String: Any]) {
        guard link == .ready else { return }
        send(object)
    }

    /// Reconnect now instead of waiting for the next automatic try.
    func retryNow() {
        retryWork?.cancel()
        retryAfter = 2
        if task == nil {
            if !host.isEmpty { open(host) } else { link = .searching }
            discover()
        }
    }

    // MARK: - Connection

    /// Connects (or reconnects) to the TV: the last known address first, Bonjour in parallel.
    func start() {
        guard autoConnect, task == nil else { return }
        retryWork?.cancel()
        if !host.isEmpty { open(host) } else { link = .searching }
        discover()
    }

    func stop() {
        retryWork?.cancel()
        browser?.cancel()
        browser = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        // Leaving the app ends whatever the phone was doing: no listening or talking in the background.
        question = nil
        speech.cancel()
        voice.stop()
        if phase == .listening || phase == .thinking || phase == .speaking { phase = .idle }
    }

    private func open(_ address: String) {
        guard task == nil, let url = URL(string: "ws://\(address):\(Self.port)/ws") else { return }
        link = .connecting
        let t = URLSession.shared.webSocketTask(with: url)
        task = t
        t.resume()
        receive(t)
    }

    private func receive(_ t: URLSessionWebSocketTask) {
        t.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.task === t else { return }
                switch result {
                case .success(let message):
                    if case .string(let s) = message { self.handle(s) }
                    self.receive(t)
                case .failure(let error):
                    self.dropped(error)
                }
            }
        }
    }

    private func dropped(_ error: Error) {
        task?.cancel()
        task = nil
        connectionNonce = Data()
        if phase == .thinking || phase == .listening {
            speech.cancel()
            phase = .idle
        }
        link = .offline(error.localizedDescription)
        scheduleRetry()
    }

    private func scheduleRetry() {
        retryWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.task == nil else { return }
                if !self.host.isEmpty { self.open(self.host) }
                self.discover()
            }
        }
        retryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + retryAfter, execute: work)
        retryAfter = min(retryAfter * 1.6, 12)
    }

    private func discover() {
        guard browser == nil else { return }
        let b = NWBrowser(for: .bonjour(type: "_winkbox._tcp", domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in self?.found(results) }
        }
        b.start(queue: .main)
        browser = b
    }

    private func found(_ results: Set<NWBrowser.Result>) {
        guard let first = results.first else { return }
        resolve(first.endpoint) { [weak self] address in
            guard let self, let address else { return }
            if address != self.host { self.host = address }
            if self.task == nil { self.open(address) }
        }
    }

    /// Turns a Bonjour service into an IPv4 address by connecting to it once.
    private func resolve(_ endpoint: NWEndpoint, done: @escaping (String?) -> Void) {
        let params = NWParameters.tcp
        if let ip = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options { ip.version = .v4 }
        let c = NWConnection(to: endpoint, using: params)
        c.stateUpdateHandler = { state in
            switch state {
            case .ready:
                var address: String?
                if case let .hostPort(h, _)? = c.currentPath?.remoteEndpoint, case let .ipv4(a) = h {
                    address = "\(a)".split(separator: "%").first.map(String.init)
                }
                c.cancel()
                DispatchQueue.main.async { done(address) }
            case .failed:
                c.cancel()
                DispatchQueue.main.async { done(nil) }
            default:
                break
            }
        }
        c.start(queue: .main)
    }

    private func send(_ object: [String: Any]) {
        guard let t = task, let data = try? JSONSerialization.data(withJSONObject: object),
              let s = String(data: data, encoding: .utf8) else { return }
        t.send(.string(s)) { _ in }
    }

    // MARK: - Messages from the TV

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8), let m = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = m["t"] as? String else { return }
        switch type {
        case "hello":
            retryAfter = 2
            connectionNonce = Data(base64Encoded: m["nonce"] as? String ?? "") ?? Data()
            if let id = identity {
                send(["t": "auth", "deviceId": id.deviceId,
                      "mac": WBCrypto.hmac(id.secret, Data("auth".utf8), connectionNonce).base64EncodedString()])
            } else {
                link = .needsPairing
            }
        case "status":
            tv = TVStatus(adb: m["adb"] as? String ?? "UNKNOWN", brain: m["brain"] as? Bool ?? false, keySet: m["keySet"] as? Bool ?? false,
                          awake: m["awake"] as? Bool ?? true)
            if link != .ready {
                link = .ready
                send(["t": "history", "n": 40])
                pushSettings()
            }
        case "auth_failed":
            // The TV no longer knows this phone (it was forgotten, or the TV was reset): pair again.
            Keychain.delete("identity")
            identity = nil
            link = .needsPairing
        case "pair_challenge":
            if let pub = Data(base64Encoded: m["tvPub"] as? String ?? ""), let nonce = Data(base64Encoded: m["nonce"] as? String ?? "") {
                challenge = (pub, nonce)
                pairing = .enterCode
                pairingError = nil
            }
        case "paired":
            if let p = pendingPair, let id = m["deviceId"] as? String, let proof = Data(base64Encoded: m["tvProof"] as? String ?? ""), p.tvProof(proof) {
                let ident = PairedIdentity(deviceId: id, secret: p.secret)
                if let d = try? JSONEncoder().encode(ident) { Keychain.save(d, for: "identity") }
                identity = ident
                pairing = .none
                pendingPair = nil
                Haptics.success()
            } else {
                pairingError = "The TV's answer didn't check out. Try again."
                pairing = .none
            }
        case "pair_failed":
            switch m["reason"] as? String ?? "" {
            case "wrong_code": pairingError = "That isn't the code on the TV. Check it and try again."; pairing = .enterCode
            case "expired": pairingError = "The code expired. Start again."; pairing = .none
            case "locked": pairingError = "Too many wrong codes. Wait a minute and try again."; pairing = .none
            default: pairingError = "Pairing didn't work. Try again."; pairing = .none
            }
        case "state":
            guard (m["id"] as? String) == currentId else { return }
            switch m["s"] as? String ?? "" {
            case "thinking": phase = .thinking
            case "acting": phase = .acting(m["text"] as? String ?? "")
            default: break
            }
        case "result":
            guard (m["id"] as? String) == currentId else { return }
            let action = m["action"] as? String ?? ""
            finished(ok: m["ok"] as? Bool ?? false, say: m["say"] as? String ?? "", alt: m["alt"] as? String ?? "",
                     action: action, source: m["source"] as? String ?? "",
                     isAnswer: (m["speak"] as? Bool) ?? (action == "none" || action.isEmpty))
        case "clarify":
            guard (m["id"] as? String) == currentId else { return }
            asked(text: m["q"] as? String ?? "", options: Self.chips(m["options"]))
        case "favorites":
            favorites = ((m["items"] as? [[String: Any]]) ?? []).compactMap { i in
                guard let name = i["name"] as? String, let query = i["query"] as? String else { return nil }
                return Favorite(name: name, query: query)
            }
        case "routines":
            routines = (m["items"] as? [String]) ?? []
        case "history":
            entries = ((m["items"] as? [[String: Any]]) ?? []).compactMap { e in
                guard let said = e["text"] as? String else { return nil }
                return Entry(id: (e["id"] as? String) ?? UUID().uuidString, said: said, reply: e["say"] as? String ?? "", ok: e["ok"] as? Bool ?? true,
                             action: e["action"] as? String ?? "", ms: e["ms"] as? Int ?? 0, source: e["source"] as? String ?? "",
                             at: Date(timeIntervalSince1970: ((e["ts"] as? Double) ?? 0) / 1000))
            }.reversed()
        case "timer_fired":
            let label = (m["label"] as? String) ?? ""
            switch m["then"] as? String ?? "none" {
            case "standby": notice = "Going to sleep. Say \u{201C}cancel\u{201D} to stop it"
            case "pause": notice = "Timer done, paused"
            case "stop": notice = "Timer done, stopped"
            case "mute": notice = "Timer done, muted"
            default: notice = label.isEmpty ? "Timer done" : "\(label): time's up"
            }
            Haptics.warning()
        case "config_ok":
            tv.brain = m["brain"] as? Bool ?? tv.brain
            notice = (m["brain"] as? Bool ?? false) ? "Saved on your TV" : "Saved"
        case "error":
            if (m["code"] as? String) == "auth" { link = .needsPairing }
        default:
            break
        }
    }

    /// Choices from the TV: plain words, or {l: label, s: what saying it means}.
    private static func chips(_ raw: Any?) -> [Chip] {
        if let objects = raw as? [[String: Any]] {
            return objects.compactMap { o in
                guard let label = o["l"] as? String else { return nil }
                return Chip(label: label, say: (o["s"] as? String) ?? label.lowercased())
            }
        }
        return ((raw as? [String]) ?? []).map { Chip(label: $0, say: $0.lowercased()) }
    }

    // MARK: - Pairing

    func beginPairing() {
        guard task != nil else { return }
        pairing = .requesting
        pairingError = nil
        send(["t": "pair_start"])
    }

    func finishPairing(code: String) {
        guard let c = challenge else { return }
        do {
            let p = try WBCrypto.pair(code: code, tvPub: c.tvPub, nonce: c.nonce)
            pendingPair = p
            pairing = .verifying
            #if os(iOS)
            let name = UIDevice.current.name
            #else
            let name = Host.current().localizedName ?? "Mac"
            #endif
            send(["t": "pair_finish", "device": name, "phonePub": p.phonePub.base64EncodedString(), "proof": p.proof.base64EncodedString()])
        } catch {
            pairingError = "That code couldn't be used. Start again."
            pairing = .none
        }
    }

    func cancelPairing() {
        pairing = .none
        pairingError = nil
    }

    func forgetThisPhone() {
        if let id = identity, link == .ready { send(["t": "forget", "deviceId": id.deviceId]) }
        Keychain.delete("identity")
        identity = nil
        link = task == nil ? .searching : .needsPairing
    }

    // MARK: - Settings sent to the TV (sealed)

    func sendConfig(_ settings: [String: Any]) {
        guard let id = identity, let data = try? JSONSerialization.data(withJSONObject: settings),
              let box = try? WBCrypto.seal(data, secret: id.secret, aad: Data(id.deviceId.utf8)) else { return }
        send(["t": "config", "sealed": box.base64EncodedString()])
    }

    func saveAPIKey(_ key: String) {
        sendConfig(["anthropicKey": key])
    }

    func pushSettings() {
        sendConfig(["model": model, "effort": effort, "fast": fast])
    }

    // MARK: - Talking

    /// The big button: starts listening, ends a sentence early, or cancels what's in progress.
    func micTapped() {
        doneWork?.cancel()
        switch phase {
        case .listening:
            speech.finish()
        case .thinking, .acting:
            cancelRequest()
        case .speaking:
            voice.stop()
            phase = .idle
        default:
            startListening()
        }
    }

    func startListening(answering: Bool = false) {
        guard link == .ready else {
            reply = link == .needsPairing ? "Pair with your TV first." : "I can't reach your TV."
            alternative = ""
            phase = .done(false)
            return
        }
        voice.stop()
        continuousAnswer = answering
        transcript = ""
        if !answering { reply = ""; alternative = "" }
        question = nil
        phase = .listening
        Haptics.press()
        send(["t": "listening", "on": true])
        // The TV is told now so it can warm its connection to the cloud while you speak.
        Task { await speech.start(localeId: language) }
    }

    /// Hold-to-talk: release ends the sentence.
    func holdReleased() {
        if phase == .listening { speech.finish() }
    }

    private func heardPartial(_ text: String) {
        transcript = text
        if Date().timeIntervalSince(lastPartialSent) > 0.18 {
            lastPartialSent = Date()
            send(["t": "partial", "text": text])
        }
    }

    private func heardFinal(_ text: String) {
        submit(text)
    }

    private func heardFailure(_ failure: SpeechListener.Failure) {
        send(["t": "listening", "on": false])
        switch failure {
        case .denied: reply = "Allow the microphone and speech recognition for WinkBox in Settings."
        case .unavailable: reply = "Speech recognition isn't available for this language right now."
        case .nothingHeard: reply = "I didn't catch that."
        case .failed(let why): reply = why
        }
        alternative = ""
        phase = .done(false)
        Haptics.warning()
        scheduleIdle(after: 3)
    }

    /// Sends text as if it had been spoken (suggestion chips, the Yes/No buttons, typed requests).
    func say(_ text: String) {
        doneWork?.cancel()
        submit(text)
    }

    private func submit(_ text: String) {
        let id = String(UUID().uuidString.prefix(8)).lowercased()
        currentId = id
        sentAt = Date()
        transcript = text
        question = nil
        phase = .thinking
        send(["t": "say", "id": id, "text": text])
    }

    func cancelRequest() {
        if let id = currentId { send(["t": "cancel", "id": id]) }
        speech.cancel()
        voice.stop()
        currentId = nil
        phase = .idle
        send(["t": "listening", "on": false])
    }

    private func finished(ok: Bool, say: String, alt: String, action: String, source: String, isAnswer: Bool) {
        reply = say
        alternative = alt
        lastMs = Int(Date().timeIntervalSince(sentAt) * 1000)
        lastSource = source
        lastAction = ok ? action : ""
        phase = .done(ok)
        entries.insert(Entry(id: currentId ?? UUID().uuidString, said: transcript, reply: say, ok: ok, action: action, ms: lastMs, source: source, at: Date()), at: 0)
        if ok { Haptics.success() } else { Haptics.warning() }
        if speakMode == .always || (speakMode == .answers && (isAnswer || !ok)) {
            speak(say + (alt.isEmpty ? "" : " " + alt), showing: ok)    // a failure keeps its red orb while it is read out
        } else {
            scheduleIdle(after: 4)
        }
    }

    private func asked(text: String, options: [Chip]) {
        question = Question(text: text, options: options)
        reply = text
        phase = .asking
        Haptics.gentle()
        if speakMode != .off { speak(text, showing: false) } else if options.isEmpty { startListening(answering: true) }
    }

    private func speak(_ text: String, showing: Bool) {
        if showing && question == nil { phase = .speaking }
        voice.speak(text, language: language)
    }

    private func spokeAll() {
        if question != nil, question?.options.isEmpty == true {
            startListening(answering: true)         // the TV asked an open question: listen for the answer
        } else if phase == .speaking {
            scheduleIdle(after: 1.5)
        } else if case .done = phase {
            scheduleIdle(after: 2.5)
        }
    }

    private func scheduleIdle(after seconds: TimeInterval) {
        doneWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if case .done = self.phase { self.phase = .idle }
                if self.phase == .speaking { self.phase = .idle }
            }
        }
        doneWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: w)
    }
}
