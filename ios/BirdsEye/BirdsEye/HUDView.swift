import SwiftUI

/// The live screen: dial, readouts, radius control, and the "around you" feed.
/// Reads only `Observer` + `ObservationMode`, so it is mode-agnostic by construction.
struct HUDView: View {
    @EnvironmentObject var engine: BirdsEyeEngine

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    header
                    if let mode = engine.mode {
                        DialView(
                            observer: engine.observer,
                            mode: mode,
                            visible: engine.visible,
                            radiusKm: engine.radiusKm,
                            hasFix: engine.hasFreshFix
                        )
                        .padding(.horizontal, 10)
                        readouts
                        radiusControl(mode: mode)
                    }
                    aroundYou
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
                Text("EYE").font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.cyan)
            }
            .tracking(3)
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(engine.hasFreshFix ? Theme.green : Theme.amber)
                    .frame(width: 7, height: 7)
                Text(statusText)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.dim)
                    .accessibilityIdentifier("statusLabel")
            }
            Button { engine.stop() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.dim)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("endSessionButton")
        }
    }

    private var statusText: String {
        guard engine.hasFreshFix else { return "ACQUIRING…" }
        return engine.observer.isLive ? "LIVE GPS" : "SIMULATED"
    }

    // MARK: - Readouts

    private var readouts: some View {
        HStack(spacing: 8) {
            readout("SPEED", engine.hasFreshFix ? "\(Int(engine.observer.speedKmh.rounded())) km/h" : "—")
            readout("HEADING", engine.hasFreshFix
                    ? String(format: "%03d°", Int(engine.observer.headingDeg.rounded()) % 360) : "—")
            readout("RADIUS", "\(Int(engine.radiusKm)) km")
            readout("IN RANGE", engine.hasFreshFix ? "\(engine.visible.count)" : "—")
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

    // MARK: - Radius

    private func radiusControl(mode: ObservationMode) -> some View {
        HStack {
            Text("HOW FAR AROUND ME")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(Theme.dim)
            Spacer()
            Picker("Radius", selection: $engine.radiusKm) {
                ForEach(mode.radiusChoices, id: \.self) { km in
                    Text("\(Int(km))").tag(km)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)
            .accessibilityIdentifier("radiusPicker")
        }
        .panelCard()
    }

    // MARK: - Feed

    private var aroundYou: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AROUND YOU")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(3)
                .foregroundStyle(Theme.dim)
            if engine.visible.isEmpty {
                Text(engine.hasFreshFix
                     ? "Nothing within \(Int(engine.radiusKm)) km — try a wider radius."
                     : "Waiting for a GPS fix…")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.dim)
                    .padding(.vertical, 10)
            }
            ForEach(engine.visible.prefix(15)) { item in
                feedRow(item)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func feedRow(_ item: VisibleLandmark) -> some View {
        let arrow = abs(item.relativeBearingDeg) < 15 ? "▲" : (item.relativeBearingDeg < 0 ? "◀" : "▶")
        let eta = item.minutesUntilAbeam(speedKmh: engine.observer.speedKmh)
            .map { $0 >= 1 ? "~\(Int($0.rounded())) min" : "now" }

        return HStack(spacing: 10) {
            Image(systemName: item.landmark.type.glyph)
                .font(.system(size: 14))
                .foregroundStyle(Theme.color(for: item.landmark.type))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.landmark.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(formatDistance(item.distanceKm)
                     + (item.isLineOfSight ? " · in sight" : " · over horizon")
                     + (eta.map { " · \($0)" } ?? ""))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.dim)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(arrow) \(item.clock) o'clock")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.amber)
                if item.isBehind {
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
        .opacity(item.isBehind ? 0.55 : 1)
    }
}
