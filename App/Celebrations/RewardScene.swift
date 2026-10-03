import SceneKit
import SwiftUI
import UIKit

/// Geometry is built once per presentation; SwiftUI updates never recreate the scene.
@MainActor
final class RewardScene: ObservableObject {
    let scene = SCNScene()
    let camera = SCNNode()
    private var stars: [SCNNode] = []
    private let medal = SCNNode()
    private let medalGlyph = SCNNode()
    private let sheen = SCNNode()
    private let earnedStars: Int

    init(stars: Int) {
        earnedStars = max(0, min(3, stars))
        configureScene()
        buildStars()
        buildMedal()
    }

    func launchStar(_ index: Int, impact: @escaping @MainActor () -> Void) {
        guard stars.indices.contains(index), index < earnedStars else { return }
        let node = stars[index]
        node.removeAllActions()
        node.isHidden = false
        node.opacity = 0
        node.position = SCNVector3(0, -2.5, -3.5)
        node.scale = SCNVector3(0.1, 0.14, 0.1)
        node.eulerAngles = SCNVector3(-0.4, index.isMultiple(of: 2) ? -1.2 : 1.2, index.isMultiple(of: 2) ? -0.6 : 0.6)
        let peak: CGFloat = index == 2 ? 1.94 : 1.76
        let pop = SCNAction.group([
            .move(to: SCNVector3(0, 0.45, 2.2), duration: 0.18),
            .scale(to: peak, duration: 0.18),
            .rotateTo(x: -0.07, y: index.isMultiple(of: 2) ? 0.36 : -0.36, z: index.isMultiple(of: 2) ? -0.08 : 0.08, duration: 0.18, usesShortestUnitArc: true),
            .fadeIn(duration: 0.12)
        ])
        pop.timingMode = .easeOut
        let squish = SCNAction.customAction(duration: 0.08) { node, time in
            let t = Float(time / 0.08)
            let value = Float(peak)
            node.scale = SCNVector3(value * (1 + 0.13 * t), value * (1 - 0.18 * t), value)
        }
        let rebound = SCNAction.group([
            .move(to: SCNVector3(0, 0.72, 1.5), duration: 0.11),
            .scale(to: peak * 0.98, duration: 0.11)
        ])
        rebound.timingMode = .easeOut
        let settle = SCNAction.group([
            .move(to: finalPosition(index), duration: 0.3),
            .scale(to: index == 1 ? 1.18 : 1.08, duration: 0.3),
            .rotateTo(x: -0.1, y: index == 0 ? -0.18 : (index == 2 ? 0.18 : 0), z: index == 0 ? -0.11 : (index == 2 ? 0.11 : 0), duration: 0.3, usesShortestUnitArc: true)
        ])
        settle.timingMode = .easeInEaseOut
        node.runAction(.sequence([
            pop,
            // Deliver the contact event directly on the main queue; no extra Task hop.
            .run({ _ in MainActor.assumeIsolated { impact() } }, queue: .main),
            squish,
            rebound,
            settle
        ]))
    }

    func launchMedal(symbol: String, impact: @escaping @MainActor () -> Void) {
        for star in stars { star.runAction(.fadeOut(duration: 0.15)) }
        configureGlyph(symbol)
        medal.removeAllActions()
        medal.isHidden = false
        medal.opacity = 0
        medal.position = SCNVector3(0, -1.3, -4)
        medal.scale = SCNVector3(0.16, 0.16, 0.16)
        medal.eulerAngles = SCNVector3(0.25, -2.9, -0.35)
        let flight = SCNAction.group([
            .move(to: SCNVector3(0, 0.35, 2), duration: 0.42),
            .scale(to: 1.86, duration: 0.42),
            .rotateTo(x: -0.12, y: 0, z: 0, duration: 0.42, usesShortestUnitArc: true),
            .fadeIn(duration: 0.16)
        ])
        flight.timingMode = .easeOut
        let squash = SCNAction.customAction(duration: 0.08) { node, time in
            let t = Float(time / 0.08)
            node.scale = SCNVector3(1.86 + 0.13 * t, 1.86 - 0.17 * t, 1.86)
        }
        let bounce = SCNAction.group([.scale(to: 1.86, duration: 0.14), .moveBy(x: 0, y: 0.2, z: 0, duration: 0.14)])
        let collect = SCNAction.group([
            .move(to: SCNVector3(0, -0.1, 0), duration: 0.4),
            .scale(to: 1.05, duration: 0.4),
            .rotateTo(x: -0.08, y: 0.16, z: 0, duration: 0.4)
        ])
        collect.timingMode = .easeInEaseOut
        medal.runAction(.sequence([
            flight,
            .run { _ in Task { @MainActor in impact() } },
            squash,
            bounce,
            .wait(duration: 0.18),
            collect
        ]))
        sheen.position = SCNVector3(-5, 4, 6)
        sheen.runAction(.move(to: SCNVector3(5, 4, 6), duration: 1.1))
    }

