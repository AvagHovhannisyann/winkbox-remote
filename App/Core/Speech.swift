import Foundation
import AVFoundation
import Speech

/// Listens through the iPhone's microphone and turns speech into text, streaming partial results as you talk. The text is
/// produced on the phone (by Apple's recognizer: on the device itself for languages that support it), and only the words
/// go to the TV. It ends by itself when you stop talking.
@MainActor
final class SpeechListener: NSObject, ObservableObject {
    enum Failure: Equatable {
        case denied, unavailable, nothingHeard
        case failed(String)
    }

    /// 0...1 loudness of the last audio buffer (the Mac preview sets it directly).
    @Published var level: Float = 0
    @Published private(set) var isListening = false

    var onPartial: ((String) -> Void)?
    var onFinal: ((String) -> Void)?
    var onFailure: ((Failure) -> Void)?

    /// Words the TV is likely to hear: app names and its own vocabulary. Helps the recognizer pick "Plex" over "plex" noise.
    static let vocabulary = ["WinkBox", "Wink", "YouTube", "SmartTube", "Spotify", "Plex", "Kodi", "VLC", "Apple TV", "Prime Video",
                             "Netflix", "AirPlay", "timer", "volume", "mute", "unmute", "settings", "Bluetooth", "Wi-Fi", "HDMI"]

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var timer: Timer?
    private var lastText = ""
    private var lastChange = Date()
    private var startedAt = Date()
    private var heard = false
    private var done = true
    private var maxSeconds: TimeInterval = 20

    /// Asks for speech recognition and microphone access (a system prompt the first time).
    func authorize() async -> Bool {
        guard await Self.speechPermission() else { return false }
        return await Self.microphonePermission()
    }

    nonisolated private static func speechPermission() async -> Bool {
        await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
    }

    nonisolated private static func microphonePermission() async -> Bool {
        #if os(iOS)
        return await withCheckedContinuation { c in AVAudioSession.sharedInstance().requestRecordPermission { c.resume(returning: $0) } }
        #else
        return true
        #endif
    }

    /// The tap runs on the audio thread, so it is built here, outside the main actor, and only reports loudness back.
    nonisolated private static func installTap(on input: AVAudioInputNode, format: AVAudioFormat,
                                               request: SFSpeechAudioBufferRecognitionRequest,
                                               level: @escaping @Sendable (Float) -> Void) {
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
            level(loudness(buffer))
        }
    }

    /// Starts listening. `silenceEnds`: how long a pause finishes the sentence (0 = only `finish()` ends it, for hold-to-talk).
    func start(localeId: String, silenceEnds: TimeInterval = 1.1, preferOnDevice: Bool = true) async {
        stopEverything()
        guard await authorize() else { onFailure?(.denied); return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeId)), recognizer.isAvailable else {
            onFailure?(.unavailable)
            return
        }
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            onFailure?(.failed("The microphone is busy."))
            return
        }
        #endif

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.taskHint = .search
        req.contextualStrings = Self.vocabulary
        if preferOnDevice && recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            onFailure?(.unavailable)
            return
        }
        input.removeTap(onBus: 0)
        Self.installTap(on: input, format: format, request: req) { [weak self] loudness in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.level = max(loudness, self.level * 0.82)
            }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            onFailure?(.failed("I couldn't start the microphone."))
            return
        }

        lastText = ""
        heard = false
        done = false
        startedAt = Date()
        lastChange = Date()
        isListening = true
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            Task { @MainActor [weak self] in self?.received(result, error) }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick(silenceEnds: silenceEnds) }
        }
    }

    /// Ends the sentence now: whatever was heard so far becomes the request.
    func finish() {
        guard isListening, !done else { return }
        request?.endAudio()
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        // The recognizer answers with its final text shortly; if it doesn't, use the last partial.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard let self, !self.done else { return }
            self.complete(self.lastText)
        }
    }

    /// Throws the sentence away.
    func cancel() {
        guard !done else { return }
        done = true
        stopEverything()
    }

    private func tick(silenceEnds: TimeInterval) {
        guard isListening, !done else { return }
        let now = Date()
        if heard && silenceEnds > 0 && now.timeIntervalSince(lastChange) > silenceEnds {
            finish()
        } else if !heard && now.timeIntervalSince(startedAt) > 8 {
            done = true
            stopEverything()
            onFailure?(.nothingHeard)
        } else if now.timeIntervalSince(startedAt) > maxSeconds {
            finish()
        }
    }

    private func received(_ result: SFSpeechRecognitionResult?, _ error: Error?) {
        guard !done else { return }
        if let result {
            let text = result.bestTranscription.formattedString
            if text != lastText {
                lastText = text
                lastChange = Date()
                heard = !text.trimmingCharacters(in: .whitespaces).isEmpty
                onPartial?(text)
            }
            if result.isFinal {
                complete(text)
                return
            }
        }
        if error != nil {
            if heard { complete(lastText) } else {
                done = true
                stopEverything()
                onFailure?(.nothingHeard)
            }
        }
    }

    private func complete(_ text: String) {
        guard !done else { return }
        done = true
        stopEverything()
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { onFailure?(.nothingHeard) } else { onFinal?(t) }
    }

    private func stopEverything() {
        timer?.invalidate()
        timer = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        isListening = false
        level = 0
    }

    nonisolated private static func loudness(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<n { sum += data[i] * data[i] }
        return min(1, (sum / Float(n)).squareRoot() * 9)
    }
}

/// Reads replies aloud with the best voice installed for the language.
@MainActor
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    var onFinish: (() -> Void)?

    override init() {
        super.init()
        synth.delegate = self
    }

    var isSpeaking: Bool { synth.isSpeaking }

    func speak(_ text: String, language: String) {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        let u = AVSpeechUtterance(string: text)
        let lang = language.replacingOccurrences(of: "_", with: "-")
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == lang }
        u.voice = voices.max(by: { $0.quality.rawValue < $1.quality.rawValue }) ?? AVSpeechSynthesisVoice(language: lang)
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        u.preUtteranceDelay = 0.05
        synth.speak(u)
    }

    func stop() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.onFinish?() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.onFinish?() }
    }
}
