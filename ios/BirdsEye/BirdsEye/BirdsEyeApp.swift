import SwiftUI

@main
struct BirdsEyeApp: App {
    @StateObject private var engine = BirdsEyeEngine()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(engine)
                .preferredColorScheme(.dark)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var engine: BirdsEyeEngine

    var body: some View {
        if engine.isRunning {
            HUDView()
        } else {
            OnboardingView()
        }
    }
}
