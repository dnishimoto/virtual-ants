//
//  File.swift
//  Virtual Ants
//
//  Created by David Nishimoto on 9/18/26.
//

import Foundation
import SwiftUI
import SceneKit
import UIKit

// MARK: - 3D Scene View

struct AntColony3DView: UIViewRepresentable {

    let simulation: AntColonySimulation
    let soilTransparency: Double
    let showGround: Bool
    let showFood: Bool
    let showAnts: Bool
    let showPheromones: Bool
    let showInvaders: Bool = true
    let cameraResetToken: UUID

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(
        context: Context
    ) -> SCNView {

        let view = SCNView()

        view.backgroundColor = UIColor(
            red: 0.025,
            green: 0.030,
            blue: 0.040,
            alpha: 1
        )

        view.allowsCameraControl = true
        view.rendersContinuously = true
        view.preferredFramesPerSecond = 60
        view.antialiasingMode = .multisampling4X

        let scene = SCNScene()

        scene.background.contents = UIColor(
            red: 0.025,
            green: 0.030,
            blue: 0.040,
            alpha: 1
        )

        scene.fogStartDistance = 45
        scene.fogEndDistance = 100

        scene.fogColor = UIColor(
            red: 0.025,
            green: 0.030,
            blue: 0.040,
            alpha: 1
        )

        view.scene = scene

        context.coordinator.configure(
            scene: scene,
            view: view
        )

        return view
    }

    func updateUIView(
        _ view: SCNView,
        context: Context
    ) {

        context.coordinator.update(
            simulation: simulation,
            soilTransparency: soilTransparency,
            showGround: showGround,
            showFood: showFood,
            showAnts: showAnts,
            showPheromones: showPheromones,
            showInvaders: showInvaders,
            cameraResetToken: cameraResetToken
        )
    }

