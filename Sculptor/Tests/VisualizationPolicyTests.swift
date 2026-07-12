import Testing
@testable import Sculptor

@Suite("Visualization visibility policy")
struct VisualizationPolicyTests {
    @Test func activeHomeEnablesVisualization() {
        #expect(
            VisualizationPolicy.isActive(
                sceneIsActive: true,
                presetsPresented: false
            )
        )
    }

    @Test func sculptPresentationLeavesVisualizationActive() {
        // Sculpt is deliberately absent from this policy.
        #expect(
            VisualizationPolicy.isActive(
                sceneIsActive: true,
                presetsPresented: false
            )
        )
    }

    @Test func presetsPresentationDisablesVisualization() {
        #expect(
            !VisualizationPolicy.isActive(
                sceneIsActive: true,
                presetsPresented: true
            )
        )
    }

    @Test func inactiveSceneDisablesVisualization() {
        #expect(
            !VisualizationPolicy.isActive(
                sceneIsActive: false,
                presetsPresented: false
            )
        )
    }
}
