import SwiftUI

@main
struct BirdsEyeApp: App {
    @StateObject private var engine = FlightEngine()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(engine)
                .preferredColorScheme(.dark)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var engine: FlightEngine

    var body: some View {
        if engine.mode == nil {
            OnboardingView()
        } else {
            HUDView()
        }
    }
}
