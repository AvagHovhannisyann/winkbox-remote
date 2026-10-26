import Foundation
import Network

enum ADBError: Error, LocalizedError {
    case badKey
    case closed(String)
    case streamRefused(String)

    var errorDescription: String? {
        switch self {
        case .badKey: return "The app's key could not be read."
        case .closed(let why): return why
        case .streamRefused(let service): return "The box refused \(service)."
        }
    }
}

/// One message of the ADB wire protocol: a 24-byte little-endian header and an optional payload.
struct ADBMessage {
    static let cnxn: UInt32 = 0x4e58_4e43
    static let auth: UInt32 = 0x4854_5541
    static let open: UInt32 = 0x4e45_504f
    static let okay: UInt32 = 0x5941_4b4f
    static let clse: UInt32 = 0x4553_4c43
    static let wrte: UInt32 = 0x4554_5257

    static let authToken: UInt32 = 1
    static let authSignature: UInt32 = 2
    static let authPublicKey: UInt32 = 3

    var command: UInt32
    var arg0: UInt32
    var arg1: UInt32
    var payload = Data()

    func encoded() -> Data {
        var d = Data(capacity: 24 + payload.count)
        func put(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        put(command)
        put(arg0)
        put(arg1)
        put(UInt32(payload.count))
        put(payload.reduce(UInt32(0)) { $0 &+ UInt32($1) })   // legacy checksum; newer adbd ignores it
        put(command ^ 0xffff_ffff)
        d.append(payload)
        return d
    }

    /// Parses one message from the front of `buffer`, removing it; nil until a whole message has arrived.
    static func take(from buffer: inout Data) -> ADBMessage? {
        guard buffer.count >= 24 else { return nil }
        let base = buffer.startIndex
        func word(_ i: Int) -> UInt32 {
            var v: UInt32 = 0
            for k in 0..<4 { v |= UInt32(buffer[base + i * 4 + k]) << (8 * k) }
            return v
        }
        let length = Int(word(3))
        guard buffer.count >= 24 + length else { return nil }
        let message = ADBMessage(command: word(0), arg0: word(1), arg1: word(2),
                                 payload: Data(buffer[(base + 24)..<(base + 24 + length)]))
        buffer = Data(buffer[(base + 24 + length)...])
        return message
    }
}

/// A stream to a service on the box ("shell:", "exec:..."). Writes are queued and sent one at a time, each waiting
/// for the box's OKAY, which is adb's flow control.
final class ADBStream {
    let localID: UInt32
    let service: String
    fileprivate(set) var remoteID: UInt32 = 0
    fileprivate weak var connection: ADBConnection?
    fileprivate var pending: [Data] = []
    fileprivate var awaitingOkay = true          // until the box accepts the OPEN
    fileprivate(set) var isOpen = false
    fileprivate(set) var isClosed = false

    /// Called on the connection's queue.
    var onOpen: (() -> Void)?
    var onData: ((Data) -> Void)?
    var onClose: (() -> Void)?

    fileprivate init(localID: UInt32, service: String) {
        self.localID = localID
        self.service = service
    }

    func write(_ data: Data) {
        connection?.queue.async { [self] in
            guard !isClosed else { return }
            let chunk = connection?.maxPayload ?? 4096
            var offset = 0
            while offset < data.count {
                pending.append(data.subdata(in: offset..<min(offset + chunk, data.count)))
                offset += chunk
            }
            connection?.flush(self)
        }
    }

    func write(_ text: String) { write(Data(text.utf8)) }

    func close() {
        connection?.queue.async { [self] in connection?.close(self) }
    }
}

/// A connection to the box's ADB daemon over Wi-Fi (TCP 5555): the CNXN/AUTH handshake, then any number of streams.
final class ADBConnection {
    enum State: Equatable {
        case connecting
        case waitingForApproval      // the box is showing "Allow USB debugging?" for this app's key
        case connected(device: String)
        case failed(String)
    }

    let queue = DispatchQueue(label: "adb.connection")
    private let onQueueKey = DispatchSpecificKey<Bool>()
    private(set) var maxPayload = 4096
    private let connection: NWConnection
    private let key: ADBKey
    private let keyName: String
    private var buffer = Data()
    private var signatureSent = false
    private var streams: [UInt32: ADBStream] = [:]
    private var nextID: UInt32 = 1
    private var finished = false

    /// Called on `queue`.
    var onState: ((State) -> Void)?

