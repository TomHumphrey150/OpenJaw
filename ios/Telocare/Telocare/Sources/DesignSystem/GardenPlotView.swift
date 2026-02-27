import SceneKit
import SwiftUI

struct GardenPlotView: View {
    let themeKey: GardenThemeKey
    let bloomLevel: Double

    @State private var scene: SCNScene?

    init(themeKey: GardenThemeKey, bloomLevel: Double) {
        self.themeKey = themeKey
        self.bloomLevel = bloomLevel
    }

    init(pathway: GardenPathway, bloomLevel: Double) {
        self.init(themeKey: GardenThemeKey(pathway: pathway), bloomLevel: bloomLevel)
    }

    var body: some View {
        SceneView(
            scene: currentScene,
            options: []
        )
        .frame(width: 110, height: 100)
        .clipShape(
            RoundedRectangle(
                cornerRadius: TelocareTheme.CornerRadius.medium,
                style: .continuous
            )
        )
        .overlay(alignment: .bottom) {
            soilGradient
        }
        .onChange(of: bloomLevel) { _, newLevel in
            if let scene {
                GardenSceneBuilder(themeKey: themeKey).updatePlant(in: scene, bloomLevel: newLevel)
            }
        }
        .onChange(of: themeKey) { _, _ in
            scene = GardenSceneBuilder(themeKey: themeKey).makeScene(bloomLevel: bloomLevel)
        }
    }

    private var currentScene: SCNScene {
        if let scene {
            return scene
        }

        let newScene = GardenSceneBuilder(themeKey: themeKey).makeScene(bloomLevel: bloomLevel)
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
            RoundedRectangle(
                cornerRadius: TelocareTheme.CornerRadius.medium,
                style: .continuous
            )
        )
        .allowsHitTesting(false)
    }
}

private extension GardenThemeKey {
    init(pathway: GardenPathway) {
        switch pathway {
        case .upstream:
            self = .meadow
        case .midstream:
            self = .alpine
        case .downstream:
            self = .sunrise
        }
    }
}
