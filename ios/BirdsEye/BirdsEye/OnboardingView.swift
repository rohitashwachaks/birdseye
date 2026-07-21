import SwiftUI
import CoreLocation

/// One screen: what the app does, then start. Location permission is requested by the
/// position source once the session begins, so there's nothing to configure first.
struct OnboardingView: View {
    @EnvironmentObject var engine: BirdsEyeEngine
    @State private var spin = false

    private var permissionDenied: Bool {
        engine.authorization == .denied || engine.authorization == .restricted
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 26) {
                Spacer()
                dial
                VStack(spacing: 10) {
                    HStack(spacing: 0) {
                        Text("BIRDS").font(.system(size: 30, weight: .bold, design: .monospaced))
                        Text("EYE").font(.system(size: 30, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.cyan)
                    }
                    .tracking(6)
                    Text("What's that out there?")
                        .font(.system(size: 17, weight: .medium))
                    Text("Landmarks, towns and lakes around you —\nnamed, with distance and direction,\nas you drive.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.dim)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
                Spacer()

                if permissionDenied {
                    Text("Location is off for Birds Eye. Enable it in Settings ▸ Privacy ▸ Location Services to see what's around you.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.amber)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }

                Button {
                    engine.start(mode: .drive)
                } label: {
                    Label("START DRIVE MODE", systemImage: "car.fill")
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.cyan.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .stroke(Theme.cyan.opacity(0.5), lineWidth: 1))
                        .foregroundStyle(Theme.cyan)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("startDriveButton")
                .padding(.horizontal, 28)

                Text("Uses your location while the app is open. Best riding shotgun.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                    .padding(.bottom, 26)
            }
        }
        .foregroundStyle(Theme.text)
    }

    private var dial: some View {
        ZStack {
            Circle().stroke(Theme.line, lineWidth: 1.5).frame(width: 150, height: 150)
            Circle().stroke(Theme.line.opacity(0.6),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                .frame(width: 100, height: 100)
            ForEach(0..<12) { i in
                Rectangle()
                    .fill(i == 0 ? Theme.cyan : Theme.dim)
                    .frame(width: 2, height: i % 3 == 0 ? 12 : 6)
                    .offset(y: -69)
                    .rotationEffect(.degrees(Double(i) * 30))
            }
            Image(systemName: "car.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Theme.amber)
        }
        .rotationEffect(.degrees(spin ? 8 : -8))
        .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: spin)
        .onAppear { spin = true }
    }
}
