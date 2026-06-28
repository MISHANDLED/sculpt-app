import SwiftUI
import SwiftData

@main
struct SculptorApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: CustomPreset.self)
    }
}
