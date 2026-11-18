import AppKit

/// Draws a Stats-style menu bar cell:
///
///     BZ=F
///     92.16 [-0.28]
///
/// Small symbol label on top, bold price below, colored change badge beside the price.
/// A stale quote (issue #9) is drawn with gray text and a gray badge.
enum TickerImage {
    static let up = NSColor(srgbRed: 0.20, green: 0.70, blue: 0.35, alpha: 1)
    static let down = NSColor(srgbRed: 0.93, green: 0.30, blue: 0.27, alpha: 1)
    static let stale = NSColor.systemGray

    /// The badge fill: gray when stale, otherwise green for up and red for down.
    static func badgeColor(isUp: Bool, isStale: Bool) -> NSColor {
        isStale ? stale : (isUp ? up : down)
    }

    /// The color of the symbol and price text. Dynamic, so it follows the menu bar appearance.
    static func textColor(isStale: Bool) -> NSColor {
        isStale ? .secondaryLabelColor : .labelColor
    }

    static func make(symbol: String, price: String, change: String?, isUp: Bool, isStale: Bool = false) -> NSImage {
        let height = max(NSStatusBar.system.thickness, 22)
        let labelFont = NSFont.systemFont(ofSize: 8, weight: .medium)
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .semibold)
        let badgeFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .bold)

        let text = textColor(isStale: isStale)
        let label = NSAttributedString(string: symbol, attributes: [.font: labelFont, .foregroundColor: text])
        let value = NSAttributedString(string: price, attributes: [.font: valueFont, .foregroundColor: text])
        let badge = change.map { NSAttributedString(string: $0, attributes: [.font: badgeFont, .foregroundColor: NSColor.white]) }

        let badgePad: CGFloat = 3
        let badgeGap: CGFloat = 4
        let badgeHeight: CGFloat = 11
        let badgeWidth = badge.map { ceil($0.size().width) + badgePad * 2 } ?? 0
        let bottomWidth = ceil(value.size().width) + (badge == nil ? 0 : badgeGap + badgeWidth)
        let width = ceil(max(label.size().width, bottomWidth)) + 2

        // Baseline positioning (flipped: y grows downward; draw(at:) places line top at y).
        let labelY = 1.5 + labelFont.capHeight - labelFont.ascender
        let valueBaseline = height - 3
        let valueY = valueBaseline - valueFont.ascender

        let image = NSImage(size: NSSize(width: width, height: height), flipped: true) { _ in
            label.draw(at: NSPoint(x: 1, y: labelY))
            value.draw(at: NSPoint(x: 1, y: valueY))

            if let badge {
                let capMid = valueBaseline - valueFont.capHeight / 2
                let rect = NSRect(x: width - badgeWidth, y: round(capMid - badgeHeight / 2),
                                  width: badgeWidth, height: badgeHeight)
                badgeColor(isUp: isUp, isStale: isStale).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 2.5, yRadius: 2.5).fill()
                let size = badge.size()
                badge.draw(at: NSPoint(x: rect.minX + badgePad, y: rect.midY - size.height / 2))
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
