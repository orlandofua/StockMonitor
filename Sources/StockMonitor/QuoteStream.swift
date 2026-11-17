import AppKit

/// A single price tick pushed by Yahoo Finance's streaming endpoint.
struct StreamTick {
    let symbol: String
    let price: Double
    let time: Date
    let change: Double?
    let changePercent: Double?
    let previousClose: Double?
}

/// Live price updates over Yahoo Finance's (unofficial) WebSocket streamer.
///
/// Not every symbol streams (some futures never send ticks), so callers keep a
/// polling fallback. The connection reconnects with exponential backoff after
/// failures and immediately after the Mac wakes from sleep.
final class QuoteStream {
    var onTick: ((StreamTick) -> Void)?

    private let url = URL(string: "wss://streamer.finance.yahoo.com/?version=2")!
    private let session = URLSession(configuration: .default)
    private var task: URLSessionWebSocketTask?
    private var symbols: [String] = []
    private var backoff: TimeInterval = 1
    private var reconnectWork: DispatchWorkItem?
    private var pingTimer: Timer?
    private var wakeObserver: NSObjectProtocol?

    init() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.backoff = 1
            self?.connect()
        }
    }

    deinit {
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        disconnect()
    }

    /// Sets the full list of symbols to stream, (re)connecting as needed.
    func setSymbols(_ newSymbols: [String]) {
        let old = Set(symbols)
        symbols = newSymbols
        guard let task, task.state == .running else { connect(); return }
        let removed = old.subtracting(newSymbols)
        if !removed.isEmpty { send(["unsubscribe": Array(removed)]) }
        let added = Set(newSymbols).subtracting(old)
        if !added.isEmpty { send(["subscribe": Array(added)]) }
    }

    // MARK: Connection

    private func connect() {
        disconnect()
        guard !symbols.isEmpty else { return }
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        send(["subscribe": symbols])
        receive(on: task)
        pingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self, weak task] _ in
            task?.sendPing { error in
                if error != nil { DispatchQueue.main.async { self?.scheduleReconnect(for: task) } }
            }
        }
    }

    private func disconnect() {
        reconnectWork?.cancel()
        reconnectWork = nil
        pingTimer?.invalidate()
        pingTimer = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    /// Reconnects after a delay, but only if `failed` is still the current task.
    private func scheduleReconnect(for failed: URLSessionWebSocketTask?) {
        guard failed === task, reconnectWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.reconnectWork = nil
            self?.connect()
        }
        reconnectWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + backoff, execute: work)
        backoff = min(backoff * 2, 60)
    }

    private func send(_ payload: [String: [String]]) {
        guard let task,
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text)) { _ in }
    }

    private func receive(on task: URLSessionWebSocketTask) {
        task.receive { [weak self, weak task] result in
            DispatchQueue.main.async {
                guard let self, let task, task === self.task else { return }
                switch result {
                case .success(let message):
                    self.backoff = 1
                    if case .string(let text) = message, let tick = Self.decode(text) {
                        self.onTick?(tick)
                    }
                    self.receive(on: task)
                case .failure:
                    self.scheduleReconnect(for: task)
                }
            }
        }
    }

    // MARK: Decoding

    /// Messages look like `{"type":"pricing","message":"<base64 protobuf>"}`.
    /// Older stream versions send the bare base64 string.
    static func decode(_ text: String) -> StreamTick? {
        var base64 = text
        if let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            guard json["type"] as? String == "pricing", let message = json["message"] as? String else { return nil }
            base64 = message
        }
        guard let bytes = Data(base64Encoded: base64) else { return nil }
        return decodePricingData([UInt8](bytes))
    }

    /// Minimal protobuf reader for Yahoo's `PricingData` message. Field numbers used:
    /// 1 id (string), 2 price (float), 3 time (sint64 ms), 8 changePercent (float),
    /// 12 change (float), 16 previousClose (float). Unknown fields are skipped.
    static func decodePricingData(_ b: [UInt8]) -> StreamTick? {
        var i = 0
        func varint() -> UInt64? {
            var result: UInt64 = 0, shift: UInt64 = 0
            while i < b.count, shift < 64 {
                let byte = b[i]; i += 1
                result |= UInt64(byte & 0x7F) << shift
                if byte & 0x80 == 0 { return result }
                shift += 7
            }
            return nil
        }
        func fixed(_ n: Int) -> UInt64? {
            guard i + n <= b.count else { return nil }
            var v: UInt64 = 0
            for k in 0..<n { v |= UInt64(b[i + k]) << (8 * UInt64(k)) }
            i += n
            return v
        }

        var id: String?, price: Float?, timeMs: Int64?
        var changePercent: Float?, change: Float?, previousClose: Float?

        while i < b.count {
            guard let key = varint() else { return nil }
            let field = key >> 3
            switch key & 7 {
            case 0: // varint
                guard let v = varint() else { return nil }
                if field == 3 { timeMs = Int64(bitPattern: v >> 1) ^ -Int64(bitPattern: v & 1) } // zigzag
            case 1: // 64-bit
                guard fixed(8) != nil else { return nil }
            case 2: // length-delimited
                guard let len = varint(), i + Int(len) <= b.count else { return nil }
                if field == 1 { id = String(decoding: b[i..<i + Int(len)], as: UTF8.self) }
                i += Int(len)
            case 5: // 32-bit float
                guard let raw = fixed(4) else { return nil }
                let f = Float(bitPattern: UInt32(raw))
                switch field {
                case 2: price = f
                case 8: changePercent = f
                case 12: change = f
                case 16: previousClose = f
                default: break
                }
            default:
                return nil
            }
        }

        guard let id, let price else { return nil }
        // Floats arrive as Float32; round to 6 significant-ish decimals to drop float noise.
        func clean(_ f: Float?) -> Double? { f.map { (Double($0) * 1_000_000).rounded() / 1_000_000 } }
        return StreamTick(
            symbol: id,
            price: clean(price)!,
            time: timeMs.map { Date(timeIntervalSince1970: Double($0) / 1000) } ?? Date(),
            change: clean(change),
            changePercent: clean(changePercent),
            previousClose: clean(previousClose).flatMap { $0 > 0 ? $0 : nil }
        )
    }
}