    static func dismantleUIView(
        _ uiView: SCNView,
        coordinator: Coordinator
    ) {

        coordinator.stop()
        uiView.delegate = nil
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator:
        NSObject,
        SCNSceneRendererDelegate {

        weak var sceneView: SCNView?

        var simulation:
            AntColonySimulation?

        private let rootNode =
            SCNNode()

        private let terrainNode =
            SCNNode()

        private let colonyNode =
            SCNNode()

        private let foodNode =
            SCNNode()

        private let antNode =
            SCNNode()

        private let invaderNode =
            SCNNode()

        private let pheromoneNode =
            SCNNode()

        private var cameraNode:
            SCNNode?

        // Dynamic ants.
        private var antNodes:
            [UUID: SCNNode] = [:]

        // Dynamic food.
        private var foodNodes:
            [UUID: SCNNode] = [:]

        // Dynamic invaders.
        private var invaderNodes:
            [UUID: SCNNode] = [:]

        private var lastAntPositions:
            [UUID: SCNVector3] = [:]

        private var lastInvaderPositions:
            [UUID: SCNVector3] = [:]

        private var lastTunnelCount = -1
        private var lastStorageCount = -1
        private var lastObstacleCount = -1

        private var lastGroundVisibility =
            false

        private var lastSoilTransparency:
            Double = -1

        private var lastPheromoneVisibility =
            false

        private var lastInvaderVisibility =
            true

        private var hasBuiltStaticScene =
            false

        private var lastCameraResetToken:
            UUID?

        private let cellSize:
            CGFloat = 0.42

        private let groundThickness:
            CGFloat = 0.55

        private let tunnelHeight:
            CGFloat = 0.42

        private let chamberHeight:
            CGFloat = 0.62

        // MARK: - Configure

        func configure(
            scene: SCNScene,
            view: SCNView
        ) {

            sceneView = view

            view.delegate = self

            scene.rootNode.addChildNode(
                rootNode
            )

            rootNode.addChildNode(
                terrainNode
            )

            rootNode.addChildNode(
                colonyNode
            )

            rootNode.addChildNode(
                foodNode
            )

            rootNode.addChildNode(
                antNode
            )

            rootNode.addChildNode(
                invaderNode
            )

            rootNode.addChildNode(
                pheromoneNode
            )

            configureLighting(
                scene: scene
            )

            configureCamera(
                scene: scene,
                view: view
            )
        }

        // MARK: - Lighting

        private func configureLighting(
            scene: SCNScene
        ) {

            let keyNode = SCNNode()

            let keyLight = SCNLight()
            keyLight.type = .omni
            keyLight.intensity = 1200
            keyLight.color = UIColor.white

            keyNode.light = keyLight

            keyNode.position = SCNVector3(
                0,
                18,
                5
            )

            rootNode.addChildNode(
                keyNode
            )

            let fillNode = SCNNode()

            let fillLight = SCNLight()
            fillLight.type = .ambient
            fillLight.intensity = 500
            fillLight.color = UIColor(
                white: 0.75,
                alpha: 1
            )

            fillNode.light = fillLight

            rootNode.addChildNode(
                fillNode
            )
        }

        // MARK: - Camera

        private func configureCamera(
            scene: SCNScene,
            view: SCNView
        ) {

            let camera = SCNNode()

            let cameraComponent = SCNCamera()
            cameraComponent.fieldOfView = 52
            cameraComponent.zNear = 0.1
            cameraComponent.zFar = 250

            camera.camera = cameraComponent

            camera.position = SCNVector3(
                0,
                18,
                25
            )

            camera.look(
                at: SCNVector3(
                    0,
                    -0.5,
                    0
                )
            )

            scene.rootNode.addChildNode(
                camera
            )

            cameraNode = camera

            view.pointOfView = camera

            view.allowsCameraControl = true
            view.defaultCameraController.inertiaEnabled = true
        }

        // MARK: - Update

        func update(
            simulation:
                AntColonySimulation,
            soilTransparency:
                Double,
            showGround:
                Bool,
            showFood:
                Bool,
            showAnts:
                Bool,
            showPheromones:
                Bool,
            showInvaders:
                Bool,
            cameraResetToken:
                UUID
        ) {

            self.simulation = simulation

            if lastCameraResetToken != cameraResetToken {

                resetCamera()

                lastCameraResetToken =
                    cameraResetToken
            }

            let tunnelCount =
                simulation.tunnelsBuilt

            let storageCount =
                simulation.storageChambersBuilt

            let obstacleCount =
                countObstacles(
                    simulation: simulation
                )

            let structureChanged =
                !hasBuiltStaticScene
                || tunnelCount != lastTunnelCount
                || storageCount != lastStorageCount
                || obstacleCount != lastObstacleCount
                || showGround != lastGroundVisibility
                || abs(
                    soilTransparency
                    - lastSoilTransparency
                ) > 0.001

            if structureChanged {

                rebuildStaticScene(
                    simulation: simulation,
                    soilTransparency: soilTransparency,
                    showGround: showGround
                )

                lastTunnelCount =
                    tunnelCount

                lastStorageCount =
                    storageCount

                lastObstacleCount =
                    obstacleCount

                lastGroundVisibility =
                    showGround

                lastSoilTransparency =
                    soilTransparency

                hasBuiltStaticScene =
                    true
            }

            if showPheromones !=
                lastPheromoneVisibility {

                rebuildPheromoneNodes(
                    simulation: simulation,
                    enabled: showPheromones
                )

                lastPheromoneVisibility =
                    showPheromones
            }

            if showInvaders !=
                lastInvaderVisibility {

                if !showInvaders {

                    invaderNode.childNodes
                        .forEach {
                            $0.isHidden = true
                        }

                } else {

                    invaderNode.childNodes
                        .forEach {
                            $0.isHidden = false
                        }
                }

                lastInvaderVisibility =
                    showInvaders
            }

            updateDynamicState(
                simulation: simulation,
                showAnts: showAnts,
                showFood: showFood,
                showInvaders: showInvaders,
                animate: false
            )
        }

        // MARK: - Continuous Rendering

        func renderer(
            _ renderer:
                SCNSceneRenderer,
            updateAtTime time:
                TimeInterval
        ) {

            guard let simulation
            else {
                return
            }

            updateDynamicState(
                simulation: simulation,
                showAnts: true,
                showFood: true,
                showInvaders: lastInvaderVisibility,
                animate: true
            )
        }

        // MARK: - Dynamic State

        private func updateDynamicState(
            simulation:
                AntColonySimulation,
            showAnts:
                Bool,
            showFood:
                Bool,
            showInvaders:
                Bool,
            animate:
                Bool
        ) {

            if showAnts {

                antNode.isHidden = false

                updateAntNodes(
                    simulation: simulation,
                    animate: animate
                )

            } else {

                antNode.isHidden = true
            }

            if showFood {

                foodNode.isHidden = false

                updateFoodNodes(
                    simulation: simulation
                )

            } else {

                foodNode.isHidden = true
            }

            if showInvaders {

                invaderNode.isHidden = false

                updateInvaderNodes(
                    simulation: simulation,
                    animate: animate
                )

            } else {

                invaderNode.isHidden = true
            }

            if lastPheromoneVisibility {

                updatePheromoneValues(
                    simulation: simulation
                )
            }
        }

        // MARK: - Ant Nodes

        private func updateAntNodes(
            simulation:
                AntColonySimulation,
            animate:
                Bool
        ) {

            var livingIDs =
                Set<UUID>()

            livingIDs.reserveCapacity(
                simulation.ants.count
            )

            for ant in simulation.ants {

                livingIDs.insert(
                    ant.id
                )

                let node: SCNNode

                if let existing =
                    antNodes[ant.id] {

                    node = existing

                } else {

                    node =
                        createAntNode(
                            ant: ant
                        )

                    antNodes[ant.id] =
                        node

                    antNode.addChildNode(
                        node
                    )
                }

                updateAntNode(
                    node,
                    ant: ant,
                    simulation: simulation,
                    animate: animate
                )
            }

            let deadIDs =
                antNodes.keys.filter {
                    !livingIDs.contains($0)
                }

            for id in deadIDs {

                antNodes[id]?
                    .removeFromParentNode()

                antNodes.removeValue(
                    forKey: id
                )

                lastAntPositions
                    .removeValue(
                        forKey: id
                    )
            }
        }

        private func createAntNode(
            ant: Ant
        ) -> SCNNode {

            let container = SCNNode()

            container.name =
                "ant-\(ant.id.uuidString)"

            let bodyGeometry =
                SCNSphere(
                    radius: 0.115
                )

            bodyGeometry.segmentCount = 8
            bodyGeometry.firstMaterial =
                antMaterial()

            let body =
                SCNNode(
                    geometry: bodyGeometry
                )

            container.addChildNode(
                body
            )

            let headGeometry =
                SCNSphere(
                    radius: 0.075
                )

            headGeometry.segmentCount = 7
            headGeometry.firstMaterial =
                antMaterial()

            let head =
                SCNNode(
                    geometry: headGeometry
                )

            head.position =
                SCNVector3(
                    0.13,
                    0.02,
                    0
                )

            container.addChildNode(
                head
            )

            let stateGeometry =
                SCNSphere(
                    radius: 0.045
                )

            stateGeometry.segmentCount = 6
            stateGeometry.firstMaterial =
                stateMaterial()

            let stateLight =
                SCNNode(
                    geometry: stateGeometry
                )

            stateLight.name =
                "stateLight"

            stateLight.position =
                SCNVector3(
                    0,
                    0.13,
                    0
                )

            container.addChildNode(
                stateLight
            )

            return container
        }

        private func updateAntNode(
            _ node: SCNNode,
            ant: Ant,
            simulation:
                AntColonySimulation,
            animate:
                Bool
        ) {

            let target =
                worldPosition(
                    x: ant.x,
                    y: ant.y,
                    depth: antDepth(for: ant),
                    simulation: simulation
                )

            let previous =
                lastAntPositions[ant.id]

            if animate,
               let previous,
               distanceSquared(
                    previous,
                    target
               ) > 0.000001 {

                SCNTransaction.begin()

                SCNTransaction.animationDuration =
                    0.065

                SCNTransaction.animationTimingFunction =
                    CAMediaTimingFunction(
                        name: .easeInEaseOut
                    )

                node.position =
                    target

                SCNTransaction.commit()

            } else {

                node.position =
                    target
            }

            lastAntPositions[ant.id] =
                target

            let directionX =
                Float(ant.directionX)

            let directionY =
                Float(ant.directionY)

            if abs(directionX) > 0.001
                || abs(directionY) > 0.001 {

                let angle =
                    atan2(
                        directionY,
                        directionX
                    )

                node.eulerAngles.y =
                    -Float(angle)
            }

            updateAntAppearance(
                node: node,
                ant: ant
            )
        }

        private func antDepth(
            for ant: Ant
        ) -> CGFloat {

            switch ant.state {

            case .building:
                return -0.95

            case .resting:
                return -0.82

            case .returning:
                return -0.78

            case .exploring:
                return -0.70

            case .searching:
                return -0.66

            default:
                return -0.70
            }
        }

        private func updateAntAppearance(
            node: SCNNode,
            ant: Ant
        ) {

            let material =
                antMaterial()

            switch ant.state {

            case .searching:

                material.diffuse.contents =
                    UIColor(
                        red: 0.95,
                        green: 0.65,
                        blue: 0.20,
                        alpha: 1
                    )

            case .returning:

                material.diffuse.contents =
                    UIColor(
                        red: 0.35,
                        green: 0.85,
                        blue: 1.0,
                        alpha: 1
                    )

            case .building:

                material.diffuse.contents =
                    UIColor(
                        red: 0.80,
                        green: 0.55,
                        blue: 0.30,
                        alpha: 1
                    )

            case .resting:

                material.diffuse.contents =
                    UIColor(
                        white: 0.55,
                        alpha: 1
                    )

            case .exploring:

                material.diffuse.contents =
                    UIColor(
                        red: 0.70,
                        green: 0.90,
                        blue: 0.40,
                        alpha: 1
                    )

            default:
                break
            }

            if let body =
                node.childNodes.first {

                body.geometry?
                    .firstMaterial =
                    material
            }

            if let stateLight =
                node.childNode(
                    withName: "stateLight",
                    recursively: false
                ) {

                stateLight.geometry?
                    .firstMaterial?
                    .emission.contents =
                    stateEmission(
                        state: ant.state
                    )
            }
        }

        // MARK: - Invaders

        private func updateInvaderNodes(
            simulation:
                AntColonySimulation,
            animate:
                Bool
        ) {

            var livingIDs =
                Set<UUID>()

            livingIDs.reserveCapacity(
                simulation.invaders.count
            )

            for invader in simulation.invaders {

                guard invader.alive,
                      invader.health > 0
                else {
                    continue
                }

                livingIDs.insert(
                    invader.id
                )

                let node: SCNNode

                if let existing =
                    invaderNodes[invader.id] {

                    node = existing

                } else {

                    node =
                        createInvaderNode(
                            invader: invader
                        )

                    invaderNodes[
                        invader.id
                    ] = node

                    invaderNode.addChildNode(
                        node
                    )
                }

                updateInvaderNode(
                    node,
                    invader: invader,
                    simulation: simulation,
                    animate: animate
                )
            }

            let staleIDs =
                invaderNodes.keys.filter {
                    !livingIDs.contains($0)
                }

            for id in staleIDs {

                invaderNodes[id]?
                    .removeFromParentNode()

                invaderNodes.removeValue(
                    forKey: id
                )

                lastInvaderPositions
                    .removeValue(
                        forKey: id
                    )
            }
        }

        private func createInvaderNode(
            invader:
                ColonyInvader
        ) -> SCNNode {

            switch invader.type {

            case .rivalAnt:

                return createRivalAntNode(
                    invader: invader
                )

            case .cockroach:

                return createCockroachNode(
                    invader: invader
                )

            case .mouse:

                return createMouseNode(
                    invader: invader
                )

            case .worm:

                return createWormNode(
                    invader: invader
                )

            case .spider:

                return createSpiderNode(
                    invader: invader
                )
            }
        }

        private func updateInvaderNode(
            _ node: SCNNode,
            invader:
                ColonyInvader,
            simulation:
                AntColonySimulation,
            animate:
                Bool
        ) {

            let target =
                worldPosition(
                    x: invader.x,
                    y: invader.y,
                    depth: invaderDepth(
                        type: invader.type
                    ),
                    simulation: simulation
                )

            let previous =
                lastInvaderPositions[
                    invader.id
                ]

            if animate,
               let previous,
               distanceSquared(
                    previous,
                    target
               ) > 0.000001 {

                SCNTransaction.begin()

                SCNTransaction.animationDuration =
                    0.085

                SCNTransaction.animationTimingFunction =
                    CAMediaTimingFunction(
                        name: .easeInEaseOut
                    )

                node.position =
                    target

                SCNTransaction.commit()

            } else {

                node.position =
                    target
            }

            lastInvaderPositions[
                invader.id
            ] = target

            let dx =
                Float(invader.directionX)

            let dy =
                Float(invader.directionY)

            if abs(dx) > 0.001
                || abs(dy) > 0.001 {

                let angle =
                    atan2(
                        dy,
                        dx
                    )

                node.eulerAngles.y =
                    -Float(angle)
            }

            let health =
                max(
                    0,
                    min(
                        1,
                        invader.health
                    )
                )

            node.opacity =
                CGFloat(
                    0.35
                    + 0.65 * health
                )

            node.scale =
                SCNVector3(
                    0.75 + Float(health) * 0.25,
                    0.75 + Float(health) * 0.25,
                    0.75 + Float(health) * 0.25
                )

            updateInvaderHealthIndicator(
                node: node,
                health: health
            )
        }

        private func invaderDepth(
            type:
                InvaderType
        ) -> CGFloat {

            switch type {

            case .rivalAnt:
                return -0.60

            case .cockroach:
                return -0.57

            case .mouse:
                return -0.48

            case .worm:
                return -0.54

            case .spider:
                return -0.56
            }
        }

        // MARK: - Rival Ant

        private func createRivalAntNode(
            invader:
                ColonyInvader
        ) -> SCNNode {

            let container = SCNNode()

            container.name =
                "invader-rival-ant-\(invader.id.uuidString)"

            let abdomen =
                SCNSphere(radius: 0.15)

            abdomen.segmentCount = 8
            abdomen.firstMaterial =
                invaderMaterial(
                    diffuse: UIColor(
                        red: 0.55,
                        green: 0.10,
                        blue: 0.08,
                        alpha: 1
                    )
                )

            let abdomenNode =
                SCNNode(
                    geometry: abdomen
                )

            abdomenNode.scale =
                SCNVector3(
                    1.15,
                    0.80,
                    0.90
                )

            container.addChildNode(
                abdomenNode
            )

            let thorax =
                SCNSphere(radius: 0.11)

            thorax.segmentCount = 8
            thorax.firstMaterial =
                invaderMaterial(
                    diffuse: UIColor(
                        red: 0.40,
                        green: 0.07,
                        blue: 0.05,
                        alpha: 1
                    )
                )

            let thoraxNode =
                SCNNode(
                    geometry: thorax
                )

            thoraxNode.position =
                SCNVector3(
                    0.12,
                    0,
                    0
                )

            container.addChildNode(
                thoraxNode
            )

            let head =
                SCNSphere(radius: 0.075)

            head.segmentCount = 7
            head.firstMaterial =
                invaderMaterial(
                    diffuse: UIColor(
                        red: 0.30,
                        green: 0.04,
                        blue: 0.03,
                        alpha: 1
                    )
                )

            let headNode =
                SCNNode(
                    geometry: head
                )

            headNode.position =
                SCNVector3(
                    0.24,
                    0.01,
                    0
                )

            container.addChildNode(
                headNode
            )

            addInvaderLegs(
                to: container,
                count: 6,
                length: 0.16,
                thickness: 0.018
            )

            return container
        }

        // MARK: - Cockroach

        private func createCockroachNode(
            invader:
                ColonyInvader
        ) -> SCNNode {

            let container = SCNNode()

            container.name =
                "invader-cockroach-\(invader.id.uuidString)"

            let body =
                SCNSphere(radius: 0.20)

            body.segmentCount = 10

            body.firstMaterial =
                invaderMaterial(
                    diffuse: UIColor(
                        red: 0.18,
                        green: 0.08,
                        blue: 0.035,
                        alpha: 1
                    )
                )

            let bodyNode =
                SCNNode(
                    geometry: body
                )

            bodyNode.scale =
                SCNVector3(
                    1.55,
                    0.45,
                    0.80
                )

            container.addChildNode(
                bodyNode
            )

            let head =
                SCNSphere(radius: 0.09)

            head.segmentCount = 7
            head.firstMaterial =
                invaderMaterial(
                    diffuse: UIColor(
                        red: 0.12,
                        green: 0.045,
                        blue: 0.02,
                        alpha: 1
                    )
                )

            let headNode =
                SCNNode(
                    geometry: head
                )

            headNode.position =
                SCNVector3(
                    0.28,
                    0,
                    0
                )

            container.addChildNode(
                headNode
            )

            addAntennae(
                to: container,
                length: 0.30
            )

            addInvaderLegs(
                to: container,
                count: 6,
                length: 0.28,
                thickness: 0.018
            )

            return container
        }

        // MARK: - Mouse

        private func createMouseNode(
            invader:
                ColonyInvader
        ) -> SCNNode {

            let container = SCNNode()

            container.name =
                "invader-mouse-\(invader.id.uuidString)"

            let body =
                SCNSphere(radius: 0.26)

            body.segmentCount = 10

            body.firstMaterial =
                invaderMaterial(
                    diffuse: UIColor(
                        white: 0.42,
                        alpha: 1
                    )
                )

            let bodyNode =
                SCNNode(
                    geometry: body
                )

            bodyNode.scale =
                SCNVector3(
                    1.35,
                    0.85,
                    0.85
                )

            container.addChildNode(
                bodyNode
            )

            let head =
                SCNSphere(radius: 0.17)

            head.segmentCount = 9

            head.firstMaterial =
                invaderMaterial(
                    diffuse: UIColor(
                        white: 0.48,
                        alpha: 1
                    )
                )

            let headNode =
                SCNNode(
                    geometry: head
                )

            headNode.position =
                SCNVector3(
                    0.30,
                    0.02,
                    0
                )

            container.addChildNode(
                headNode
            )

            let earGeometry =
                SCNCylinder(
                    radius: 0.075,
                    height: 0.035
                )

            earGeometry.radialSegmentCount = 8
            earGeometry.firstMaterial =
                invaderMaterial(
                    diffuse: UIColor(
                        red: 0.65,
                        green: 0.35,
                        blue: 0.35,
                        alpha: 1
                    )
                )

            let leftEar =
                SCNNode(
                    geometry: earGeometry
                )

            leftEar.position =
                SCNVector3(
                    0.23,
                    0.16,
                    0.10
                )

            leftEar.eulerAngles.z =
                Float.pi / 2

            container.addChildNode(
                leftEar
            )

            let rightEar =
                leftEar.clone()

            rightEar.position.z =
                -0.10

            container.addChildNode(
                rightEar
            )

            let eyeGeometry =
                SCNSphere(
                    radius: 0.025
                )

            eyeGeometry.segmentCount = 6

            let eyeMaterial =
                SCNMaterial()

            eyeMaterial.diffuse.contents =
                UIColor.black

            eyeMaterial.emission.contents =
                UIColor.white

            eyeMaterial.emission.intensity =
                0.15

            eyeGeometry.firstMaterial =
                eyeMaterial

            let eye =
                SCNNode(
                    geometry: eyeGeometry
                )

            eye.position =
                SCNVector3(
                    0.43,
                    0.08,
                    0.08
                )

            container.addChildNode(
                eye
            )

            let secondEye =
                eye.clone()

            secondEye.position.z =
                -0.08

            container.addChildNode(
                secondEye
            )

            addMouseTail(
                to: container
            )

            return container
        }

        private func addMouseTail(
            to container: SCNNode
        ) {

            let material =
                invaderMaterial(
                    diffuse: UIColor(
                        red: 0.55,
                        green: 0.32,
                        blue: 0.30,
                        alpha: 1
                    )
                )

            var previous =
                SCNVector3(
                    -0.25,
                    0,
                    0
                )

            for index in 0..<5 {

                let geometry =
                    SCNSphere(
                        radius:
                            0.035
                    )

                geometry.segmentCount = 6
                geometry.firstMaterial =
                    material

                let node =
                    SCNNode(
                        geometry: geometry
                    )

                let offset =
                    Float(index + 1)

                node.position =
                    SCNVector3(
                        -0.25 - offset * 0.10,
                        -0.01 * offset,
                        sin(offset) * 0.025
                    )

                container.addChildNode(
                    node
                )

                previous =
                    node.position
            }

            _ = previous
        }

        // MARK: - Worm

        private func createWormNode(
            invader:
                ColonyInvader
        ) -> SCNNode {

            let container = SCNNode()

            container.name =
                "invader-worm-\(invader.id.uuidString)"

            let material =
                invaderMaterial(
                    diffuse: UIColor(
                        red: 0.50,
                        green: 0.24,
                        blue: 0.16,
                        alpha: 1
                    )
                )

            for index in 0..<9 {

                let radius =
                    0.075
                    - CGFloat(index) * 0.003

                let geometry =
                    SCNSphere(
                        radius:
                            max(
                                0.045,
                                radius
                            )
                    )

                geometry.segmentCount = 7
                geometry.firstMaterial =
                    material

                let segment =
                    SCNNode(
                        geometry: geometry
                    )

                let x =
                    Float(
                        -0.28
                        + Double(index) * 0.075
                    )

                let wave =
                    Float(
                        sin(
                            Double(index) * 0.85
                        )
                    ) * 0.035

                segment.position =
                    SCNVector3(
                        x,
                        wave,
                        0
                    )

                container.addChildNode(
                    segment
                )
            }

            return container
        }

        // MARK: - Spider

        private func createSpiderNode(
            invader:
                ColonyInvader
        ) -> SCNNode {

            let container = SCNNode()

            container.name =
                "invader-spider-\(invader.id.uuidString)"

            let abdomen =
                SCNSphere(radius: 0.15)

            abdomen.segmentCount = 9

            abdomen.firstMaterial =
                invaderMaterial(
                    diffuse: UIColor(
                        red: 0.08,
                        green: 0.08,
                        blue: 0.10,
                        alpha: 1
                    )
                )

            let abdomenNode =
                SCNNode(
                    geometry: abdomen
                )

            abdomenNode.scale =
                SCNVector3(
                    1.20,
                    0.80,
                    1.0
                )

            abdomenNode.position =
                SCNVector3(
                    -0.08,
                    0.01,
                    0
                )

            container.addChildNode(
                abdomenNode
            )

            let cephalothorax =
                SCNSphere(radius: 0.105)

            cephalothorax.segmentCount = 8

            cephalothorax.firstMaterial =
                invaderMaterial(
                    diffuse: UIColor(
                        red: 0.13,
                        green: 0.13,
                        blue: 0.15,
                        alpha: 1
                    )
                )

            let thoraxNode =
                SCNNode(
                    geometry:
                        cephalothorax
                )

            thoraxNode.position =
                SCNVector3(
                    0.12,
                    0.01,
                    0
                )

            container.addChildNode(
                thoraxNode
            )

            addSpiderLegs(
                to: container
            )

            return container
        }

        private func addSpiderLegs(
            to container: SCNNode
        ) {

            let material =
                invaderMaterial(
                    diffuse: UIColor(
                        red: 0.12,
                        green: 0.12,
                        blue: 0.14,
                        alpha: 1
                    )
                )

            let angles: [Float] = [
                0.45,
                0.75,
                1.05,
                1.35,
                -0.45,
                -0.75,
                -1.05,
                -1.35
            ]

            for angle in angles {

                let upper =
                    SCNCylinder(
                        radius: 0.014,
                        height: 0.20
                    )

                upper.radialSegmentCount = 5
                upper.firstMaterial =
                    material

                let upperNode =
                    SCNNode(
                        geometry: upper
                    )

                upperNode.position =
                    SCNVector3(
                        0,
                        -0.02,
                        0
                    )

                upperNode.eulerAngles.z =
                    angle

                container.addChildNode(
                    upperNode
                )

                let lower =
                    SCNCylinder(
                        radius: 0.011,
                        height: 0.20
                    )

                lower.radialSegmentCount = 5
                lower.firstMaterial =
                    material

                let lowerNode =
                    SCNNode(
                        geometry: lower
                    )

                lowerNode.position =
                    SCNVector3(
                        0,
                        -0.13,
                        0.10
                    )

                lowerNode.eulerAngles.z =
                    angle * 0.65

                container.addChildNode(
                    lowerNode
                )
            }
        }

        // MARK: - Invader Details

        private func addInvaderLegs(
            to container: SCNNode,
            count: Int,
            length: CGFloat,
            thickness: CGFloat
        ) {

            let material =
                invaderMaterial(
                    diffuse: UIColor(
                        white: 0.12,
                        alpha: 1
                    )
                )

            let sideCount =
                max(
                    1,
                    count / 2
                )

            for index in 0..<sideCount {

                let offset =
                    Float(
                        index
                    )
                    - Float(
                        sideCount - 1
                    ) / 2

                for side in [-1.0, 1.0] {

                    let geometry =
                        SCNCylinder(
                            radius: thickness,
                            height: length
                        )

                    geometry.radialSegmentCount = 5
                    geometry.firstMaterial =
                        material

                    let node =
                        SCNNode(
                            geometry: geometry
                        )

                    node.position =
                        SCNVector3(
                            Float(offset) * 0.10,
                            -0.04,
                            Float(side) * 0.12
                        )

                    node.eulerAngles.x =
                        Float(side) * 0.85

                    container.addChildNode(
                        node
                    )
                }
            }
        }

        private func addAntennae(
            to container: SCNNode,
            length: CGFloat
        ) {

            let material =
                invaderMaterial(
                    diffuse: UIColor(
                        white: 0.10,
                        alpha: 1
                    )
                )

            for side in [-1.0, 1.0] {

                let geometry =
                    SCNCylinder(
                        radius: 0.008,
                        height: length
                    )

                geometry.radialSegmentCount = 5
                geometry.firstMaterial =
                    material

                let antenna =
                    SCNNode(
                        geometry: geometry
                    )

                antenna.position =
                    SCNVector3(
                        0.33,
                        0.07,
                        Float(side) * 0.055
                    )

                antenna.eulerAngles.z =
                    Float.pi / 2.7

                antenna.eulerAngles.x =
                    Float(side) * 0.20

                container.addChildNode(
                    antenna
                )
            }
        }

        private func updateInvaderHealthIndicator(
            node: SCNNode,
            health: Double
        ) {

            if let indicator =
                node.childNode(
                    withName:
                        "invaderHealth",
                    recursively: true
                ) {

                indicator.geometry?
                    .firstMaterial?
                    .emission.intensity =
                    CGFloat(
                        0.20
                        + health * 0.80
                    )
            }
        }

        private func invaderMaterial(
            diffuse: UIColor
        ) -> SCNMaterial {

            let material =
                SCNMaterial()

            material.diffuse.contents =
                diffuse

            material.specular.contents =
                UIColor.white

            material.shininess =
                18

            return material
        }

        // MARK: - Food Nodes

        private func updateFoodNodes(
            simulation:
                AntColonySimulation
        ) {

            var activeIDs =
                Set<UUID>()

            activeIDs.reserveCapacity(
                simulation.foodSources.count
            )

            for source in
                simulation.foodSources
            where
                !source.depleted
                && source.amount > 0 {

                activeIDs.insert(
                    source.id
                )

                let node: SCNNode

                if let existing =
                    foodNodes[source.id] {

                    node = existing

                } else {

                    node =
                        createFoodNode(
                            source: source
                        )

                    foodNodes[source.id] =
                        node

                    foodNode.addChildNode(
                        node
                    )
                }

                node.position =
                    worldPosition(
                        x: source.x,
                        y: source.y,
                        depth: -0.42,
                        simulation: simulation
                    )

                let scale =
                    max(
                        0.15,
                        min(
                            1.8,
                            CGFloat(
                                source.amount / 20.0
                            )
                        )
                    )

                node.scale =
                    SCNVector3(
                        Float(scale),
                        Float(scale),
                        Float(scale)
                    )
            }

            let staleIDs =
                foodNodes.keys.filter {
                    !activeIDs.contains($0)
                }

            for id in staleIDs {

                foodNodes[id]?
                    .removeFromParentNode()

                foodNodes.removeValue(
                    forKey: id
                )
            }
        }

        private func createFoodNode(
            source:
                FoodSource
        ) -> SCNNode {

            let geometry =
                SCNSphere(
                    radius: 0.16
                )

            geometry.segmentCount = 8

            let material =
                SCNMaterial()

            let color =
                foodColor(
                    type: source.type
                )

            material.diffuse.contents =
                color

            material.emission.contents =
                color

            material.emission.intensity =
                0.35

            geometry.firstMaterial =
                material

            let node =
                SCNNode(
                    geometry: geometry
                )

            node.name =
                "food-\(source.id.uuidString)"

            return node
        }

        // MARK: - Static Scene

        private func rebuildStaticScene(
            simulation:
                AntColonySimulation,
            soilTransparency:
                Double,
            showGround:
                Bool
        ) {

            terrainNode.childNodes
                .forEach {
                    $0.removeFromParentNode()
                }

            colonyNode.childNodes
                .forEach {
                    $0.removeFromParentNode()
                }

            if showGround {

                createCutawayGround(
                    simulation: simulation,
                    transparency:
                        soilTransparency
                )
            }

            createColonyStructure(
                simulation: simulation
            )
        }

        private func createCutawayGround(
            simulation:
                AntColonySimulation,
            transparency:
                Double
        ) {

            let width =
                CGFloat(simulation.width)
                * cellSize

            let height =
                CGFloat(simulation.height)
                * cellSize

            let geometry =
                SCNBox(
                    width: width,
                    height: groundThickness,
                    length: height,
                    chamferRadius: 0
                )

            let material =
                SCNMaterial()

            material.diffuse.contents =
                UIColor(
                    red: 0.34,
                    green: 0.23,
                    blue: 0.13,
                    alpha:
                        CGFloat(
                            transparency
                        )
                )

            material.transparency =
                CGFloat(transparency)

            material.blendMode =
                .alpha

            material.isDoubleSided =
                true

            material.writesToDepthBuffer =
                false

            geometry.firstMaterial =
                material

            let soil =
                SCNNode(
                    geometry: geometry
                )

            terrainNode.addChildNode(
                soil
            )

            createSurfaceGrid(
                simulation: simulation
            )
        }

        private func createSurfaceGrid(
            simulation:
                AntColonySimulation
        ) {

            let width =
                CGFloat(simulation.width)
                * cellSize

            let height =
                CGFloat(simulation.height)
                * cellSize

            let material =
                SCNMaterial()

            material.diffuse.contents =
                UIColor(
                    white: 0.45,
                    alpha: 0.20
                )

            material.transparency =
                0.20

            let railHeight:
                CGFloat = 0.025

            let xGeometry =
                SCNBox(
                    width: width,
                    height: railHeight,
                    length: 0.025,
                    chamferRadius: 0
                )

            xGeometry.firstMaterial =
                material

            let xRail =
                SCNNode(
                    geometry: xGeometry
                )

            xRail.position =
                SCNVector3(
                    0,
                    0.30,
                    Float(-height / 2)
                )

            terrainNode.addChildNode(
                xRail
            )

            let xRail2 =
                xRail.clone()

            xRail2.position.z =
                Float(height / 2)

            terrainNode.addChildNode(
                xRail2
            )

            let zGeometry =
                SCNBox(
                    width: 0.025,
                    height: railHeight,
                    length: height,
                    chamferRadius: 0
                )

            zGeometry.firstMaterial =
                material

            let zRail =
                SCNNode(
                    geometry: zGeometry
                )

            zRail.position =
                SCNVector3(
                    Float(-width / 2),
                    0.30,
                    0
                )

            terrainNode.addChildNode(
                zRail
            )

            let zRail2 =
                zRail.clone()

            zRail2.position.x =
                Float(width / 2)

            terrainNode.addChildNode(
                zRail2
            )
        }

        // MARK: - Colony Structure

        private func createColonyStructure(
            simulation:
                AntColonySimulation
        ) {

            for y in 0..<simulation.height {

                for x in 0..<simulation.width {

                    let index =
                        y * simulation.width + x

                    let cell =
                        simulation.cells[index]

                    switch cell.terrain {

                    case .tunnel:

                        createTunnel(
                            x: x,
                            y: y,
                            simulation: simulation
                        )

                    case .storage:

                        createStorage(
                            x: x,
                            y: y,
                            cell: cell,
                            simulation: simulation
                        )

                    case .nest:

                        createNestCell(
                            x: x,
                            y: y,
                            simulation: simulation
                        )

                    case .obstacle:

                        createObstacle(
                            x: x,
                            y: y,
                            simulation: simulation
                        )

                    default:
                        break
                    }
                }
            }
        }

        private func createTunnel(
            x: Int,
            y: Int,
            simulation:
                AntColonySimulation
        ) {

            let geometry =
                SCNBox(
                    width: cellSize * 0.90,
                    height: tunnelHeight,
                    length: cellSize * 0.90,
                    chamferRadius: 0.05
                )

            let material =
                SCNMaterial()

            material.diffuse.contents =
                UIColor(
                    red: 0.20,
                    green: 0.12,
                    blue: 0.07,
                    alpha: 0.95
                )

            geometry.firstMaterial =
                material

            let node =
                SCNNode(
                    geometry: geometry
                )

            node.position =
                worldPosition(
                    x: x,
                    y: y,
                    depth: -0.72,
                    simulation: simulation
                )

            colonyNode.addChildNode(
                node
            )
        }

        private func createStorage(
            x: Int,
            y: Int,
            cell:
                ColonyCell,
            simulation:
                AntColonySimulation
        ) {

            let geometry =
                SCNBox(
                    width: cellSize * 0.92,
                    height: chamberHeight,
                    length: cellSize * 0.92,
                    chamferRadius: 0.10
                )

            let material =
                SCNMaterial()

            material.diffuse.contents =
                UIColor(
                    red: 0.26,
                    green: 0.16,
                    blue: 0.08,
                    alpha: 0.95
                )

            geometry.firstMaterial =
                material

            let node =
                SCNNode(
                    geometry: geometry
                )

            node.position =
                worldPosition(
                    x: x,
                    y: y,
                    depth: -0.86,
                    simulation: simulation
                )

            colonyNode.addChildNode(
                node
            )

            if cell.storedFood > 0 {

                let fillGeometry =
                    SCNSphere(
                        radius:
                            cellSize * 0.25
                    )

                fillGeometry.segmentCount =
                    8

                let fillMaterial =
                    SCNMaterial()

                fillMaterial.diffuse.contents =
                    UIColor(
                        red: 0.92,
                        green: 0.70,
                        blue: 0.18,
                        alpha: 0.95
                    )

                fillMaterial.emission.contents =
                    UIColor(
                        red: 0.30,
                        green: 0.18,
                        blue: 0.02,
                        alpha: 1
                    )

                fillMaterial.emission.intensity =
                    0.20

                fillGeometry.firstMaterial =
                    fillMaterial

                let fill =
                    SCNNode(
                        geometry: fillGeometry
                    )

                let fillScale =
                    max(
                        0.20,
                        min(
                            1.0,
                            CGFloat(
                                cell.storedFood
                                / max(
                                    1,
                                    simulation.storageCapacity
                                )
                            )
                        )
                    )

                fill.scale =
                    SCNVector3(
                        Float(fillScale),
                        Float(fillScale),
                        Float(fillScale)
                    )

                fill.position =
                    worldPosition(
                        x: x,
                        y: y,
                        depth: -0.47,
                        simulation: simulation
                    )

                colonyNode.addChildNode(
                    fill
                )
            }
        }

        private func createNestCell(
            x: Int,
            y: Int,
            simulation:
                AntColonySimulation
        ) {

            let geometry =
                SCNCylinder(
                    radius:
                        cellSize * 0.38,
                    height: 0.18
                )

            geometry.radialSegmentCount =
                8

            let material =
                SCNMaterial()

            material.diffuse.contents =
                UIColor(
                    red: 0.28,
                    green: 0.18,
                    blue: 0.10,
                    alpha: 0.90
                )

            geometry.firstMaterial =
                material

            let node =
                SCNNode(
                    geometry: geometry
                )

            node.position =
                worldPosition(
                    x: x,
                    y: y,
                    depth: -0.53,
                    simulation: simulation
                )

            colonyNode.addChildNode(
                node
            )
        }

        private func createObstacle(
            x: Int,
            y: Int,
            simulation:
                AntColonySimulation
        ) {

            let geometry =
                SCNBox(
                    width: cellSize * 0.80,
                    height: 0.55,
                    length: cellSize * 0.80,
                    chamferRadius: 0.05
                )

            let material =
                SCNMaterial()

            material.diffuse.contents =
                UIColor(
                    white: 0.25,
                    alpha: 0.9
                )

            geometry.firstMaterial =
                material

            let node =
                SCNNode(
                    geometry: geometry
                )

            node.position =
                worldPosition(
                    x: x,
                    y: y,
                    depth: -0.30,
                    simulation: simulation
                )

            terrainNode.addChildNode(
                node
            )
        }

        // MARK: - Pheromones

        private func rebuildPheromoneNodes(
            simulation:
                AntColonySimulation,
            enabled:
                Bool
        ) {

            pheromoneNode.childNodes
                .forEach {
                    $0.removeFromParentNode()
                }

            guard enabled
            else {
                return
            }

            for y in 0..<simulation.height {

                for x in 0..<simulation.width {

                    let index =
                        y * simulation.width + x

                    let cell =
                        simulation.cells[index]

                    let strength =
                        max(
                            cell.foodPheromone,
                            cell.nestPheromone
                        )

                    guard strength > 0.05
                    else {
                        continue
                    }

                    let geometry =
                        SCNSphere(
                            radius: 0.035
                        )

                    geometry.segmentCount =
                        5

                    let material =
                        SCNMaterial()

                    material.diffuse.contents =
                        UIColor(
                            red: 0.20,
                            green: 0.70,
                            blue: 1.0,
                            alpha: 0.25
                        )

                    material.transparency =
                        CGFloat(
                            min(
                                0.65,
                                strength
                            )
                        )

                    geometry.firstMaterial =
                        material

                    let node =
                        SCNNode(
                            geometry: geometry
                        )

                    node.position =
                        worldPosition(
                            x: x,
                            y: y,
                            depth: -0.40,
                            simulation: simulation
                        )

                    pheromoneNode
                        .addChildNode(
                            node
                        )
                }
            }
        }

        private func updatePheromoneValues(
            simulation:
                AntColonySimulation
        ) {

            let expectedCount =
                countActivePheromoneCells(
                    simulation: simulation
                )

            if expectedCount
                != pheromoneNode
                    .childNodes.count {

                rebuildPheromoneNodes(
                    simulation: simulation,
                    enabled: true
                )

                return
            }

            var index = 0

            for y in 0..<simulation.height {

                for x in 0..<simulation.width {

                    let cellIndex =
                        y * simulation.width + x

                    let cell =
                        simulation.cells[cellIndex]

                    let strength =
                        max(
                            cell.foodPheromone,
                            cell.nestPheromone
                        )

                    guard strength > 0.05
                    else {
                        continue
                    }

                    guard index <
                        pheromoneNode
                            .childNodes
                            .count
                    else {
                        return
                    }

                    let node =
                        pheromoneNode
                            .childNodes[index]

                    node.geometry?
                        .firstMaterial?
                        .transparency =
                        CGFloat(
                            min(
                                0.65,
                                strength
                            )
                        )

                    index += 1
                }
            }
        }

        // MARK: - Camera

        private func resetCamera() {

            guard let cameraNode
            else {
                return
            }

            cameraNode.position =
                SCNVector3(
                    0,
                    18,
                    25
                )

            cameraNode.look(
                at:
                    SCNVector3(
                        0,
                        -0.5,
                        0
                    )
            )
        }

        // MARK: - Coordinates

        private func worldPosition(
            x: Int,
            y: Int,
            depth: CGFloat,
            simulation:
                AntColonySimulation
        ) -> SCNVector3 {

            let centerX =
                CGFloat(
                    simulation.width - 1
                ) / 2.0

            let centerY =
                CGFloat(
                    simulation.height - 1
                ) / 2.0

            let sceneX =
                (
                    CGFloat(x)
                    - centerX
                ) * cellSize

            let sceneZ =
                (
                    CGFloat(y)
                    - centerY
                ) * cellSize

            return SCNVector3(
                Float(sceneX),
                Float(depth),
                Float(sceneZ)
            )
        }

        private func worldPosition(
            x: Double,
            y: Double,
            depth: CGFloat,
            simulation:
                AntColonySimulation
        ) -> SCNVector3 {

            let centerX =
                Double(
                    simulation.width - 1
                ) / 2.0

            let centerY =
                Double(
                    simulation.height - 1
                ) / 2.0

            let sceneX =
                (
                    x - centerX
                )
                * Double(cellSize)

            let sceneZ =
                (
                    y - centerY
                )
                * Double(cellSize)

            return SCNVector3(
                Float(sceneX),
                Float(depth),
                Float(sceneZ)
            )
        }

        // MARK: - Helpers

        private func countObstacles(
            simulation:
                AntColonySimulation
        ) -> Int {

            simulation.cells.reduce(
                into: 0
            ) { result, cell in

                if cell.terrain ==
                    .obstacle {

                    result += 1
                }
            }
        }

        private func countActivePheromoneCells(
            simulation:
                AntColonySimulation
        ) -> Int {

            simulation.cells.reduce(
                into: 0
            ) { result, cell in

                if max(
                    cell.foodPheromone,
                    cell.nestPheromone
                ) > 0.05 {

                    result += 1
                }
            }
        }

        private func distanceSquared(
            _ a: SCNVector3,
            _ b: SCNVector3
        ) -> Float {

            let dx =
                a.x - b.x

            let dy =
                a.y - b.y

            let dz =
                a.z - b.z

            return
                dx * dx
                + dy * dy
                + dz * dz
        }

        // MARK: - Materials

        private func antMaterial()
            -> SCNMaterial {

            let material =
                SCNMaterial()

            material.diffuse.contents =
                UIColor(
                    white: 0.72,
                    alpha: 1
                )

            material.specular.contents =
                UIColor.white

            material.shininess =
                30

            return material
        }

        private func stateMaterial()
            -> SCNMaterial {

            let material =
                SCNMaterial()

            material.diffuse.contents =
                UIColor.white

            material.emission.contents =
                UIColor.white

            material.emission.intensity =
                0.8

            return material
        }

        private func stateEmission(
            state:
                AntState
        ) -> UIColor {

            switch state {

            case .searching:

                return UIColor(
                    red: 1,
                    green: 0.55,
                    blue: 0.10,
                    alpha: 1
                )

            case .returning:

                return UIColor(
                    red: 0.10,
                    green: 0.80,
                    blue: 1,
                    alpha: 1
                )

            case .building:

                return UIColor(
                    red: 1,
                    green: 0.75,
                    blue: 0.20,
                    alpha: 1
                )

            case .resting:

                return UIColor(
                    white: 0.35,
                    alpha: 1
                )

            case .exploring:

                return UIColor(
                    red: 0.50,
                    green: 1,
                    blue: 0.25,
                    alpha: 1
                )

            default:

                return UIColor.white
            }
        }

        private func foodColor(
            type:
                FoodType
        ) -> UIColor {

            switch type {

            case .seed:

                return UIColor(
                    red: 0.85,
                    green: 0.70,
                    blue: 0.25,
                    alpha: 1
                )

            case .fruit:

                return UIColor(
                    red: 0.95,
                    green: 0.20,
                    blue: 0.25,
                    alpha: 1
                )

            case .insect:

                return UIColor(
                    red: 0.55,
                    green: 0.80,
                    blue: 0.35,
                    alpha: 1
                )

            case .nectar:

                return UIColor(
                    red: 0.35,
                    green: 0.70,
                    blue: 1.0,
                    alpha: 1
                )

            default:

                return UIColor.white
            }
        }

        // MARK: - Stop

        func stop() {

            simulation = nil

            antNodes.values
                .forEach {
                    $0.removeFromParentNode()
                }

            foodNodes.values
                .forEach {
                    $0.removeFromParentNode()
                }

            invaderNodes.values
                .forEach {
                    $0.removeFromParentNode()
                }

            antNodes.removeAll()
            foodNodes.removeAll()
            invaderNodes.removeAll()

            lastAntPositions.removeAll()
            lastInvaderPositions.removeAll()
        }
    }
}
