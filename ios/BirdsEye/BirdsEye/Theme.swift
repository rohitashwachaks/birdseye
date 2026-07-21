import SwiftUI

/// Night-flight HUD palette (matches the web prototype).
enum Theme {
    static let bg = Color(red: 0.020, green: 0.031, blue: 0.059)        // #05080f
    static let panel = Color(red: 0.039, green: 0.067, blue: 0.114)     // #0a111d
    static let panel2 = Color(red: 0.051, green: 0.082, blue: 0.141)    // #0d1524
    static let line = Color(red: 0.102, green: 0.153, blue: 0.251)      // #1a2740
    static let text = Color(red: 0.843, green: 0.886, blue: 0.933)      // #d7e2ee
    static let dim = Color(red: 0.392, green: 0.455, blue: 0.561)       // #64748f
    static let cyan = Color(red: 0.373, green: 0.831, blue: 0.957)      // #5fd4f4
    static let amber = Color(red: 1.000, green: 0.706, blue: 0.329)     // #ffb454
    static let green = Color(red: 0.494, green: 0.886, blue: 0.659)     // #7ee2a8

    static func color(for type: LandmarkType) -> Color {
        switch type {
        case .city, .town: return cyan
        case .peak: return Color(red: 0.85, green: 0.75, blue: 0.95)
        case .park: return green
        case .water: return Color(red: 0.45, green: 0.65, blue: 0.95)
        case .icon: return amber
        case .wonder: return Color(red: 1.0, green: 0.85, blue: 0.55)
        case .border: return Color(red: 0.95, green: 0.55, blue: 0.55)
        case .museum: return Color(red: 0.80, green: 0.72, blue: 0.98)
        case .stadium: return Color(red: 0.55, green: 0.90, blue: 0.80)
        case .tower: return amber
        case .airport: return Color(red: 0.65, green: 0.78, blue: 0.95)
        case .campus: return Color(red: 0.90, green: 0.80, blue: 0.60)
        }
    }
}

extension View {
    func panelCard() -> some View {
        self
            .padding(14)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
    }
}

func formatDistance(_ km: Double) -> String {
    km < 10 ? String(format: "%.1f km", km) : "\(Int(km.rounded())) km"
}
