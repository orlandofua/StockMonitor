import Foundation

/// Number formatting for prices and changes (see docs/adr/0006).
enum Formatting {
    /// Price with 2 decimals, or 4 decimals for values below 1 (low-priced assets).
    static func price(_ value: Double, locale: Locale = .current) -> String {
        number(value, decimals: abs(value) >= 1 || value == 0 ? 2 : 4, locale: locale)
    }

    /// Point change, always rounded to 2 decimals with explicit sign (e.g. +0.26, -1.05).
    static func change(_ value: Double, locale: Locale = .current) -> String {
        var rounded = (value * 100).rounded() / 100
        if rounded == 0 { rounded = 0 } // avoid "-0.00"
        return (rounded >= 0 ? "+" : "") + number(rounded, decimals: 2, locale: locale)
    }

    /// Percent change with 2 decimals and explicit sign (e.g. -0.30%).
    static func percent(_ value: Double) -> String {
        var rounded = (value * 100).rounded() / 100
        if rounded == 0 { rounded = 0 }
        return String(format: "%+.2f%%", rounded)
    }

    static func number(_ value: Double, decimals: Int, locale: Locale = .current) -> String {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .decimal
        f.roundingMode = .halfUp // half away from zero, matching `change` (NumberFormatter defaults to half-even)
        f.minimumFractionDigits = decimals
        f.maximumFractionDigits = decimals
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
