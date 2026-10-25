import SwiftUI
import Testing
@testable import Sculptor

@Suite("Visualization visibility policy")
struct VisualizationPolicyTests {
    @Test func activeHomeEnablesVisualization() {
        #expect(
            VisualizationPolicy.isActive(
                scenePhase: .active,
                presetsPresented: false
            )
        )
    }

    @Test func sculptPresentationLeavesVisualizationActive() {
        // Sculpt is deliberately absent from this policy.
        #expect(
            VisualizationPolicy.isActive(
                scenePhase: .active,
                presetsPresented: false
            )
        )
    }

    @Test func presetsPresentationDisablesVisualization() {
        #expect(
            !VisualizationPolicy.isActive(
                scenePhase: .active,
                presetsPresented: true
            )
        )
    }

    @Test func inactiveButVisibleSceneKeepsVisualization() {
        // Split View on iPhone Duo / iPad: visible but not focused.
        #expect(
            VisualizationPolicy.isActive(
                scenePhase: .inactive,
                presetsPresented: false
            )
        )
    }

    @Test func backgroundSceneDisablesVisualization() {
        #expect(
            !VisualizationPolicy.isActive(
                scenePhase: .background,
                presetsPresented: false
            )
        )
    }
}
