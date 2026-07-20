import SwiftUI

/// Main in-flight/driving screen: circular dial + readouts + "coming up" feed.
struct HUDView: View {
    @EnvironmentObject var engine: FlightEngine

    private var isDrive: Bool { engine.mode == .drive }
    private var flightRoute: FlightRoute? {
        if case .flight(let route) = engine.mode { return route }
        return nil
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    header
                    DialView(
                        snapshot: engine.snapshot,
                        visible: engine.visible,
                        seatSide: isDrive ? nil : engine.seatSide,
                        isDrive: isDrive
                    )
                    .padding(.horizontal, 10)
                    readouts
                    if let route = flightRoute {
                        flightControls(route: route)
                    } else {
                        driveControls
                    }
                    comingUp
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .foregroundStyle(Theme.text)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            HStack(spacing: 0) {
                Text("BIRDS").font(.system(size: 15, weight: .bold, design: .monospaced))
                Text("EYE").font(.system(size: 15, weight: .bold, design: .monospaced)).foregroundStyle(Theme.cyan)
            }
            .tracking(3)
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(engine.snapshot.usingGPS ? Theme.green : Theme.amber)
                    .frame(width: 7, height: 7)
                Text(statusText)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.dim)
            }
            Button {
                engine.endSession()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.dim)
            }
            .buttonStyle(.plain)
        }
    }

    private var statusText: String {
        if isDrive {
            return engine.snapshot.hasFix ? "LIVE GPS" : "ACQUIRING…"
        }
        if engine.snapshot.usingGPS { return "GPS LOCK" }
        return engine.wheelsUp == nil ? "AT THE GATE" : "DEAD RECKONING"
    }

    // MARK: - Readouts

    private var readouts: some View {
        HStack(spacing: 8) {
            readout("ALT", engine.snapshot.hasFix ? "\(Int(engine.snapshot.altM.rounded())) m" : "—")
            readout("GS", engine.snapshot.hasFix ? "\(Int(engine.snapshot.kmh.rounded())) km/h" : "—")
            readout("TRK", engine.snapshot.hasFix ? String(format: "%03d°", Int(engine.snapshot.headingDeg.rounded()) % 360) : "—")
            readout("RANGE", engine.snapshot.hasFix ? "\(Int(engine.snapshot.rangeKm.rounded())) km" : "—")
        }
    }

    private func readout(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(Theme.dim)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.green)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
    }

    // MARK: - Flight controls

    private func flightControls(route: FlightRoute) -> some View {
        VStack(spacing: 10) {
            if engine.wheelsUp == nil {
                Button {
                    engine.markWheelsUp()
                } label: {
                    Label("WHEELS UP — START THE CLOCK", systemImage: "airplane.departure")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Theme.amber.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.amber.opacity(0.5), lineWidth: 1))
                        .foregroundStyle(Theme.amber)
                }
                .buttonStyle(.plain)
                Text("Tap at takeoff — or drag the flight bar below if you're already in the air.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
            }
            VStack(spacing: 6) {
                Slider(
                    value: Binding(
                        get: { engine.snapshot.progress },
                        set: { engine.scrub(to: $0) }
                    ), in: 0...1
                )
                .tint(Theme.cyan)
                HStack {
                    Text(route.from.code)
                    Spacer()
                    Text("\(Int((engine.snapshot.progress * route.totalKm).rounded())) / \(Int(route.totalKm.rounded())) km")
                    Spacer()
                    Text(route.to.code)
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.dim)
            }
            .panelCard()
        }
    }

    // MARK: - Drive controls

    private var driveControls: some View {
        HStack {
            Text("DISCOVERY RADIUS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(Theme.dim)
            Spacer()
            Picker("Radius", selection: $engine.driveRadiusKm) {
                Text("50").tag(50.0)
                Text("100").tag(100.0)
                Text("200").tag(200.0)
                Text("400").tag(400.0)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)
            .onChange(of: engine.driveRadiusKm) { engine.tick() }
        }
        .panelCard()
    }

    // MARK: - Coming up feed

    private var comingUp: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COMING UP")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(3)
                .foregroundStyle(Theme.dim)
            if engine.visible.isEmpty {
                Text(engine.snapshot.hasFix
                     ? "Nothing in range yet — fly on ✈"
                     : "Waiting for a position…")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.dim)
                    .padding(.vertical, 10)
            }
            ForEach(engine.visible.prefix(12)) { item in
                feedRow(item)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func feedRow(_ item: VisibleLandmark) -> some View {
        let behind = abs(item.rel) > 100
        let sideArrow = abs(item.rel) < 15 ? "▲" : (item.rel < 0 ? "◀" : "▶")
        var eta: String?
        if engine.snapshot.kmh > 40 && abs(item.rel) < 80 {
            let minutes = item.distKm * cos(Geo.rad(item.rel)) / engine.snapshot.kmh * 60
            eta = minutes >= 1 ? "~\(Int(minutes.rounded())) min" : "now"
        }
        return HStack(spacing: 10) {
            Image(systemName: item.landmark.type.glyph)
                .font(.system(size: 14))
                .foregroundStyle(Theme.color(for: item.landmark.type))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.landmark.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(formatDistance(item.distKm)
                     + (item.landmark.elevM >= 1000 ? " · elev \(Int(item.landmark.elevM)) m" : "")
                     + (eta.map { " · \($0)" } ?? ""))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.dim)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(sideArrow) \(item.clock) o'clock")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.amber)
                if behind {
                    Text("behind you")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Theme.dim)
                }
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 11))
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .stroke(item.landmark.tier == 1 ? Theme.cyan.opacity(0.4) : Theme.line, lineWidth: 1)
        )
        .opacity(behind ? 0.55 : 1)
    }
}
