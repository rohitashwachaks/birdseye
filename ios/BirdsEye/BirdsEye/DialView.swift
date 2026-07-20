import SwiftUI

/// The circular compass dial: heading-up, you at the center, landmarks plotted
/// by relative bearing (angle) and distance (radius). Glance at it and you know
/// exactly where to look out the window.
struct DialView: View {
    let snapshot: Snapshot
    let visible: [VisibleLandmark]
    let seatSide: SeatSide?      // highlight "your window" sector in flight mode
    let isDrive: Bool

    var body: some View {
        ZStack {
            Canvas { ctx, size in
                draw(ctx: &ctx, size: size)
            }
            Image(systemName: isDrive ? "car.fill" : "airplane")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.amber)
                .rotationEffect(isDrive ? .zero : .degrees(-90))
                .shadow(color: Theme.amber.opacity(0.7), radius: 6)
                .opacity(snapshot.hasFix ? 1 : 0.25)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // Screen point for a relative bearing (deg, 0 = up) at a radius.
    private func point(center: CGPoint, rel: Double, r: Double) -> CGPoint {
        let a = Geo.rad(rel)
        return CGPoint(x: center.x + sin(a) * r, y: center.y - cos(a) * r)
    }

    // sqrt distance scaling: spreads out the near field where detail matters
    private func radius(forDist d: Double, outerR: Double) -> Double {
        guard snapshot.rangeKm > 0 else { return 0 }
        return outerR * sqrt(min(d / snapshot.rangeKm, 1))
    }

    private func draw(ctx: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let outerR = min(size.width, size.height) / 2 - 26
        let heading = snapshot.headingDeg

        // dial background
        let outerRect = CGRect(x: center.x - outerR, y: center.y - outerR, width: outerR * 2, height: outerR * 2)
        ctx.fill(Path(ellipseIn: outerRect), with: .color(Theme.panel))
        ctx.stroke(Path(ellipseIn: outerRect), with: .color(Theme.line), lineWidth: 1.5)

        // "your window" sector (flight mode)
        if let side = seatSide, !isDrive {
            let mid = side.bearingOffset          // -90 (left) or +90 (right), relative
            var wedge = Path()
            wedge.move(to: center)
            wedge.addArc(
                center: center, radius: outerR,
                startAngle: .degrees(mid - 60 - 90), endAngle: .degrees(mid + 60 - 90),
                clockwise: false
            )
            wedge.closeSubpath()
            ctx.fill(wedge, with: .color(Theme.amber.opacity(0.07)))
            let labelPt = point(center: center, rel: mid, r: outerR * 0.86)
            ctx.draw(
                Text("YOUR WINDOW")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.amber.opacity(0.8)),
                at: labelPt, anchor: .center
            )
        }

        // range rings (radii 1/3 and 2/3; sqrt scaling → distance = range/9, 4·range/9)
        for f in [1.0 / 3.0, 2.0 / 3.0] {
            let r = outerR * f
            let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            ctx.stroke(Path(ellipseIn: rect), with: .color(Theme.line.opacity(0.7)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            let dKm = snapshot.rangeKm * f * f
            ctx.draw(
                Text("\(Int(dKm.rounded())) km")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(Theme.dim),
                at: CGPoint(x: center.x, y: center.y - r - 7), anchor: .center
            )
        }
        ctx.draw(
            Text("\(Int(snapshot.rangeKm.rounded())) km")
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(Theme.dim),
            at: CGPoint(x: center.x, y: center.y - outerR + 9), anchor: .center
        )

        // tick marks + cardinal letters (rotate with heading; up = current track)
        for tickDeg in stride(from: 0, to: 360, by: 10) {
            let rel = Geo.relativeBearing(Double(tickDeg), heading: heading)
            let major = tickDeg % 30 == 0
            let p1 = point(center: center, rel: rel, r: outerR)
            let p2 = point(center: center, rel: rel, r: outerR - (major ? 10 : 5))
            var tick = Path()
            tick.move(to: p1)
            tick.addLine(to: p2)
            ctx.stroke(tick, with: .color(major ? Theme.text.opacity(0.7) : Theme.dim.opacity(0.5)), lineWidth: major ? 1.5 : 1)

            let cardinals: [Int: String] = [0: "N", 90: "E", 180: "S", 270: "W"]
            if let letter = cardinals[tickDeg] {
                let lp = point(center: center, rel: rel, r: outerR + 14)
                ctx.draw(
                    Text(letter)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(letter == "N" ? Theme.cyan : Theme.dim),
                    at: lp, anchor: .center
                )
            }
        }

        // heading marker (lubber line at 12 o'clock)
        var lubber = Path()
        lubber.move(to: CGPoint(x: center.x, y: center.y - outerR - 2))
        lubber.addLine(to: CGPoint(x: center.x - 6, y: center.y - outerR - 12))
        lubber.addLine(to: CGPoint(x: center.x + 6, y: center.y - outerR - 12))
        lubber.closeSubpath()
        ctx.fill(lubber, with: .color(Theme.amber))

        guard snapshot.hasFix else {
            ctx.draw(
                Text("waiting for position…")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.dim),
                at: CGPoint(x: center.x, y: center.y + 24), anchor: .center
            )
            return
        }

        // landmarks: dot for everything, labels for the top few without crowding
        var labeledPoints: [CGPoint] = []
        for item in visible {
            let r = radius(forDist: item.distKm, outerR: outerR)
            let p = point(center: center, rel: item.rel, r: r)
            let color = Theme.color(for: item.landmark.type)
            let isTier1 = item.landmark.tier == 1
            let dotR: CGFloat = isTier1 ? 4.5 : 3
            let dotRect = CGRect(x: p.x - dotR, y: p.y - dotR, width: dotR * 2, height: dotR * 2)
            if isTier1 {
                let glowRect = dotRect.insetBy(dx: -3, dy: -3)
                ctx.fill(Path(ellipseIn: glowRect), with: .color(color.opacity(0.25)))
            }
            ctx.fill(Path(ellipseIn: dotRect), with: .color(color))

            let crowded = labeledPoints.contains { hypot($0.x - p.x, $0.y - p.y) < 40 }
            if labeledPoints.count < 10 && !crowded {
                labeledPoints.append(p)
                let labelAnchorY: CGFloat = p.y > center.y ? p.y + 8 : p.y - 8
                let anchor: UnitPoint = p.y > center.y ? .top : .bottom
                ctx.draw(
                    Text(item.landmark.name)
                        .font(.system(size: 9.5, weight: isTier1 ? .semibold : .regular))
                        .foregroundStyle(isTier1 ? Theme.text : Theme.text.opacity(0.75)),
                    at: CGPoint(x: p.x, y: labelAnchorY), anchor: anchor
                )
                ctx.draw(
                    Text(formatDistance(item.distKm))
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(Theme.dim),
                    at: CGPoint(x: p.x, y: labelAnchorY + (anchor == .top ? 13 : -13)), anchor: anchor
                )
            }
        }
    }
}
