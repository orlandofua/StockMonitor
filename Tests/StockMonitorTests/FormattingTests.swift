import Foundation
import Testing
@testable import StockMonitor

@Suite("Formatting")
struct FormattingTests {
    static let us = Locale(identifier: "en_US")

    @Test(arguments: [
        (-0.25999999, "-0.26"),   // float noise from subtracting prices
        (-0.28, "-0.28"),
        (0.125, "+0.13"),         // half rounds away from zero
        (-0.125, "-0.13"),
        (0.004, "+0.00"),
        (-0.004, "+0.00"),        // no "-0.00"
        (0, "+0.00"),
        (1234.5, "+1,234.50"),
        (-105.058594, "-105.06"),
    ])
    func changeRoundsToTwoDecimals(_ value: Double, _ expected: String) {
        #expect(Formatting.change(value, locale: Self.us) == expected)
    }

    @Test(arguments: [
        (92.16, "92.16"),
        (64296.121094, "64,296.12"),
        (0.12346, "0.1235"),      // low-priced assets keep 4 decimals
        (0.5, "0.5000"),
        (0, "0.00"),
        (1, "1.00"),
    ])
    func priceDecimals(_ value: Double, _ expected: String) {
        #expect(Formatting.price(value, locale: Self.us) == expected)
    }

    @Test(arguments: [
        (-0.2999, "-0.30%"),
        (1.234, "+1.23%"),
        (-0.001, "+0.00%"),
        (0, "+0.00%"),
    ])
    func percentRoundsToTwoDecimals(_ value: Double, _ expected: String) {
        #expect(Formatting.percent(value) == expected)
    }
}
