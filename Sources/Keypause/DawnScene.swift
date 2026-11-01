import AppKit
import SwiftUI

/// The night turning to morning, built from Core Animation layers. Every moving part gets ONE animation that
/// spans the whole session, so the GPU compositor runs it and the app does essentially no per-frame work.
struct DawnScene: NSViewRepresentable {
    let deadline: Date?
    let total: TimeInterval
    let done: Bool

    func makeNSView(context: Context) -> DawnNSView {
        let v = DawnNSView()
        v.configure(deadline: deadline, total: total, done: done)
        return v
    }
    func updateNSView(_ v: DawnNSView, context: Context) { v.configure(deadline: deadline, total: total, done: done) }
}

/// The sky's colors through the night, shared by the scene and by the text-contrast logic.
enum DawnPalette {
    typealias RGB = (CGFloat, CGFloat, CGFloat)
    static let top: [RGB] = [(0.03, 0.05, 0.14), (0.10, 0.10, 0.28), (0.33, 0.27, 0.55), (0.40, 0.58, 0.86)]
    static let bottom: [RGB] = [(0.07, 0.10, 0.24), (0.30, 0.20, 0.45), (0.92, 0.45, 0.45), (1.00, 0.74, 0.40)]

    static func rgb(_ stops: [RGB], _ p: Double) -> RGB {
        let x = min(max(p, 0), 1) * Double(stops.count - 1)
        let i = min(Int(x), stops.count - 2), f = CGFloat(x - Double(i))
        let (a, b) = (stops[i], stops[i + 1])
        return (a.0 + (b.0 - a.0) * f, a.1 + (b.1 - a.1) * f, a.2 + (b.2 - a.2) * f)
    }
    /// WCAG relative luminance (0 = black, 1 = white).
    static func luminance(_ c: RGB) -> Double {
        func lin(_ v: CGFloat) -> Double { let d = Double(v); return d <= 0.03928 ? d / 12.92 : pow((d + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.0) + 0.7152 * lin(c.1) + 0.0722 * lin(c.2)
    }
    /// Text color for the bright morning sky: a deep plum from the sunrise palette (not flat black).
    static let ink: RGB = (0.27, 0.08, 0.30)
    static var inkColor: Color { Color(red: Double(ink.0), green: Double(ink.1), blue: Double(ink.2)) }

    /// Is dark text easier to read than white at this point of the night? `at` is how far down the island the
    /// text sits (0 = top edge, 1 = bottom). Crossover is where white and the plum ink have equal contrast.
    static func prefersDarkText(_ p: Double, at: Double) -> Bool {
        let t = rgb(top, p), b = rgb(bottom, p)
        let mix: RGB = (t.0 + (b.0 - t.0) * CGFloat(at), t.1 + (b.1 - t.1) * CGFloat(at), t.2 + (b.2 - t.2) * CGFloat(at))
        // equal contrast: 1.05/(L+.05) == (L+.05)/(inkL+.05)  =>  L = sqrt(1.05*(inkL+.05)) - .05
        let crossover = (1.05 * (luminance(ink) + 0.05)).squareRoot() - 0.05
        return luminance(mix) > crossover
    }
}

private func lerpColor(_ stops: [DawnPalette.RGB], _ p: Double) -> CGColor {
    let c = DawnPalette.rgb(stops, p)
    return CGColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
}

/// Everything about the scene at one moment of the night (p: 0 = dusk ... 1 = morning).
private struct SceneState {
    let skyTop, skyBottom, hillBack, hillFront: CGColor
    let sunY: CGFloat, sunOpacity: Float, glowOpacity: Float          // sunY as a fraction of height from the top
    let moonX: CGFloat, moonY: CGFloat, moonOpacity: Float            // fractions of width / height from the top
    let starsOpacity: Float, cloudAlpha: Float

    init(_ p: Double) {
        skyTop = lerpColor(DawnPalette.top, p)
        skyBottom = lerpColor(DawnPalette.bottom, p)
        hillBack = lerpColor([(0.10, 0.09, 0.26), (0.30, 0.18, 0.40), (0.55, 0.30, 0.42)], p)
        hillFront = lerpColor([(0.05, 0.04, 0.14), (0.16, 0.10, 0.26), (0.30, 0.17, 0.28)], p)
        sunY = 1.40 - 1.00 * p            // ends behind Kip's head, like a halo
        sunOpacity = Float(min(1, p * 2.2))
        glowOpacity = Float(0.05 + 0.55 * p)
        moonX = 0.74 + 0.05 * p
        moonY = 0.22 + 1.0 * p
        moonOpacity = Float(max(0, 1 - p / 0.72))
        starsOpacity = Float(max(0, 1 - p * 1.45))
        cloudAlpha = Float(0.16 + 0.30 * p)
    }
}

final class DawnNSView: NSView {
    private var deadline: Date?
    private var total: TimeInterval = 0
    private var done = false
    private var builtKey = ""

    private let sky = CAGradientLayer()
    private let stars = CALayer()
    private let moon = CALayer()
    private let glow = CAGradientLayer()
    private let sun = CALayer()
    private let hillBack = CAShapeLayer()
    private let hillFront = CAShapeLayer()
    private var clouds: [(layer: CALayer, scale: CGFloat, speed: CGFloat, row: CGFloat, phase: CGFloat)] = []

    // MARK: setup (once)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        let root = layer!
        root.masksToBounds = true

        sky.startPoint = CGPoint(x: 0.5, y: 1); sky.endPoint = CGPoint(x: 0.5, y: 0)   // top -> bottom (layer y is up)
        root.addSublayer(sky)

        func frac(_ x: Double) -> Double { x - floor(x) }
        root.addSublayer(stars)
        for i in 0..<30 {
            let s = CALayer()
            let r = 0.7 + frac(Double(i) * 0.37) * 1.3
            s.bounds = CGRect(x: 0, y: 0, width: r * 2, height: r * 2)
            s.cornerRadius = r
            s.backgroundColor = NSColor.white.cgColor
            s.setValue(frac(sin(Double(i) * 12.9898) * 43758.5453), forKey: "fx")
            s.setValue(frac(sin(Double(i) * 78.233) * 12345.678) * 0.7, forKey: "fy")
            let tw = CABasicAnimation(keyPath: "opacity")      // twinkle: compositor-driven, no app work
            tw.fromValue = 0.3; tw.toValue = 1.0
            tw.duration = 0.8 + frac(Double(i) * 0.61) * 1.6
            tw.autoreverses = true; tw.repeatCount = .infinity
            tw.timeOffset = frac(Double(i) * 0.29) * 2
            s.add(tw, forKey: "twinkle")
            stars.addSublayer(s)
        }

        moon.bounds = CGRect(x: 0, y: 0, width: 28, height: 28)
        moon.contents = Self.crescentImage()
        moon.contentsScale = 2
        root.addSublayer(moon)

        let big = [(2.0, 2.0, 9.0), (16, -6, 14), (34, -2, 12), (48, 3, 8), (-8, 4, 6)]
        let small = [(0.0, 0.0, 8.0), (13, -5, 11), (27, 0, 7)]
        let defs: [(CGFloat, CGFloat, CGFloat, CGFloat, [(Double, Double, Double)])] = [   // row, scale, speed, phase, lobes
            (0.19, 0.8, 5, 0, big), (0.25, 0.7, 8, 170, small), (0.30, 0.5, 3.5, 340, small)]   // a thin strip above Kip and the text
        for d in defs {
            let c = CALayer()
            c.bounds = CGRect(x: 0, y: 0, width: 96 * d.1, height: 34 * d.1)
            c.contents = Self.cloudImage(lobes: d.4, scale: d.1)
            c.contentsScale = 2
            root.addSublayer(c)
            clouds.append((c, d.1, d.2, d.0, d.3))
        }

        glow.type = .radial
        glow.bounds = CGRect(x: 0, y: 0, width: 340, height: 340)
        glow.startPoint = CGPoint(x: 0.5, y: 0.5); glow.endPoint = CGPoint(x: 1, y: 1)
        glow.colors = [NSColor(srgbRed: 1, green: 0.74, blue: 0.42, alpha: 0.95).cgColor,
                       NSColor(srgbRed: 1, green: 0.5, blue: 0.35, alpha: 0.30).cgColor,
                       NSColor(srgbRed: 1, green: 0.5, blue: 0.35, alpha: 0).cgColor]
        glow.locations = [0, 0.4, 1]
        root.addSublayer(glow)

        sun.bounds = CGRect(x: 0, y: 0, width: 60, height: 60)
        sun.cornerRadius = 30
        sun.backgroundColor = NSColor(srgbRed: 1, green: 0.9, blue: 0.62, alpha: 1).cgColor
        root.addSublayer(sun)

        root.addSublayer(hillBack)
        root.addSublayer(hillFront)
    }
    required init?(coder: NSCoder) { fatalError() }

    private static func bitmap(_ size: NSSize, _ draw: @escaping (CGContext) -> Void) -> CGImage? {
        let img = NSImage(size: size, flipped: false) { _ in draw(NSGraphicsContext.current!.cgContext); return true }
        var rect = CGRect(origin: .zero, size: size)
        return img.cgImage(forProposedRect: &rect, context: nil, hints: [.ctm: AffineTransform(scale: 2)])
    }
    private static func crescentImage() -> CGImage? {
        bitmap(NSSize(width: 28, height: 28)) { ctx in
            ctx.setFillColor(NSColor(srgbRed: 1, green: 0.93, blue: 0.7, alpha: 1).cgColor)
            ctx.fillEllipse(in: CGRect(x: 2, y: 2, width: 24, height: 24))
            ctx.setBlendMode(.clear)
            ctx.fillEllipse(in: CGRect(x: 9, y: 5, width: 24, height: 24))
        }
    }
    /// A puffy cloud: overlapping lobes on a flat base, with a tinted underside, baked into one bitmap.
    private static func cloudImage(lobes: [(Double, Double, Double)], scale s: CGFloat) -> CGImage? {
        bitmap(NSSize(width: 96 * s, height: 34 * s)) { ctx in
            func shape(dy: CGFloat) -> CGPath {
                let p = CGMutablePath()
                for (px, py, r) in lobes {
                    p.addEllipse(in: CGRect(x: (14 + px - r) * s, y: (14 - py - r + dy) * s + 4 * s, width: 2 * r * s, height: 2 * r * s))
                }
                p.addRoundedRect(in: CGRect(x: 0, y: (4 + dy) * s, width: 74 * s, height: 12 * s), cornerWidth: 6 * s, cornerHeight: 6 * s)
                return p
            }
            ctx.setFillColor(NSColor(srgbRed: 0.55, green: 0.42, blue: 0.62, alpha: 0.55).cgColor)   // underside
            ctx.addPath(shape(dy: -2.5)); ctx.fillPath()
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.addPath(shape(dy: 0)); ctx.fillPath()
        }
    }

    // MARK: configuration (cheap; only rebuilds when something real changed)

    func configure(deadline: Date?, total: TimeInterval, done: Bool) {
        self.deadline = deadline; self.total = total; self.done = done
        rebuildIfNeeded()
    }

    override func layout() {
        super.layout()
        rebuildIfNeeded(force: bounds.size.debugDescription != sizeKey)
    }
    private var sizeKey = ""

    private func rebuildIfNeeded(force: Bool = false) {
        guard bounds.width > 10, bounds.height > 10 else { return }
        let key = "\(done)|\(deadline?.timeIntervalSinceReferenceDate ?? 0)|\(bounds.size)"
        guard force || key != builtKey else { return }
        builtKey = key; sizeKey = bounds.size.debugDescription
        build()
    }

    // MARK: build: geometry + one long animation per property

    private func build() {
        let w = bounds.width, h = bounds.height
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        for l in [sky, moon, glow, sun, stars, hillBack, hillFront] { l.removeAllAnimations() }
        clouds.forEach { $0.layer.removeAllAnimations() }
        // restart the star twinkles that removeAllAnimations just cleared
        for (i, s) in (stars.sublayers ?? []).enumerated() {
            let tw = CABasicAnimation(keyPath: "opacity")
            tw.fromValue = 0.3; tw.toValue = 1.0; tw.duration = 0.8 + Double(i % 7) * 0.23
            tw.autoreverses = true; tw.repeatCount = .infinity; tw.timeOffset = Double(i % 5) * 0.4
            s.add(tw, forKey: "twinkle")
        }

        sky.frame = bounds
        stars.frame = bounds
        for s in stars.sublayers ?? [] {
            s.position = CGPoint(x: (s.value(forKey: "fx") as! Double) * w, y: h - (s.value(forKey: "fy") as! Double) * h)
        }
        sun.position = CGPoint(x: w * 0.16, y: 0)     // y is animated below
        glow.position = sun.position

        for (path, layer, base, amp, waves, phase) in [(CGMutablePath(), hillBack, 14.0, 6.0, 2.2, 0.9),
                                                       (CGMutablePath(), hillFront, 6.0, 4.0, 3.1, 1.6)] {
            path.move(to: CGPoint(x: 0, y: 0))
            for i in 0...64 {
                let x = Double(i) / 64
                path.addLine(to: CGPoint(x: x * w, y: base + amp * sin(x * .pi * waves + phase)))
            }
            path.addLine(to: CGPoint(x: w, y: 0)); path.closeSubpath()
            layer.frame = bounds; layer.path = path
        }

        // progress now and how long is left
        let remaining = done ? 0 : max(0, deadline?.timeIntervalSinceNow ?? 0)
        let p0: Double = done ? 1 : (total > 0 ? min(max(1 - remaining / total, 0), 1) : 1)
        let end = SceneState(1)
        let animated = !done && remaining > 0.05

        // clouds drift continuously (independent of progress)
        for c in clouds {
            let span = w + 180
            c.layer.position = CGPoint(x: -90, y: h - h * c.row)
            let drift = CABasicAnimation(keyPath: "position.x")
            drift.fromValue = -90; drift.toValue = span - 90
            drift.duration = span / Double(c.speed); drift.repeatCount = .infinity
            drift.timeOffset = Double(c.phase) / Double(c.speed)
            c.layer.add(drift, forKey: "drift")
        }

        func apply(_ s: SceneState) {   // static state (also the final model values)
            sky.colors = [s.skyTop, s.skyBottom]
            hillBack.fillColor = s.hillBack; hillFront.fillColor = s.hillFront
            sun.position.y = h - h * s.sunY; glow.position.y = sun.position.y
            sun.opacity = s.sunOpacity; glow.opacity = s.glowOpacity
            moon.position = CGPoint(x: w * s.moonX, y: h - h * s.moonY); moon.opacity = s.moonOpacity
            stars.opacity = s.starsOpacity
            for c in clouds { c.layer.opacity = s.cloudAlpha * Float(0.7 + 0.3 * c.scale) }
        }
        apply(animated ? SceneState(p0) : end)
        guard animated else { return }

        // one keyframe animation per property, spanning the rest of the night; the compositor does the rest
        let n = 24
        let states = (0...n).map { SceneState(p0 + (1 - p0) * Double($0) / Double(n)) }
        func run(_ layer: CALayer, _ keyPath: String, _ values: [Any], final: Any) {
            let a = CAKeyframeAnimation(keyPath: keyPath)
            a.values = values; a.duration = remaining; a.calculationMode = .linear
            a.timingFunction = CAMediaTimingFunction(name: .linear)
            a.fillMode = .forwards; a.isRemovedOnCompletion = false
            layer.add(a, forKey: "dawn-" + keyPath)
        }
        run(sky, "colors", states.map { [$0.skyTop, $0.skyBottom] }, final: 0)
        run(hillBack, "fillColor", states.map { $0.hillBack }, final: 0)
        run(hillFront, "fillColor", states.map { $0.hillFront }, final: 0)
        run(sun, "position.y", states.map { h - h * $0.sunY }, final: 0)
        run(glow, "position.y", states.map { h - h * $0.sunY }, final: 0)
        run(sun, "opacity", states.map { $0.sunOpacity }, final: 0)
        run(glow, "opacity", states.map { $0.glowOpacity }, final: 0)
        run(moon, "position", states.map { NSValue(point: NSPoint(x: w * $0.moonX, y: h - h * $0.moonY)) }, final: 0)
        run(moon, "opacity", states.map { $0.moonOpacity }, final: 0)
        run(stars, "opacity", states.map { $0.starsOpacity }, final: 0)
        for c in clouds { run(c.layer, "opacity", states.map { $0.cloudAlpha * Float(0.7 + 0.3 * c.scale) }, final: 0) }
        // after the animations end, the model values must already be the morning state
        apply(end)
    }
}
