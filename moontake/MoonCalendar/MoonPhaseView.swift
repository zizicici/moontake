import UIKit

/// Schematic phase, deliberately independent of the Moon's apparent sky orientation.
final class MoonPhaseView: UIView {
    var angle: Double = 0 { didSet { setNeedsDisplay() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        let radius = max(0, min(bounds.width, bounds.height) / 2 - 1)
        guard radius > 0 else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let disc = UIBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius,
                                             width: radius * 2, height: radius * 2))
        UIColor.moonColor.withAlphaComponent(0.12).setFill()
        disc.fill()

        let phase = angle.truncatingRemainder(dividingBy: 360)
        let waxing = phase < 180
        let terminator = cos(phase * .pi / 180)
        let lit = UIBezierPath()
        // Each horizontal slice extends from the terminator to the lit limb.
        for step in 0...80 {
            let y = -radius + 2 * radius * CGFloat(step) / 80
            let limb = sqrt(max(0, radius * radius - y * y))
            let x = waxing ? limb : -limb
            let point = CGPoint(x: center.x + x, y: center.y + y)
            if step == 0 { lit.move(to: point) } else { lit.addLine(to: point) }
        }
        for step in (0...80).reversed() {
            let y = -radius + 2 * radius * CGFloat(step) / 80
            let limb = sqrt(max(0, radius * radius - y * y))
            let x = CGFloat(terminator) * limb * (waxing ? 1 : -1)
            lit.addLine(to: CGPoint(x: center.x + x, y: center.y + y))
        }
        lit.close()
        UIColor.moonColor.setFill()
        lit.fill()
        UIColor.moonColor.withAlphaComponent(0.3).setStroke()
        disc.lineWidth = 0.75
        disc.stroke()
    }
}
