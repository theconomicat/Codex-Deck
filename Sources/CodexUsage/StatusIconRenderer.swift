import AppKit
import CodexUsageCore

final class StatusIconRenderer {
    private let sidePadding: CGFloat = 2
    private let ringDiameter: CGFloat = 23
    private let ringLineWidth: CGFloat = 2.3
    private let ringGap: CGFloat = 14

    private func imageSize(count: Int) -> NSSize {
        NSSize(
            width: sidePadding * 2 + ringDiameter * CGFloat(count) + ringGap * CGFloat(max(0, count - 1)),
            height: 24
        )
    }

    func image(for snapshot: CodexUsageSnapshot) -> NSImage {
        let percents = snapshot.windows.map { $0.isExpired() ? nil : $0.remainingPercent }
        return render(percents: percents.isEmpty ? [nil] : percents)
    }

    func placeholderImage() -> NSImage { render(percents: [nil]) }

    private func render(percents: [Double?]) -> NSImage {
        NSImage(size: imageSize(count: percents.count), flipped: false) { [self] rect in
            for (index, percent) in percents.enumerated() {
                let centerX = sidePadding + ringDiameter / 2 + CGFloat(index) * (ringDiameter + ringGap)
                let text = percent.map { String(Int($0.rounded())) } ?? "--"
                drawRing(in: rect, centerX: centerX, percent: percent ?? 0, text: text)
            }
            return true
        }
    }

    private func drawRing(in rect: NSRect, centerX: CGFloat, percent: Double, text: String) {
        let center = NSPoint(x: centerX, y: rect.midY)
        let radius = ringDiameter / 2 - ringLineWidth / 2

        let background = NSBezierPath()
        background.lineWidth = ringLineWidth
        background.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        NSColor.separatorColor.withAlphaComponent(0.45).setStroke()
        background.stroke()

        let progress = NSBezierPath()
        progress.lineCapStyle = .round
        progress.lineWidth = ringLineWidth
        let clamped = max(0, min(100, percent))
        progress.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 90,
            endAngle: 90 - CGFloat(clamped / 100 * 360),
            clockwise: true
        )
        color(for: clamped).setStroke()
        progress.stroke()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: text.count > 2 ? 7.2 : 8.2, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributed.size()
        attributed.draw(at: NSPoint(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2 - 0.5))
    }

    private func color(for percent: Double) -> NSColor {
        if percent >= 65 {
            return NSColor(calibratedRed: 0.16, green: 0.80, blue: 0.31, alpha: 0.9)
        }
        if percent >= 35 {
            return NSColor(calibratedRed: 1.00, green: 0.73, blue: 0.18, alpha: 0.9)
        }
        if percent >= 15 {
            return NSColor(calibratedRed: 1.00, green: 0.62, blue: 0.18, alpha: 0.9)
        }
        return NSColor(calibratedRed: 1.00, green: 0.37, blue: 0.34, alpha: 0.9)
    }
}
