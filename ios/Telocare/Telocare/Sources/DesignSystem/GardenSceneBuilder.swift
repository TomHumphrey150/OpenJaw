import SceneKit
import SwiftUI

struct GardenSceneBuilder {
    let pathway: GardenPathway

    func makeScene(bloomLevel: Double) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor(TelocareTheme.cream)

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

    // MARK: - Camera

    private func addCamera(to scene: SCNScene) {
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 40
        cameraNode.position = SCNVector3(0, 1.8, 3.5)
        cameraNode.look(at: SCNVector3(0, 0.6, 0))
        scene.rootNode.addChildNode(cameraNode)
    }

    // MARK: - Lighting

    private func addLighting(to scene: SCNScene) {
        let ambientNode = SCNNode()
        ambientNode.light = SCNLight()
        ambientNode.light?.type = .ambient
        ambientNode.light?.intensity = 600
        ambientNode.light?.color = UIColor(white: 1.0, alpha: 1.0)
        scene.rootNode.addChildNode(ambientNode)

        let directionalNode = SCNNode()
        directionalNode.light = SCNLight()
        directionalNode.light?.type = .directional
        directionalNode.light?.intensity = 800
        directionalNode.light?.color = UIColor.white
        directionalNode.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 6, 0)
        scene.rootNode.addChildNode(directionalNode)
    }

    // MARK: - Soil

    private func addSoil(to scene: SCNScene) {
        let soil = SCNCylinder(radius: 0.8, height: 0.15)
        soil.firstMaterial?.diffuse.contents = UIColor(red: 0.45, green: 0.32, blue: 0.22, alpha: 1.0)
        soil.firstMaterial?.roughness.contents = 0.9
        let soilNode = SCNNode(geometry: soil)
        soilNode.position = SCNVector3(0, -0.075, 0)
        scene.rootNode.addChildNode(soilNode)
    }

    // MARK: - Plant

    private func addPlant(to scene: SCNScene, bloomLevel: Double) {
        let plantGroup = SCNNode()
        plantGroup.name = "plantGroup"

        let stage = GrowthStage(bloomLevel: bloomLevel)

        switch pathway {
        case .upstream:
            addFernPlant(to: plantGroup, stage: stage, bloomLevel: bloomLevel)
        case .midstream:
            addTreePlant(to: plantGroup, stage: stage, bloomLevel: bloomLevel)
        case .downstream:
            addFlowerPlant(to: plantGroup, stage: stage, bloomLevel: bloomLevel)
        }

        addIdleSway(to: plantGroup, bloomLevel: bloomLevel)
        scene.rootNode.addChildNode(plantGroup)
    }

    // MARK: - Fern (Roots / upstream)

    private func addFernPlant(to parent: SCNNode, stage: GrowthStage, bloomLevel: Double) {
        let stemHeight: CGFloat = stage.stemHeight * 0.7
        let leafScale: Float = stage.leafScale
        let leafCount = stage.leafCount

        // Central stem
        let stem = SCNCylinder(radius: 0.04, height: stemHeight)
        stem.firstMaterial?.diffuse.contents = UIColor(red: 0.3, green: 0.5, blue: 0.25, alpha: 1.0)
        let stemNode = SCNNode(geometry: stem)
        stemNode.position = SCNVector3(0, Float(stemHeight / 2), 0)
        parent.addChildNode(stemNode)

        // Fern fronds radiating outward
        for i in 0..<leafCount {
            let angle = Float(i) * (2 * .pi / Float(leafCount))
            let frond = makeLeaf(
                width: CGFloat(0.15 * leafScale),
                height: CGFloat(0.5 * leafScale),
                color: fernColor(for: bloomLevel)
            )
            frond.position = SCNVector3(0, Float(stemHeight) * 0.8, 0)
            frond.eulerAngles = SCNVector3(
                -Float.pi / 4 - Float(bloomLevel) * 0.2,
                angle,
                0
            )
            parent.addChildNode(frond)
        }
    }

    // MARK: - Tree (Canopy / midstream)

    private func addTreePlant(to parent: SCNNode, stage: GrowthStage, bloomLevel: Double) {
        let trunkHeight: CGFloat = stage.stemHeight
        let canopyRadius: CGFloat = CGFloat(stage.leafScale) * 0.45

        // Trunk
        let trunk = SCNCylinder(radius: 0.06, height: trunkHeight)
        trunk.firstMaterial?.diffuse.contents = UIColor(red: 0.45, green: 0.35, blue: 0.2, alpha: 1.0)
        let trunkNode = SCNNode(geometry: trunk)
        trunkNode.position = SCNVector3(0, Float(trunkHeight / 2), 0)
        parent.addChildNode(trunkNode)

        // Canopy sphere(s)
        let mainCanopy = SCNSphere(radius: canopyRadius)
        mainCanopy.firstMaterial?.diffuse.contents = canopyColor(for: bloomLevel)
        let canopyNode = SCNNode(geometry: mainCanopy)
        canopyNode.position = SCNVector3(0, Float(trunkHeight) + Float(canopyRadius) * 0.6, 0)
        parent.addChildNode(canopyNode)

        if bloomLevel > 0.5 {
            let sideCanopy = SCNSphere(radius: canopyRadius * 0.7)
            sideCanopy.firstMaterial?.diffuse.contents = canopyColor(for: bloomLevel)

            let leftNode = SCNNode(geometry: sideCanopy)
            leftNode.position = SCNVector3(
                -Float(canopyRadius) * 0.7,
                Float(trunkHeight) + Float(canopyRadius) * 0.3,
                0
            )
            parent.addChildNode(leftNode)

            let rightNode = SCNNode(geometry: sideCanopy)
            rightNode.position = SCNVector3(
                Float(canopyRadius) * 0.7,
                Float(trunkHeight) + Float(canopyRadius) * 0.3,
                0
            )
            parent.addChildNode(rightNode)
        }
    }

    // MARK: - Flower (Bloom / downstream)

    private func addFlowerPlant(to parent: SCNNode, stage: GrowthStage, bloomLevel: Double) {
        let stemHeight: CGFloat = stage.stemHeight * 0.9
        let petalScale: Float = stage.leafScale

        // Stem
        let stem = SCNCylinder(radius: 0.035, height: stemHeight)
        stem.firstMaterial?.diffuse.contents = UIColor(red: 0.3, green: 0.55, blue: 0.25, alpha: 1.0)
        let stemNode = SCNNode(geometry: stem)
        stemNode.position = SCNVector3(0, Float(stemHeight / 2), 0)
        parent.addChildNode(stemNode)

        // Leaves along stem
        if bloomLevel > 0.2 {
            for side in [-1, 1] as [Int] {
                let leaf = makeLeaf(
                    width: CGFloat(0.1 * petalScale),
                    height: CGFloat(0.25 * petalScale),
                    color: UIColor(red: 0.35, green: 0.6, blue: 0.3, alpha: 1.0)
                )
                leaf.position = SCNVector3(
                    Float(side) * 0.05,
                    Float(stemHeight) * 0.4,
                    0
                )
                leaf.eulerAngles = SCNVector3(0, 0, Float(side) * Float.pi / 4)
                parent.addChildNode(leaf)
            }
        }

        // Flower head
        if bloomLevel > 0.2 {
            let petalCount = bloomLevel > 0.5 ? 6 : 4
            let flowerCenter = SCNSphere(radius: CGFloat(0.06 * petalScale))
            flowerCenter.firstMaterial?.diffuse.contents = UIColor(red: 0.95, green: 0.85, blue: 0.3, alpha: 1.0)
            let centerNode = SCNNode(geometry: flowerCenter)
            centerNode.position = SCNVector3(0, Float(stemHeight), 0)
            parent.addChildNode(centerNode)

            for i in 0..<petalCount {
                let angle = Float(i) * (2 * .pi / Float(petalCount))
                let petal = makePetal(
                    size: CGFloat(0.12 * petalScale),
                    color: petalColor(for: bloomLevel)
                )
                petal.position = SCNVector3(0, Float(stemHeight), 0)
                petal.eulerAngles = SCNVector3(-Float.pi / 6, angle, 0)
                parent.addChildNode(petal)
            }
        }
    }

    // MARK: - Geometry Helpers

    private func makeLeaf(width: CGFloat, height: CGFloat, color: UIColor) -> SCNNode {
        let leaf = SCNPlane(width: width, height: height)
        leaf.firstMaterial?.diffuse.contents = color
        leaf.firstMaterial?.isDoubleSided = true
        return SCNNode(geometry: leaf)
    }

    private func makePetal(size: CGFloat, color: UIColor) -> SCNNode {
        let petal = SCNPlane(width: size, height: size * 1.5)
        petal.cornerRadius = size * 0.4
        petal.firstMaterial?.diffuse.contents = color
        petal.firstMaterial?.isDoubleSided = true
        return SCNNode(geometry: petal)
    }

    // MARK: - Colors

    private func fernColor(for bloomLevel: Double) -> UIColor {
        let green = 0.4 + bloomLevel * 0.3
        return UIColor(red: 0.2, green: green, blue: 0.15, alpha: 1.0)
    }

    private func canopyColor(for bloomLevel: Double) -> UIColor {
        let green = 0.45 + bloomLevel * 0.25
        return UIColor(red: 0.2, green: green, blue: 0.2, alpha: 1.0)
    }

    private func petalColor(for bloomLevel: Double) -> UIColor {
        if bloomLevel > 0.8 {
            return UIColor(red: 0.95, green: 0.35, blue: 0.5, alpha: 1.0)
        } else if bloomLevel > 0.5 {
            return UIColor(red: 0.9, green: 0.5, blue: 0.55, alpha: 1.0)
        } else {
            return UIColor(red: 0.85, green: 0.65, blue: 0.6, alpha: 1.0)
        }
    }

    // MARK: - Animation

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

// MARK: - Growth Stage

private struct GrowthStage {
    let stemHeight: CGFloat
    let leafScale: Float
    let leafCount: Int

    init(bloomLevel: Double) {
        switch bloomLevel {
        case ..<0.2:
            stemHeight = 0.4
            leafScale = 0.5
            leafCount = 3
        case ..<0.5:
            stemHeight = 0.7
            leafScale = 0.75
            leafCount = 5
        case ..<0.8:
            stemHeight = 1.0
            leafScale = 1.0
            leafCount = 7
        default:
            stemHeight = 1.3
            leafScale = 1.2
            leafCount = 9
        }
    }
}
