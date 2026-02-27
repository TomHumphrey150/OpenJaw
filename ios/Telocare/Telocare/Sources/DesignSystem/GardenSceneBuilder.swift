import SceneKit
import SwiftUI

struct GardenSceneBuilder {
    let themeKey: GardenThemeKey

    init(themeKey: GardenThemeKey) {
        self.themeKey = themeKey
    }

    init(pathway: GardenPathway) {
        switch pathway {
        case .upstream:
            themeKey = .meadow
        case .midstream:
            themeKey = .alpine
        case .downstream:
            themeKey = .sunrise
        }
    }

    func makeScene(bloomLevel: Double) -> SCNScene {
        let scene = SCNScene()
        let palette = palette(for: themeKey)
        scene.background.contents = palette.background

        addCamera(to: scene)
        addLighting(to: scene)
        addSoil(to: scene)
        addPlant(to: scene, bloomLevel: bloomLevel)

        return scene
    }

    func updatePlant(in scene: SCNScene, bloomLevel: Double) {
        scene.rootNode.childNode(withName: "plantGroup", recursively: true)?.removeFromParentNode()
        addPlant(to: scene, bloomLevel: bloomLevel)
    }

    private func addCamera(to scene: SCNScene) {
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 40
        cameraNode.position = SCNVector3(0, 1.8, 3.5)
        cameraNode.look(at: SCNVector3(0, 0.6, 0))
        scene.rootNode.addChildNode(cameraNode)
    }

