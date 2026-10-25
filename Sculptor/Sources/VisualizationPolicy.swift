import SwiftUI

enum VisualizationPolicy {
    /// `.inactive` still renders: on iPhone Duo / iPad Split View a visible
    /// scene can be inactive while the other app has focus.
    static func isActive(
        scenePhase: ScenePhase,
        presetsPresented: Bool
    ) -> Bool {
        scenePhase != .background && !presetsPresented
    }
}
