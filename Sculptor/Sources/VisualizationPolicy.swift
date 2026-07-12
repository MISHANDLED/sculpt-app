enum VisualizationPolicy {
    static func isActive(
        sceneIsActive: Bool,
        presetsPresented: Bool
    ) -> Bool {
        sceneIsActive && !presetsPresented
    }
}
