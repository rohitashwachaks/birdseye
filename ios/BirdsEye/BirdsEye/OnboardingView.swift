import SwiftUI

/// Three-step onboarding: welcome → flight number or drive mode → flight briefing.
struct OnboardingView: View {
    @EnvironmentObject var engine: FlightEngine

    enum Stage {
        case welcome
        case chooseMode
        case flightReady(FlightRoute)
    }

    @State private var stage: Stage = .welcome

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            switch stage {
            case .welcome:
                WelcomeStep { withAnimation(.easeInOut) { stage = .chooseMode } }
            case .chooseMode:
                ChooseModeStep(
                    onFlightFound: { route in withAnimation(.easeInOut) { stage = .flightReady(route) } },
                    onDrive: { engine.begin(mode: .drive) }
                )
            case .flightReady(let route):
                FlightReadyStep(
                    route: route,
                    onStart: { side in
                        engine.seatSide = side
                        engine.begin(mode: .flight(route))
                    },
                    onBack: { withAnimation(.easeInOut) { stage = .chooseMode } }
                )
            }
        }
        .foregroundStyle(Theme.text)
    }
}

// MARK: - Step 1: welcome

private struct WelcomeStep: View {
    let onContinue: () -> Void
    @State private var spin = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle().stroke(Theme.line, lineWidth: 1.5).frame(width: 150, height: 150)
                Circle().stroke(Theme.line.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 5])).frame(width: 100, height: 100)
                ForEach(0..<12) { i in
                    Rectangle()
                        .fill(i == 0 ? Theme.cyan : Theme.dim)
                        .frame(width: 2, height: i % 3 == 0 ? 12 : 6)
                        .offset(y: -69)
                        .rotationEffect(.degrees(Double(i) * 30))
                }
                Image(systemName: "airplane")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.amber)
                    .rotationEffect(.degrees(-90))
            }
            .rotationEffect(.degrees(spin ? 8 : -8))
            .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: spin)
            .onAppear { spin = true }

            VStack(spacing: 10) {
                HStack(spacing: 0) {
                    Text("BIRDS").font(.system(size: 30, weight: .bold, design: .monospaced))
                    Text("EYE").font(.system(size: 30, weight: .bold, design: .monospaced)).foregroundStyle(Theme.cyan)
                }
                .tracking(6)
                Text("What's that below me?")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.text)
                Text("Point your window seat at the planet.\nMountains, cities, borders and wonders —\nnamed, with distance and direction.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.dim)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            Spacer()
            Button(action: onContinue) {
                Text("GET STARTED")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.cyan.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.cyan.opacity(0.5), lineWidth: 1))
                    .foregroundStyle(Theme.cyan)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 28)
            .padding(.bottom, 30)
        }
    }
}

// MARK: - Step 2: flight number or drive mode

private struct ChooseModeStep: View {
    let onFlightFound: (FlightRoute) -> Void
    let onDrive: () -> Void

    @State private var flightNumber = ""
    @State private var isLooking = false
    @State private var errorText: String?
    @State private var showManual = false
    @State private var manualFrom = "SFO"
    @State private var manualTo = "JFK"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("WHERE ARE WE HEADED?")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(Theme.dim)
                    .padding(.top, 28)