    init(host: String, port: UInt16 = 5555, key: ADBKey, keyName: String) {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 10
        tcp.keepaliveInterval = 5
        tcp.keepaliveCount = 3
        tcp.connectionTimeout = 6
        connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!,
                                  using: NWParameters(tls: nil, tcp: tcp))
        self.key = key
        self.keyName = keyName
        queue.setSpecific(key: onQueueKey, value: true)
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.send(ADBMessage(command: ADBMessage.cnxn, arg0: 0x0100_0001, arg1: 256 * 1024,
                                     payload: Data("host::features=shell_v2,cmd\0".utf8)))
                self.receive()
            case .waiting(let error):
                self.fail("Can't reach the box (\(error.localizedDescription)).")
            case .failed(let error):
                self.fail("Connection lost (\(error.localizedDescription)).")
            case .cancelled:
                self.fail("Disconnected.")
            default:
                break
            }
        }
        onState?(.connecting)
        connection.start(queue: queue)
    }

    func stop() {
        queue.async { [self] in
            finished = true
            connection.cancel()
        }
    }

    /// Opens a stream to `service`; call on any thread. The stream's callbacks run on `queue`.
    @discardableResult
    func open(_ service: String, configure: ((ADBStream) -> Void)? = nil) -> ADBStream {
        let register = { () -> ADBStream in
            let s = ADBStream(localID: self.nextID, service: service)
            self.nextID += 1
            s.connection = self
            configure?(s)
            self.streams[s.localID] = s
            return s
        }
        let stream = DispatchQueue.getSpecific(key: onQueueKey) == true ? register() : queue.sync(execute: register)
        queue.async { [self] in
            guard !finished else { return finish(stream) }
            send(ADBMessage(command: ADBMessage.open, arg0: stream.localID, arg1: 0,
                            payload: Data((service + "\0").utf8)))
        }
        return stream
    }

    // MARK: - Internals (on `queue`)

    fileprivate func flush(_ stream: ADBStream) {
        guard stream.isOpen, !stream.awaitingOkay, !stream.pending.isEmpty else { return }
        let data = stream.pending.removeFirst()
        stream.awaitingOkay = true
        send(ADBMessage(command: ADBMessage.wrte, arg0: stream.localID, arg1: stream.remoteID, payload: data))
    }

    fileprivate func close(_ stream: ADBStream) {
        guard !stream.isClosed else { return }
        if stream.isOpen {
            send(ADBMessage(command: ADBMessage.clse, arg0: stream.localID, arg1: stream.remoteID))
        }
        finish(stream)
    }

    private func finish(_ stream: ADBStream) {
        guard !stream.isClosed else { return }
        stream.isClosed = true
        stream.pending.removeAll()
        streams[stream.localID] = nil
        stream.onClose?()
    }

    private func fail(_ why: String) {
        guard !finished else { return }
        finished = true
        connection.cancel()
        for s in streams.values { finish(s) }
        onState?(.failed(why))
    }

    private func send(_ message: ADBMessage) {
        connection.send(content: message.encoded(), completion: .contentProcessed { [weak self] error in
            if let error = error { self?.fail("Send failed (\(error.localizedDescription)).") }
        })
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let data = data, !data.isEmpty {
                self.buffer.append(data)
                while let message = ADBMessage.take(from: &self.buffer) { self.handle(message) }
            }
            if let error = error {
                self.fail("Connection lost (\(error.localizedDescription)).")
            } else if isComplete {
                self.fail("The box closed the connection.")
            } else if !self.finished {
                self.receive()
            }
        }
    }

    private func handle(_ m: ADBMessage) {
        switch m.command {
        case ADBMessage.auth where m.arg0 == ADBMessage.authToken:
            if !signatureSent, let sig = try? key.sign(token: m.payload) {
                signatureSent = true
                send(ADBMessage(command: ADBMessage.auth, arg0: ADBMessage.authSignature, arg1: 0, payload: sig))
            } else if let pub = try? key.adbPublicKey(name: keyName) {
                // The box doesn't know this key yet: offer it, and the TV asks the user to allow it.
                send(ADBMessage(command: ADBMessage.auth, arg0: ADBMessage.authPublicKey, arg1: 0, payload: pub))
                onState?(.waitingForApproval)
            } else {
                fail("The app's key could not be read.")
            }

        case ADBMessage.cnxn:
            maxPayload = max(1024, min(Int(m.arg1), 256 * 1024))
            let banner = String(decoding: m.payload, as: UTF8.self)
            var model = "Android TV"
            for part in banner.split(separator: ";") where part.contains("ro.product.model=") {
                model = String(part.split(separator: "=").last ?? "")
            }
            onState?(.connected(device: model))

        case ADBMessage.okay:
            guard let s = streams[m.arg1] else { return }
            if !s.isOpen {
                s.remoteID = m.arg0
                s.isOpen = true
                s.awaitingOkay = false
                s.onOpen?()
            } else {
                s.awaitingOkay = false
            }
            flush(s)

        case ADBMessage.wrte:
            guard let s = streams[m.arg1] else { return }
            send(ADBMessage(command: ADBMessage.okay, arg0: s.localID, arg1: m.arg0))
            s.onData?(m.payload)

        case ADBMessage.clse:
            if let s = streams[m.arg1] { finish(s) }

        default:
            break
        }
    }
}
