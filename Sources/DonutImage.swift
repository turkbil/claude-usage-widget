import AppKit

/// Renders a small filled-ring (donut) icon as NSImage. Used both:
///   • inline in the menu bar title via NSTextAttachment
///   • inside the popup if we ever want bigger versions
enum DonutImage {

    /// Ring filled to `fill` with the percentage number inside, sized for the menu
    /// bar. Drawn on demand so the number follows light/dark mode.
    static func ringWithNumber(fill: Double, number: Int, color: NSColor, size: CGFloat = 22) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let line: CGFloat = 2
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = size / 2 - line / 2
            ctx.setLineWidth(line)
            ctx.setStrokeColor(NSColor.labelColor.withAlphaComponent(0.2).cgColor)
            ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            ctx.strokePath()
            let pct = max(0, min(1, fill))
            if pct > 0 {
                ctx.setStrokeColor(color.cgColor)
                ctx.setLineCap(.butt)
                ctx.addArc(center: center, radius: radius, startAngle: .pi / 2,
                           endAngle: .pi / 2 - CGFloat(pct) * .pi * 2, clockwise: true)
                ctx.strokePath()
            }
            // Biggest bold size that fits inside the ring.
            let text = "\(number)"
            let maxW = (radius - line) * 2 - 1
            var fontSize: CGFloat = 12.5
            var attrs: [NSAttributedString.Key: Any] = [:]
            repeat {
                attrs = [.font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold),
                         .foregroundColor: NSColor.labelColor]
                if (text as NSString).size(withAttributes: attrs).width <= maxW { break }
                fontSize -= 0.5
            } while fontSize > 6
            let sz = (text as NSString).size(withAttributes: attrs)
            (text as NSString).draw(at: NSPoint(x: rect.midX - sz.width / 2, y: rect.midY - sz.height / 2), withAttributes: attrs)
            return true
        }
    }

    /// fill: 0…1 (e.g. 0.32 for 32%)
    /// color: any NSColor; an alpha-dimmed track is drawn underneath
    /// size: square edge in points (14 fits the menu bar text nicely)
    /// lineWidth: ring thickness in points
    static func make(fill: Double, color: NSColor, size: CGFloat = 14, lineWidth: CGFloat = 3) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        defer { image.unlockFocus() }

        guard let ctx = NSGraphicsContext.current?.cgContext else { return image }
        ctx.setShouldAntialias(true)
        ctx.setAllowsAntialiasing(true)

        let inset = lineWidth / 2
        let center = CGPoint(x: size / 2, y: size / 2)
        let radius = size / 2 - inset

        // Track (dimmer version of label color so it adapts to light/dark).
        ctx.setStrokeColor(NSColor.labelColor.withAlphaComponent(0.18).cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.strokePath()

        // Fill arc.
        let pct = max(0, min(1, fill))
        guard pct > 0 else { return image }

        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)

        // Start at 12 o'clock (CGContext angle 90°), go clockwise.
        // In CGContext, angles increase counter-clockwise from +X axis.
        // We want clockwise = -delta in math terms but `clockwise: true` already handles it.
        let startAngle: CGFloat = .pi / 2          // top
        let sweep = CGFloat(pct) * .pi * 2
        let endAngle = startAngle - sweep
        ctx.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: true
        )
        ctx.strokePath()

        return image
    }
}
