import SwiftUI

/// Heading-up compass dial: you at the centre, landmarks placed by relative bearing
/// (angle) and distance (radius). Glance at it and you know which way to look.
///
/// Knows nothing about driving or flying — it renders an `Observer` and an
/// `ObservationMode`, so the same view serves every mode.
struct DialView: View {
    let observer: Observer
    let mode: ObservationMode
    let visible: [VisibleLandmark]
    let radiusKm: Double
    let hasFix: Bool

    var body: some View {
        ZStack {
            Canvas { ctx, size in draw(ctx: &ctx, size: size) }
            Image(systemName: mode.glyph)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.amber)
                .rotationEffect(.degrees(mode.glyphRotationDeg))
                .shadow(color: Theme.amber.opacity(0.7), radius: 6)
                .opacity(hasFix ? 1 : 0.25)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityIdentifier("compassDial")
    }

    /// Screen point for a relative bearing (degrees, 0 = up) at a radius.
    private func point(center: CGPoint, rel: Double, r: Double) -> CGPoint {
        let a = Geo.rad(rel)
        return CGPoint(x: center.x + sin(a) * r, y: center.y - cos(a) * r)
    }

    /// sqrt scaling: spreads out the near field, where detail matters most.
    private func screenRadius(forDist d: Double, outerR: Double) -> Double {
        guard radiusKm > 0 else { return 0 }
        return outerR * sqrt(min(d / radiusKm, 1))
    }

    private func draw(ctx: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let outerR = min(size.width, size.height) / 2 - 26
        let heading = observer.headingDeg

        let outerRect = CGRect(x: center.x - outerR, y: center.y - outerR,
                               width: outerR * 2, height: outerR * 2)
        ctx.fill(Path(ellipseIn: outerRect), with: .color(Theme.panel))
        ctx.stroke(Path(ellipseIn: outerRect), with: .color(Theme.line), lineWidth: 1.5)

        // Range rings. With sqrt scaling a ring at fraction f sits at f² of the radius.
        for f in [1.0 / 3.0, 2.0 / 3.0] {
            let r = outerR * f
            let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            ctx.stroke(Path(ellipseIn: rect), with: .color(Theme.line.opacity(0.7)),
                       style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            ctx.draw(Text(formatDistance(radiusKm * f * f))
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(Theme.dim),
                     at: CGPoint(x: center.x, y: center.y - r - 7), anchor: .center)
        }
        ctx.draw(Text(formatDistance(radiusKm))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(Theme.dim),
                 at: CGPoint(x: center.x, y: center.y - outerR + 9), anchor: .center)

        // Compass ticks and cardinals, rotating so the current heading is always up.
        let cardinals: [Int: String] = [0: "N", 90: "E", 180: "S", 270: "W"]
        for tickDeg in stride(from: 0, to: 360, by: 10) {
            let rel = Geo.relativeBearing(Double(tickDeg), heading: heading)
            let major = tickDeg % 30 == 0
            var tick = Path()
            tick.move(to: point(center: center, rel: rel, r: outerR))
            tick.addLine(to: point(center: center, rel: rel, r: outerR - (major ? 10 : 5)))
            ctx.stroke(tick,
                       with: .color(major ? Theme.text.opacity(0.7) : Theme.dim.opacity(0.5)),
                       lineWidth: major ? 1.5 : 1)
            if let letter = cardinals[tickDeg] {
                ctx.draw(Text(letter)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(letter == "N" ? Theme.cyan : Theme.dim),
                         at: point(center: center, rel: rel, r: outerR + 14), anchor: .center)
            }
        }

        // Lubber line: the direction of travel, always at 12 o'clock.
        var lubber = Path()
        lubber.move(to: CGPoint(x: center.x, y: center.y - outerR - 2))
        lubber.addLine(to: CGPoint(x: center.x - 6, y: center.y - outerR - 12))
        lubber.addLine(to: CGPoint(x: center.x + 6, y: center.y - outerR - 12))
        lubber.closeSubpath()
        ctx.fill(lubber, with: .color(Theme.amber))

        guard hasFix else {
            ctx.draw(Text("waiting for GPS…")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.dim),
                     at: CGPoint(x: center.x, y: center.y + 24), anchor: .center)
            return
        }

        // Landmarks. Solid = plausibly in sight; hollow = in range but over the horizon.
        var labelled: [CGPoint] = []
        for item in visible {
            let r = screenRadius(forDist: item.distanceKm, outerR: outerR)
            let p = point(center: center, rel: item.relativeBearingDeg, r: r)
            let color = Theme.color(for: item.landmark.type)
            let isTier1 = item.landmark.tier == 1
            let dotR: CGFloat = isTier1 ? 4.5 : 3
            let dotRect = CGRect(x: p.x - dotR, y: p.y - dotR, width: dotR * 2, height: dotR * 2)

            if item.isLineOfSight {
                if isTier1 {
                    ctx.fill(Path(ellipseIn: dotRect.insetBy(dx: -3, dy: -3)),
                             with: .color(color.opacity(0.25)))
                }
                ctx.fill(Path(ellipseIn: dotRect), with: .color(color))
            } else {
                ctx.stroke(Path(ellipseIn: dotRect), with: .color(color.opacity(0.55)), lineWidth: 1)
            }

            // Label budget: nearest/most notable first, skipping anything that would collide.
            let crowded = labelled.contains { hypot($0.x - p.x, $0.y - p.y) < 40 }
            guard labelled.count < 10, !crowded else { continue }
            labelled.append(p)

            let below = p.y > center.y
            let labelY: CGFloat = below ? p.y + 8 : p.y - 8
            let anchor: UnitPoint = below ? .top : .bottom
            ctx.draw(Text(item.landmark.name)
                        .font(.system(size: 9.5, weight: isTier1 ? .semibold : .regular))
                        .foregroundStyle(item.isLineOfSight ? Theme.text : Theme.text.opacity(0.55)),
                     at: CGPoint(x: p.x, y: labelY), anchor: anchor)
            ctx.draw(Text(formatDistance(item.distanceKm))
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(Theme.dim),
                     at: CGPoint(x: p.x, y: labelY + (below ? 13 : -13)), anchor: anchor)
        }
    }
}
