import SwiftUI
import SwiftData

@main
struct SculptorApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(for: CustomPreset.self)
    }
}