    private func addLighting(to scene: SCNScene) {
        let ambientNode = SCNNode()
        ambientNode.light = SCNLight()
        ambientNode.light?.type = .ambient
        ambientNode.light?.intensity = 550
        ambientNode.light?.color = UIColor(white: 1.0, alpha: 1.0)
        scene.rootNode.addChildNode(ambientNode)

        let directionalNode = SCNNode()
        directionalNode.light = SCNLight()
        directionalNode.light?.type = .directional
        directionalNode.light?.intensity = 820
        directionalNode.light?.color = UIColor.white
        directionalNode.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 6, 0)
        scene.rootNode.addChildNode(directionalNode)
    }

    private func addSoil(to scene: SCNScene) {
        let soil = SCNCylinder(radius: 0.8, height: 0.15)
        soil.firstMaterial?.diffuse.contents = UIColor(red: 0.45, green: 0.32, blue: 0.22, alpha: 1.0)
        soil.firstMaterial?.roughness.contents = 0.9
        let soilNode = SCNNode(geometry: soil)
        soilNode.position = SCNVector3(0, -0.075, 0)
        scene.rootNode.addChildNode(soilNode)
    }

    private func addPlant(to scene: SCNScene, bloomLevel: Double) {
        let palette = palette(for: themeKey)
        let stage = GrowthStage(bloomLevel: bloomLevel)

        let plantGroup = SCNNode()
        plantGroup.name = "plantGroup"

        let stem = SCNCylinder(radius: 0.05, height: stage.stemHeight)
        stem.firstMaterial?.diffuse.contents = palette.stem
        let stemNode = SCNNode(geometry: stem)
        stemNode.position = SCNVector3(0, Float(stage.stemHeight / 2), 0)
        plantGroup.addChildNode(stemNode)

        for index in 0..<stage.branchCount {
            let side: Float = index % 2 == 0 ? -1 : 1
            let verticalFactor = Float(index + 1) / Float(stage.branchCount + 1)
            let branch = SCNCylinder(radius: 0.02, height: stage.branchHeight)
            branch.firstMaterial?.diffuse.contents = palette.stem

            let branchNode = SCNNode(geometry: branch)
            branchNode.position = SCNVector3(0, Float(stage.stemHeight) * verticalFactor, 0)
            branchNode.eulerAngles = SCNVector3(0, 0, side * Float.pi / 3)
            plantGroup.addChildNode(branchNode)

            let leafNode = makeLeaf(
                width: CGFloat(0.14 * stage.leafScale),
                height: CGFloat(0.26 * stage.leafScale),
                color: palette.leaf
            )
            leafNode.position = SCNVector3(
                side * 0.16,
                Float(stage.stemHeight) * verticalFactor + Float(stage.branchHeight) * 0.45,
                0
            )
            leafNode.eulerAngles = SCNVector3(0, side * Float.pi / 6, side * Float.pi / 5)
            plantGroup.addChildNode(leafNode)
        }

        for index in 0..<stage.crownLeafCount {
            let angle = Float(index) * (2 * .pi / Float(max(stage.crownLeafCount, 1)))
            let crownLeaf = makeLeaf(
                width: CGFloat(0.15 * stage.leafScale),
                height: CGFloat(0.28 * stage.leafScale),
                color: palette.leaf
            )
            crownLeaf.position = SCNVector3(0, Float(stage.stemHeight) * 0.96, 0)
            crownLeaf.eulerAngles = SCNVector3(-Float.pi / 5, angle, 0)
            plantGroup.addChildNode(crownLeaf)
        }

        if stage.flowerCount > 0 {
            let center = SCNSphere(radius: CGFloat(0.06 * stage.leafScale))
            center.firstMaterial?.diffuse.contents = palette.center
            let centerNode = SCNNode(geometry: center)
            centerNode.position = SCNVector3(0, Float(stage.stemHeight) + 0.04, 0)
            plantGroup.addChildNode(centerNode)

            for index in 0..<stage.flowerCount {
                let angle = Float(index) * (2 * .pi / Float(stage.flowerCount))
                let petal = makePetal(size: CGFloat(0.12 * stage.leafScale), color: palette.flower)
                petal.position = SCNVector3(0, Float(stage.stemHeight) + 0.04, 0)
                petal.eulerAngles = SCNVector3(-Float.pi / 6, angle, 0)
                plantGroup.addChildNode(petal)
            }
        }

        addIdleSway(to: plantGroup, bloomLevel: bloomLevel)
        scene.rootNode.addChildNode(plantGroup)
    }

    private func makeLeaf(width: CGFloat, height: CGFloat, color: UIColor) -> SCNNode {
        let leaf = SCNPlane(width: width, height: height)
        leaf.firstMaterial?.diffuse.contents = color
        leaf.firstMaterial?.isDoubleSided = true
        return SCNNode(geometry: leaf)
    }

    private func makePetal(size: CGFloat, color: UIColor) -> SCNNode {
        let petal = SCNPlane(width: size, height: size * 1.35)
        petal.cornerRadius = size * 0.35
        petal.firstMaterial?.diffuse.contents = color
        petal.firstMaterial?.isDoubleSided = true
        return SCNNode(geometry: petal)
    }

    private func palette(for themeKey: GardenThemeKey) -> GardenPalette {
        switch themeKey {
        case .meadow:
            return GardenPalette(
                background: UIColor(red: 0.98, green: 0.99, blue: 0.95, alpha: 1.0),
                stem: UIColor(red: 0.20, green: 0.46, blue: 0.20, alpha: 1.0),
                leaf: UIColor(red: 0.33, green: 0.64, blue: 0.28, alpha: 1.0),
                flower: UIColor(red: 0.85, green: 0.93, blue: 0.43, alpha: 1.0),
                center: UIColor(red: 0.95, green: 0.84, blue: 0.38, alpha: 1.0)
            )
        case .sunrise:
            return GardenPalette(
                background: UIColor(red: 1.0, green: 0.97, blue: 0.93, alpha: 1.0),
                stem: UIColor(red: 0.31, green: 0.50, blue: 0.22, alpha: 1.0),
                leaf: UIColor(red: 0.48, green: 0.68, blue: 0.30, alpha: 1.0),
                flower: UIColor(red: 0.97, green: 0.62, blue: 0.36, alpha: 1.0),
                center: UIColor(red: 0.99, green: 0.84, blue: 0.44, alpha: 1.0)
            )
        case .tide:
            return GardenPalette(
                background: UIColor(red: 0.95, green: 0.98, blue: 1.0, alpha: 1.0),
                stem: UIColor(red: 0.18, green: 0.41, blue: 0.45, alpha: 1.0),
                leaf: UIColor(red: 0.27, green: 0.58, blue: 0.62, alpha: 1.0),
                flower: UIColor(red: 0.41, green: 0.75, blue: 0.81, alpha: 1.0),
                center: UIColor(red: 0.93, green: 0.89, blue: 0.54, alpha: 1.0)
            )
        case .ember:
            return GardenPalette(
                background: UIColor(red: 1.0, green: 0.95, blue: 0.92, alpha: 1.0),
                stem: UIColor(red: 0.42, green: 0.34, blue: 0.20, alpha: 1.0),
                leaf: UIColor(red: 0.61, green: 0.43, blue: 0.24, alpha: 1.0),
                flower: UIColor(red: 0.90, green: 0.43, blue: 0.26, alpha: 1.0),
                center: UIColor(red: 0.96, green: 0.80, blue: 0.41, alpha: 1.0)
            )
        case .alpine:
            return GardenPalette(
                background: UIColor(red: 0.95, green: 0.98, blue: 0.96, alpha: 1.0),
                stem: UIColor(red: 0.21, green: 0.37, blue: 0.29, alpha: 1.0),
                leaf: UIColor(red: 0.32, green: 0.52, blue: 0.39, alpha: 1.0),
                flower: UIColor(red: 0.66, green: 0.83, blue: 0.66, alpha: 1.0),
                center: UIColor(red: 0.95, green: 0.88, blue: 0.47, alpha: 1.0)
            )
        case .orchard:
            return GardenPalette(
                background: UIColor(red: 1.0, green: 0.96, blue: 0.97, alpha: 1.0),
                stem: UIColor(red: 0.34, green: 0.43, blue: 0.23, alpha: 1.0),
                leaf: UIColor(red: 0.49, green: 0.63, blue: 0.33, alpha: 1.0),
                flower: UIColor(red: 0.93, green: 0.57, blue: 0.62, alpha: 1.0),
                center: UIColor(red: 0.97, green: 0.83, blue: 0.44, alpha: 1.0)
            )
        }
    }

    private func addIdleSway(to node: SCNNode, bloomLevel: Double) {
        let amplitude = Float(0.02 + bloomLevel * 0.03)
        let sway = SCNAction.sequence([
            SCNAction.rotateBy(x: 0, y: 0, z: CGFloat(amplitude), duration: 2.0),
            SCNAction.rotateBy(x: 0, y: 0, z: CGFloat(-2 * amplitude), duration: 4.0),
            SCNAction.rotateBy(x: 0, y: 0, z: CGFloat(amplitude), duration: 2.0),
        ])
        node.runAction(SCNAction.repeatForever(sway))
    }
}

private struct GardenPalette {
    let background: UIColor
    let stem: UIColor
    let leaf: UIColor
    let flower: UIColor
    let center: UIColor
}

private struct GrowthStage {
    let stemHeight: CGFloat
    let branchHeight: CGFloat
    let branchCount: Int
    let crownLeafCount: Int
    let leafScale: Float
    let flowerCount: Int

    init(bloomLevel: Double) {
        switch bloomLevel {
        case ..<0.2:
            stemHeight = 0.42
            branchHeight = 0.16
            branchCount = 2
            crownLeafCount = 3
            leafScale = 0.55
            flowerCount = 0
        case ..<0.5:
            stemHeight = 0.72
            branchHeight = 0.20
            branchCount = 4
            crownLeafCount = 4
            leafScale = 0.78
            flowerCount = 3
        case ..<0.8:
            stemHeight = 1.02
            branchHeight = 0.24
            branchCount = 6
            crownLeafCount = 5
            leafScale = 1.0
            flowerCount = 5
        default:
            stemHeight = 1.28
            branchHeight = 0.30
            branchCount = 8
            crownLeafCount = 6
            leafScale = 1.2
            flowerCount = 7
        }
    }
}
