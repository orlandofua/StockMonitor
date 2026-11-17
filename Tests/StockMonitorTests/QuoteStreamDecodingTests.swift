import Foundation
import Testing
@testable import StockMonitor

/// Builds protobuf `PricingData` payloads for tests.
private struct ProtoWriter {
    var bytes: [UInt8] = []

    mutating func varint(_ value: UInt64) {
        var v = value
        while v >= 0x80 { bytes.append(UInt8(v & 0x7F) | 0x80); v >>= 7 }
        bytes.append(UInt8(v))
    }
    mutating func key(_ field: UInt64, _ wire: UInt64) { varint(field << 3 | wire) }
    mutating func string(_ field: UInt64, _ s: String) {
        key(field, 2); varint(UInt64(s.utf8.count)); bytes += Array(s.utf8)
    }
    mutating func float(_ field: UInt64, _ f: Float) {
        key(field, 5)
        let bits = f.bitPattern
        for i in 0..<4 { bytes.append(UInt8((bits >> (8 * UInt32(i))) & 0xFF)) }
    }
    mutating func double(_ field: UInt64, _ d: Double) {
        key(field, 1)
        let bits = d.bitPattern
        for i in 0..<8 { bytes.append(UInt8((bits >> (8 * UInt64(i))) & 0xFF)) }
    }
    mutating func sint64(_ field: UInt64, _ v: Int64) {
        key(field, 0); varint(UInt64(bitPattern: (v << 1) ^ (v >> 63)))
    }

    var base64: String { Data(bytes).base64EncodedString() }
}

@Suite("QuoteStream decoding")
struct QuoteStreamDecodingTests {
    /// A real message captured from wss://streamer.finance.yahoo.com/?version=2 on 2026-11-17.
    static let capturedBTC = #"{"type":"pricing","message":"CgdCVEMtVVNEFR8oe0cY8JfPir1oIgNVU0QqA0NDQzApOAFF8AsnvkiA4JCc6QFVP+Z9R138/XpHZQAe0sJ9YDx9R7ABgOCQnOkB2AEE4AGA4JCc6QHoAYDgkJzpAfIBA0JUQ4ECAAAAwHUuc0GJAgAA48BmznJC9QIAHtLC/QLwCye+"}"#

    @Test func decodesCapturedMessage() throws {
        let tick = try #require(QuoteStream.decode(Self.capturedBTC))
        #expect(tick.symbol == "BTC-USD")
        #expect(abs(tick.price - 64296.12) < 0.01)
        #expect(abs(try #require(tick.change) - -105.06) < 0.01)
        #expect(abs(try #require(tick.changePercent) - -0.1631) < 0.0001)
        // 2026-11-17 08:40:11 UTC
        #expect(abs(tick.time.timeIntervalSince1970 - 1_794_904_811) < 1)
    }

    @Test func decodesSyntheticMessageAndSkipsUnknownFields() throws {
        var w = ProtoWriter()
        w.string(1, "BZ=F")
        w.string(4, "USD")            // unknown string field
        w.float(2, 92.16)
        w.sint64(3, 1_794_904_811_000)
        w.sint64(9, 123_456)          // unknown varint field
        w.float(8, -0.30)
        w.float(12, -0.28)
        w.double(33, 1.5e12)          // unknown 64-bit field
        w.float(16, 92.44)

        let tick = try #require(QuoteStream.decode(w.base64))
        #expect(tick.symbol == "BZ=F")
        #expect(tick.price == 92.16)
        #expect(tick.change == -0.28)
        #expect(tick.changePercent == -0.3)
        #expect(tick.previousClose == 92.44)
        #expect(tick.time == Date(timeIntervalSince1970: 1_794_904_811))
    }

    @Test func acceptsBareBase64FromOlderStreamVersion() throws {
        var w = ProtoWriter()
        w.string(1, "AAPL")
        w.float(2, 231.4)
        #expect(QuoteStream.decode(w.base64)?.symbol == "AAPL")
    }

    @Test func zeroPreviousCloseIsTreatedAsMissing() throws {
        var w = ProtoWriter()
        w.string(1, "AAPL")
        w.float(2, 231.4)
        w.float(16, 0)
        #expect(try #require(QuoteStream.decode(w.base64)).previousClose == nil)
    }

    @Test func missingTimeFallsBackToNow() throws {
        var w = ProtoWriter()
        w.string(1, "AAPL")
        w.float(2, 231.4)
        let tick = try #require(QuoteStream.decode(w.base64))
        #expect(abs(tick.time.timeIntervalSinceNow) < 5)
    }

    @Test(arguments: [
        #"{"type":"heartbeat","message":"CgdCVEMtVVNE"}"#,  // not a pricing message
        #"{"type":"pricing"}"#,                            // no payload
        "not base64 at all!",
        "",
    ])
    func rejectsNonPricingOrInvalidInput(_ text: String) {
        #expect(QuoteStream.decode(text) == nil)
    }

    @Test func rejectsMessageWithoutPrice() {
        var w = ProtoWriter()
        w.string(1, "AAPL")
        #expect(QuoteStream.decode(w.base64) == nil)
    }

    @Test func rejectsMessageWithoutSymbol() {
        var w = ProtoWriter()
        w.float(2, 231.4)
        #expect(QuoteStream.decode(w.base64) == nil)
    }

    @Test func rejectsTruncatedMessages() {
        var w = ProtoWriter()
        w.string(1, "AAPL")
        w.float(2, 231.4)
        // Cut inside the float, then inside the string.
        #expect(QuoteStream.decodePricingData(Array(w.bytes.dropLast(2))) == nil)
        #expect(QuoteStream.decodePricingData(Array(w.bytes.prefix(4))) == nil)
    }

    @Test func rejectsUnsupportedWireType() {
        // Field 1, wire type 3 (deprecated group start).
        #expect(QuoteStream.decodePricingData([0x0B, 0x00]) == nil)
    }
}
