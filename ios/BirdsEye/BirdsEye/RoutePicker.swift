import SwiftUI

/// Type-to-search airport field. The flight-number lookup is only ever a *guess*
/// (see FlightLookup — the free route DB is per-callsign and often carries a stale
/// city pair), so picking the route by hand has to be first-class, not a fallback.
struct AirportSearchField: View {
    let label: String
    @Binding var selection: Airport

    @State private var query = ""
    @State private var isSearching = false

    private var matches: [Airport] {
        Array(airportDB.filter { $0.matches(query: query) }.prefix(6))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(Theme.dim)

            if isSearching {
                TextField("code or city", text: $query)
                    .accessibilityIdentifier("airportSearch-\(label)")
                    .flightCodeFieldStyle()
                    .font(.system(size: 15, design: .monospaced))
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.cyan.opacity(0.5), lineWidth: 1))

                if !matches.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(matches) { apt in
                            Button {
                                selection = apt
                                query = ""
                                isSearching = false
                            } label: {
                                HStack(spacing: 8) {
                                    Text(apt.iata)
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                        .foregroundStyle(Theme.cyan)
                                        .frame(width: 42, alignment: .leading)
                                    Text(apt.name)
                                        .font(.system(size: 13))
                                        .foregroundStyle(Theme.text)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.vertical, 9)
                                .padding(.horizontal, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("airportResult-\(apt.iata)")
                            if apt != matches.last { Divider().overlay(Theme.line) }
                        }
                    }
                    .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line, lineWidth: 1))
                } else if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("No match — try the 3-letter code.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                }
            } else {
                Button { isSearching = true } label: {
                    HStack(spacing: 8) {
                        Text(selection.iata)
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.text)
                        Text(selection.name)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.dim)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.dim)
                    }
                    .padding(10)
                    .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("airportSelect-\(label)")
            }
        }
    }
}

/// From/to pair + confirm button. Used both as the manual entry path and as the
/// "that's not my route" correction on the briefing screen.
struct RoutePickerCard: View {
    @Binding var from: Airport
    @Binding var to: Airport
    var confirmTitle: String = "USE THIS ROUTE"
    let onConfirm: (FlightRoute) -> Void

    private var isValid: Bool { from.iata != to.iata }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AirportSearchField(label: "FROM", selection: $from)
            AirportSearchField(label: "TO", selection: $to)

            if !isValid {
                Text("Origin and destination must differ.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.amber)
            }

            Button {
                guard isValid else { return }
                onConfirm(FlightRoute(
                    label: "\(from.iata) → \(to.iata)",
                    from: from.routeEnd,
                    to: to.routeEnd
                ))
            } label: {
                Text(confirmTitle)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Theme.cyan.opacity(isValid ? 0.15 : 0.05), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.cyan.opacity(isValid ? 0.5 : 0.2), lineWidth: 1))
                    .foregroundStyle(Theme.cyan.opacity(isValid ? 1 : 0.4))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("confirmRouteButton")
            .disabled(!isValid)
        }
    }
}
