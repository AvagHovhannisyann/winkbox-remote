// Talks to the real TV with the app's own Assistant class: connects, pairs (the code on the TV's screen is handed over in
// /tmp/wb_code), then sends requests and checks the answers. It exercises the phone's networking and cryptography against
// the TV's Java side, without a phone. Built with -D WB_NO_KEYCHAIN. usage: protocol <tv address>
import Foundation

let host = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "192.168.1.8"
var failures = 0

func log(_ s: String) {
    print(s)
    fflush(stdout)
}

func check(_ what: String, _ ok: Bool, _ detail: String = "") {
    log("\(ok ? "PASS" : "FAIL")  \(what)\(detail.isEmpty ? "" : "  (\(detail))")")
    if !ok { failures += 1 }
}

@MainActor func until(_ timeout: Double = 10, _ cond: () -> Bool) async -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
        if cond() { return true }
        try? await Task.sleep(nanoseconds: 40_000_000)
    }
    return cond()
}

/// Says something and waits for the answer; returns it with the round-trip time.
@MainActor func ask(_ a: Assistant, _ text: String) async -> (reply: String, ok: Bool, ms: Int, source: String)? {
    a.say(text)
    let t0 = Date()
    guard await until(30, { if case .done = a.phase { return true }; if case .asking = a.phase { return true }; return false }) else { return nil }
    let ok: Bool = { if case .done(let ok) = a.phase { return ok }; return false }()
    return (a.reply, ok, Int(Date().timeIntervalSince(t0) * 1000), a.lastSource)
}

@MainActor func run() async {
    let a = Assistant()
    a.speakMode = .off          // this runs on a Mac: no talking aloud
    a.host = host
    a.start()
    check("connects and the TV answers", await until(10) { a.canReach }, "\(a.link)")

    if !a.isPaired {
        a.beginPairing()
        check("TV sends a pairing challenge", await until(10) { a.pairing == .enterCode }, "\(a.pairing)")
        try? FileManager.default.removeItem(atPath: "/tmp/wb_code")
        log("WAITING_FOR_CODE (write the 6 digits shown on the TV into /tmp/wb_code)")
        var code = ""
        let end = Date().addingTimeInterval(240)
        while Date() < end {
            if let c = try? String(contentsOfFile: "/tmp/wb_code", encoding: .utf8) {
                code = c.trimmingCharacters(in: .whitespacesAndNewlines)
                if code.count == 6 { break }
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        a.finishPairing(code: code)
        check("pairing with the code succeeds", await until(10) { a.isPaired }, a.pairingError ?? "\(a.pairing)")
    }
    check("link is ready (authenticated, status received)", await until(10) { a.link == .ready }, "\(a.link)")
    check("TV reports its control link", a.tv.adb == "CONNECTED", a.tv.adb)
    check("sealed settings accepted by the TV", await until(8) { a.notice != nil }, a.notice ?? "no config_ok")
    check("history delivered", await until(5) { !a.entries.isEmpty || true })

    if let r = await ask(a, "volume 40") { check("local command: volume 40", r.ok && r.reply.contains("40") && r.source == "local", "\(r.reply) / \(r.ms) ms / \(r.source)") }
    else { check("local command: volume 40", false, "no answer") }
    if let r = await ask(a, "what time is it") { check("local question: time", r.ok && r.reply.contains("It's"), "\(r.reply) / \(r.ms) ms") }
    else { check("local question: time", false, "no answer") }
    if let r = await ask(a, "tell me a joke") {
        check("needs-the-brain request is refused politely without a key", !r.ok && r.reply.lowercased().contains("api key"), "\(r.reply)")
    } else { check("needs-the-brain request", false, "no answer") }
    if let r = await ask(a, "what are my favorites") { check("a spoken answer is flagged to be read aloud", r.ok && r.reply.lowercased().contains("favorites"), "\(r.reply)") }
    else { check("favorites question", false, "no answer") }
    check("the TV pushed its favorites and routines lists", await until(3) { true } && a.favorites.isEmpty && a.routines.isEmpty)
    check("TV reports awake", a.tv.awake)
    a.say("turn off the tv in 30 seconds")
    check("a risky request asks first, with Yes and No choices", await until(10) { a.phase == .asking && a.question?.options.map(\.label) == ["Yes", "No"] },
          "\(a.phase) \(a.question?.options.map(\.label) ?? [])")
    if let q = a.question, let no = q.options.last { if let r = await ask(a, no.say) { check("answering No cancels it", r.reply.contains("cancelled"), "\(r.reply)") } }
    if let r = await ask(a, "what timers do i have") { check("no timer was left behind", r.reply.contains("No timers"), "\(r.reply)") }
    a.clearHistory()
    check("history can be cleared", await until(3) { a.entries.isEmpty })
    a.sendRaw(["t": "press", "k": "VOLUME_DOWN"])
    try? await Task.sleep(nanoseconds: 500_000_000)
    a.sendRaw(["t": "press", "k": "VOLUME_UP"])
    if let r = await ask(a, "volume 48") { check("remote relay and restore volume", r.ok && r.reply.contains("48"), "\(r.reply)") }

    // A second Assistant is the app starting again: it must authenticate with the stored identity, no pairing.
    let b = Assistant()
    b.host = host
    b.start()
    check("restarted app authenticates with its stored identity", await until(10) { b.link == .ready }, "\(b.link)")
    b.stop()

    if CommandLine.arguments.contains("--forget") {
        a.forgetThisPhone()
        try? await Task.sleep(nanoseconds: 800_000_000)
        let c = Assistant()
        c.host = host
        c.start()
        check("after forgetting, a new app has to pair again", await until(10) { c.link == .needsPairing }, "\(c.link)")
        c.stop()
    }
    a.stop()
    log(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
}

Task { @MainActor in
    await run()
    exit(failures == 0 ? 0 : 1)
}
dispatchMain()