                // flight mode card
                VStack(alignment: .leading, spacing: 12) {
                    Label("I'm flying", systemImage: "airplane.departure")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("Enter your flight number — we'll download the route so Birds Eye works with no signal at 36,000 ft.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.dim)
                    HStack(spacing: 10) {
                        TextField("UA 123", text: $flightNumber)
                            .flightCodeFieldStyle()
                            .font(.system(size: 20, weight: .semibold, design: .monospaced))
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
                        Button(action: lookup) {
                            Group {
                                if isLooking {
                                    ProgressView().tint(Theme.bg)
                                } else {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 17, weight: .bold))
                                }
                            }
                            .frame(width: 50, height: 46)
                            .background(Theme.cyan, in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(Theme.bg)
                        }
                        .buttonStyle(.plain)
                        .disabled(flightNumber.trimmingCharacters(in: .whitespaces).isEmpty || isLooking)
                    }
                    if let errorText {
                        Text(errorText)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.amber)
                    }
                    if showManual {
                        manualRoutePicker
                    }
                }
                .panelCard()

                // drive mode card
                Button(action: onDrive) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Drive mode", systemImage: "car.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Text("Testing on the road? Uses live GPS and shows every landmark within a discovery radius. Best riding shotgun.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.dim)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panelCard()
                }
                .buttonStyle(.plain)

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 22)
        }
        .background(Theme.bg)
    }

    private var manualRoutePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().overlay(Theme.line)
            Text("PICK THE ROUTE MANUALLY")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(Theme.dim)
            HStack(spacing: 12) {
                Picker("From", selection: $manualFrom) {
                    ForEach(airportDB) { apt in
                        Text("\(apt.iata) · \(apt.name)").tag(apt.iata)
                    }
                }
                Image(systemName: "arrow.right").foregroundStyle(Theme.dim)
                Picker("To", selection: $manualTo) {
                    ForEach(airportDB) { apt in
                        Text("\(apt.iata) · \(apt.name)").tag(apt.iata)
                    }
                }
            }
            .tint(Theme.cyan)
            Button {
                guard let from = airportDB.first(where: { $0.iata == manualFrom }),
                      let to = airportDB.first(where: { $0.iata == manualTo }),
                      from.iata != to.iata else { return }
                onFlightFound(FlightRoute(label: "\(from.iata) → \(to.iata)", from: from.routeEnd, to: to.routeEnd))
            } label: {
                Text("USE THIS ROUTE")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.cyan.opacity(0.4), lineWidth: 1))
                    .foregroundStyle(Theme.cyan)
            }
            .buttonStyle(.plain)
        }
    }

    private func lookup() {
        errorText = nil
        isLooking = true
        let query = flightNumber
        Task { @MainActor in
            defer { isLooking = false }
            do {
                let route = try await FlightLookup.lookup(query)
                onFlightFound(route)
            } catch {
                errorText = error.localizedDescription
                showManual = true
            }
        }
    }
}

// MARK: - Step 3: flight briefing

private struct FlightReadyStep: View {
    let route: FlightRoute
    let onStart: (SeatSide) -> Void
    let onBack: () -> Void

    @State private var side: SeatSide = .left

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Button(action: onBack) {
                Label("Back", systemImage: "chevron.left")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Theme.dim)
            }
            .buttonStyle(.plain)
            .padding(.top, 18)

            Text("ROUTE LOADED")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .tracking(3)
                .foregroundStyle(Theme.green)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading) {
                        Text(route.from.code).font(.system(size: 30, weight: .bold, design: .monospaced))
                        Text(route.from.city).font(.system(size: 12)).foregroundStyle(Theme.dim)
                    }
                    Spacer()
                    Image(systemName: "airplane")
                        .foregroundStyle(Theme.cyan)
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(route.to.code).font(.system(size: 30, weight: .bold, design: .monospaced))
                        Text(route.to.city).font(.system(size: 12)).foregroundStyle(Theme.dim)
                    }
                }
                Divider().overlay(Theme.line)
                HStack {
                    stat("FLIGHT", route.label)
                    Spacer()
                    stat("DISTANCE", "\(Int(route.totalKm.rounded())) km")
                    Spacer()
                    stat("CRUISE TIME", String(format: "≈%.1f h", route.cruiseHours))
                }
                Text("Route is cached — everything from here works offline. GPS at the window improves accuracy when it can.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
            }
            .panelCard()

            VStack(alignment: .leading, spacing: 10) {
                Text("WHICH WINDOW ARE YOU AT?")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(Theme.dim)
                Picker("Seat side", selection: $side) {
                    ForEach(SeatSide.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                Text("We'll highlight what's visible from your side of the plane.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
            }
            .panelCard()

            Spacer()

            Button { onStart(side) } label: {
                Text("START · TO THE GATE ✈")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.cyan.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.cyan.opacity(0.5), lineWidth: 1))
                    .foregroundStyle(Theme.cyan)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 26)
        }
        .padding(.horizontal, 22)
        .background(Theme.bg)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1).foregroundStyle(Theme.dim)
            Text(value).font(.system(size: 14, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.green)
        }
    }
}
