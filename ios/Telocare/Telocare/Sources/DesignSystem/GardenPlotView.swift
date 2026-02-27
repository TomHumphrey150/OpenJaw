import SceneKit
import SwiftUI

struct GardenPlotView: View {
    let pathway: GardenPathway
    let bloomLevel: Double

    @State private var scene: SCNScene?

    var body: some View {
        SceneView(
            scene: currentScene,
            options: []
        )
        .frame(width: 110, height: 100)
        .clipShape(RoundedRectangle(cornerRadius: TelocareTheme.CornerRadius.medium, style: .continuous))
        .overlay(alignment: .bottom) {
            soilGradient
        }
        .onChange(of: bloomLevel) { _, newLevel in
            if let scene {
                GardenSceneBuilder(pathway: pathway).updatePlant(in: scene, bloomLevel: newLevel)
            }
        }
    }

    private var currentScene: SCNScene {
        if let scene {
            return scene
        }

        let newScene = GardenSceneBuilder(pathway: pathway).makeScene(bloomLevel: bloomLevel)
        DispatchQueue.main.async {
            scene = newScene
        }
        return newScene
    }

    private var soilGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.45, green: 0.32, blue: 0.22).opacity(0.6),
                .clear,
            ],
            startPoint: .bottom,
            endPoint: .center
        )
        .frame(height: 30)
        .clipShape(
            RoundedRectangle(cornerRadius: TelocareTheme.CornerRadius.medium, style: .continuous)
        )
        .allowsHitTesting(false)
    }
}