    func showFinalStars() {
        stop()
        medal.isHidden = true
        for (index, node) in stars.enumerated() {
            node.isHidden = index >= earnedStars
            node.opacity = 1
            node.position = finalPosition(index)
            let size: Float = index == 1 ? 1.18 : 1.08
            node.scale = SCNVector3(size, size, size)
            node.eulerAngles = SCNVector3(-0.1, index == 0 ? -0.18 : (index == 2 ? 0.18 : 0), index == 0 ? -0.11 : (index == 2 ? 0.11 : 0))
        }
    }

    func showFinalMedal(symbol: String) {
        stop()
        stars.forEach { $0.isHidden = true }
        configureGlyph(symbol)
        medal.isHidden = false
        medal.opacity = 1
        medal.position = SCNVector3(0, 0.3, 0)
        medal.scale = SCNVector3(1.5, 1.5, 1.5)
        medal.eulerAngles = SCNVector3(-0.08, 0.12, 0)
    }

    func stop() {
        stars.forEach { $0.removeAllActions() }
        medal.removeAllActions()
        sheen.removeAllActions()
    }

    private func finalPosition(_ index: Int) -> SCNVector3 {
        // Earned stars are centered even when only one or two were awarded.
        if earnedStars == 1 { return SCNVector3(0, 0.3, 0) }
        if earnedStars == 2 { return SCNVector3(index == 0 ? -1.45 : 1.45, 0.3, 0) }
        return SCNVector3(Float(index - 1) * 2.5, index == 1 ? 0.5 : -0.1, 0)
    }

    private func configureScene() {
        scene.background.contents = UIColor.clear
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 40
        camera.camera?.projectionDirection = .horizontal
        camera.camera?.zNear = 0.1
        camera.camera?.zFar = 40
        camera.position = SCNVector3(0, 0, 12)
        scene.rootNode.addChildNode(camera)

        addLight(type: .ambient, color: UIColor(red: 0.82, green: 0.88, blue: 1, alpha: 1), intensity: 420, position: .init(0, 0, 8))
        addLight(type: .omni, color: UIColor(red: 1, green: 0.94, blue: 0.7, alpha: 1), intensity: 1_250, position: .init(-4, 5, 7))
        addLight(type: .omni, color: UIColor(red: 1, green: 0.66, blue: 0.18, alpha: 1), intensity: 650, position: .init(4, -2, 3))
        addLight(type: .omni, color: UIColor(red: 0.64, green: 0.85, blue: 1, alpha: 1), intensity: 900, position: .init(0, 4, -2))
        let shadowLight = SCNNode()
        shadowLight.light = SCNLight()
        shadowLight.light?.type = .spot
        shadowLight.light?.intensity = 350
        shadowLight.light?.castsShadow = true
        shadowLight.light?.shadowColor = UIColor.black.withAlphaComponent(0.28)
        shadowLight.light?.shadowMapSize = CGSize(width: 512, height: 512)
        shadowLight.light?.shadowRadius = 5
        shadowLight.light?.spotInnerAngle = 55
        shadowLight.light?.spotOuterAngle = 80
        shadowLight.position = SCNVector3(-3, 5, 8)
        shadowLight.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(shadowLight)

        let shadowSurface = SCNPlane(width: 18, height: 18)
        let shadowMaterial = SCNMaterial()
        shadowMaterial.lightingModel = .shadowOnly
        shadowMaterial.writesToDepthBuffer = false
        shadowSurface.materials = [shadowMaterial]
        let shadowNode = SCNNode(geometry: shadowSurface)
        shadowNode.position.z = -0.8
        shadowNode.castsShadow = false
        scene.rootNode.addChildNode(shadowNode)
        sheen.light = SCNLight()
        sheen.light?.type = .omni
        sheen.light?.color = UIColor.white
        sheen.light?.intensity = 550
        sheen.position = .init(-5, 4, 6)
        scene.rootNode.addChildNode(sheen)
        // A small reflection map supplies broad specular bands without a texture asset.
        scene.lightingEnvironment.contents = reflectionMap()
        scene.lightingEnvironment.intensity = 0.75
    }

    private func addLight(type: SCNLight.LightType, color: UIColor, intensity: CGFloat, position: SCNVector3) {
        let node = SCNNode()
        node.light = SCNLight()
        node.light?.type = type
        node.light?.color = color
        node.light?.intensity = intensity
        node.position = position
        scene.rootNode.addChildNode(node)
    }

    private func buildStars() {
        for _ in 0..<3 {
            let geometry = SCNShape(path: Self.starPath(radius: 1), extrusionDepth: 0.32)
            geometry.chamferRadius = 0.085
            geometry.chamferMode = .both
            geometry.materials = [gold(red: 1, green: 0.79, blue: 0.08), gold(red: 1, green: 0.72, blue: 0.07), gold(red: 0.74, green: 0.36, blue: 0.015), gold(red: 1, green: 0.87, blue: 0.26), gold(red: 1, green: 0.87, blue: 0.26)]
            let star = SCNNode(geometry: geometry)
            star.isHidden = true
            star.castsShadow = true
            scene.rootNode.addChildNode(star)
            stars.append(star)
            // A raised small inset carries another specular edge across the front face.
            let inset = SCNShape(path: Self.starPath(radius: 0.78), extrusionDepth: 0.012)
            inset.chamferRadius = 0.025
            inset.materials = [gold(red: 1, green: 0.84, blue: 0.14, roughness: 0.26)]
            let face = SCNNode(geometry: inset)
            face.position.z = 0.171
            star.addChildNode(face)
        }
    }

