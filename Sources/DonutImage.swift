import AppKit

/// Renders a small filled-ring (donut) icon as NSImage. Used both:
///   • inline in the menu bar title via NSTextAttachment
///   • inside the popup if we ever want bigger versions
enum DonutImage {

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