    private func buildMedal() {
        scene.rootNode.addChildNode(medal)
        medal.isHidden = true
        let body = SCNCylinder(radius: 1.12, height: 0.24)
        body.radialSegmentCount = 96
        body.materials = [gold(red: 0.94, green: 0.63, blue: 0.06), gold(red: 1, green: 0.84, blue: 0.25), gold(red: 0.8, green: 0.45, blue: 0.02)]
        let bodyNode = SCNNode(geometry: body)
        bodyNode.eulerAngles.x = .pi / 2
        bodyNode.castsShadow = true
        medal.addChildNode(bodyNode)

        let ring = SCNTorus(ringRadius: 1.01, pipeRadius: 0.055)
        ring.ringSegmentCount = 96
        ring.pipeSegmentCount = 16
        ring.materials = [gold(red: 1, green: 0.9, blue: 0.42, roughness: 0.16)]
        let rim = SCNNode(geometry: ring)
        rim.eulerAngles.x = .pi / 2
        rim.position.z = 0.145
        medal.addChildNode(rim)

        let face = SCNCylinder(radius: 0.92, height: 0.035)
        face.radialSegmentCount = 96
        face.materials = [gold(red: 0.88, green: 0.51, blue: 0.035), gold(red: 1, green: 0.75, blue: 0.12)]
        let faceNode = SCNNode(geometry: face)
        faceNode.eulerAngles.x = .pi / 2
        faceNode.position.z = 0.14
        medal.addChildNode(faceNode)

        let glyphPlane = SCNPlane(width: 1.08, height: 1.08)
        medalGlyph.geometry = glyphPlane
        medalGlyph.position.z = 0.17
        medal.addChildNode(medalGlyph)

        // Real metal studs remain visible when the medal turns sideways.
        for index in 0..<12 {
            let stud = SCNSphere(radius: 0.025)
            stud.segmentCount = 8
            stud.materials = [gold(red: 1, green: 0.93, blue: 0.53)]
            let node = SCNNode(geometry: stud)
            let angle = Double(index) * .pi / 6
            node.position = .init(Float(cos(angle) * 0.96), Float(sin(angle) * 0.96), 0.18)
            medal.addChildNode(node)
        }
    }

    private func configureGlyph(_ symbol: String) {
        let configuration = UIImage.SymbolConfiguration(pointSize: 160, weight: .black)
        let image = UIImage(systemName: symbol, withConfiguration: configuration)?.withTintColor(UIColor(red: 0.36, green: 0.16, blue: 0.015, alpha: 1), renderingMode: .alwaysOriginal)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = image
        material.isDoubleSided = false
        material.writesToDepthBuffer = false
        medalGlyph.geometry?.materials = [material]
    }

    private func gold(red: CGFloat, green: CGFloat, blue: CGFloat, roughness: CGFloat = 0.2) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor(red: red, green: green, blue: blue, alpha: 1)
        material.metalness.contents = 0.74
        material.roughness.contents = roughness
        return material
    }

    private static func starPath(radius: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        for index in 0..<10 {
            let angle = CGFloat.pi / 2 + CGFloat(index) * CGFloat.pi / 5
            let distance = index.isMultiple(of: 2) ? radius : radius * 0.49
            let point = CGPoint(x: cos(angle) * distance, y: sin(angle) * distance)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.close()
        return path
    }

    private func reflectionMap() -> UIImage {
        let size = CGSize(width: 256, height: 128)
        return UIGraphicsImageRenderer(size: size).image { renderer in
            let colors = [UIColor(red: 0.22, green: 0.29, blue: 0.42, alpha: 1).cgColor, UIColor.white.cgColor, UIColor(red: 0.98, green: 0.77, blue: 0.38, alpha: 1).cgColor, UIColor(red: 0.14, green: 0.2, blue: 0.35, alpha: 1).cgColor]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 0.32, 0.4, 1]) {
                renderer.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
        }
    }
}

struct RewardSceneView: UIViewRepresentable {
    let rewardScene: RewardScene
    let isPlaying: Bool

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = rewardScene.scene
        view.pointOfView = rewardScene.camera
        view.backgroundColor = .clear
        view.isOpaque = false
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.isPlaying = isPlaying
        view.rendersContinuously = false
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        if uiView.isPlaying != isPlaying { uiView.isPlaying = isPlaying }
        // A settled/reduced-motion result still needs a draw after its nodes
        // change, even though the animation clock is no longer playing.
        uiView.setNeedsDisplay()
    }

    static func dismantleUIView(_ uiView: SCNView, coordinator: ()) {
        uiView.isPlaying = false
        uiView.scene = nil
    }
}
