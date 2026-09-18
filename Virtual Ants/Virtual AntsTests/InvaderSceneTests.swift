//
//  InvaderSceneTests.swift
//  Virtual AntsTests
//

import XCTest
import SwiftUI
import SceneKit
@testable import Virtual_Ants


@MainActor
final class InvaderSceneTests: XCTestCase {

    // MARK: - Simulation Layer

    func testSimulationSpawnsInvadersWithinReasonableSteps() {
        let simulation = AntColonySimulation()

        var spawned = false

        // At the default spawn chance, invaders should appear
        // within well under 400 generations. This is generous
        // (roughly 30x the expected wait) so the test isn't flaky.
        for _ in 0..<400 {
            simulation.step()

            if !simulation.invaders.isEmpty {
                spawned = true
                break
            }
        }

        XCTAssertTrue(
            spawned,
            """
            No invader ever appeared in simulation.invaders after 400 steps \
            — the spawn logic itself is broken, not just the 3D rendering.
            """
        )
    }

    func testSpawnedInvaderHasAValidOnGridPosition() {
        let simulation = AntColonySimulation()

        for _ in 0..<400 {
            simulation.step()

            if let invader = simulation.invaders.first {
                XCTAssertGreaterThanOrEqual(
                    invader.x,
                    0,
                    "An invader must not spawn left of the grid."
                )

                XCTAssertLessThanOrEqual(
                    invader.x,
                    Double(simulation.width),
                    "An invader must not spawn right of the grid."
                )

                XCTAssertGreaterThanOrEqual(
                    invader.y,
                    0,
                    "An invader must not spawn above the grid."
                )

                XCTAssertLessThanOrEqual(
                    invader.y,
                    Double(simulation.height),
                    "An invader must not spawn below the grid."
                )

                XCTAssertGreaterThan(
                    invader.health,
                    0,
                    "A newly spawned invader must have positive health."
                )

                XCTAssertTrue(
                    invader.alive,
                    "A newly spawned invader must be alive."
                )

                return
            }
        }

        XCTFail("No invader spawned to validate position and health against.")
    }

    // MARK: - Rendering Layer

    func testLiveInvaderProducesAVisibleSceneNode() {
        let simulation = AntColonySimulation()

        let invader = ColonyInvader(
            type: .spider,
            x: Double(simulation.nestCenterX + 5),
            y: Double(simulation.nestCenterY)
        )

        simulation.invaders = [invader]

        let coordinator = makeConfiguredCoordinator()

        coordinator.update(
            simulation: simulation,
            soilTransparency: 0.5,
            showGround: true,
            showFood: true,
            showAnts: true,
            showPheromones: false,
            showInvaders: true,
            cameraResetToken: UUID()
        )

        XCTAssertEqual(
            coordinator.debugInvaderNodeCount,
            1,
            """
            Expected exactly one invader node in the scene graph \
            for one live invader.
            """
        )

        XCTAssertTrue(
            coordinator.debugTrackedInvaderIDs.contains(invader.id),
            "The invader's UUID should be tracked in the node map."
        )

        XCTAssertFalse(
            coordinator.debugInvaderSceneNode.isHidden,
            """
            The invader container node must not be hidden when \
            showInvaders is true.
            """
        )

        let node = coordinator.debugInvaderNode(for: invader.id)

        XCTAssertTrue(
            node?.parent === coordinator.debugInvaderSceneNode,
            """
            The invader's node should be parented under the invader \
            container node so it is part of the rendered scene graph.
            """
        )
    }

    func testShowInvadersFalseHidesTheInvaderContainer() {
        let simulation = AntColonySimulation()

        simulation.invaders = [
            ColonyInvader(
                type: .mouse,
                x: Double(simulation.nestCenterX),
                y: Double(simulation.nestCenterY)
            )
        ]

        let coordinator = makeConfiguredCoordinator()

        coordinator.update(
            simulation: simulation,
            soilTransparency: 0.5,
            showGround: true,
            showFood: true,
            showAnts: true,
            showPheromones: false,
            showInvaders: false,
            cameraResetToken: UUID()
        )

        XCTAssertTrue(
            coordinator.debugInvaderSceneNode.isHidden,
            """
            The invader container node should be hidden when \
            showInvaders is false, even though invaders exist \
            in the simulation.
            """
        )

        coordinator.update(
            simulation: simulation,
            soilTransparency: 0.5,
            showGround: true,
            showFood: true,
            showAnts: true,
            showPheromones: false,
            showInvaders: true,
            cameraResetToken: UUID()
        )

        XCTAssertFalse(
            coordinator.debugInvaderSceneNode.isHidden,
            """
            Toggling showInvaders back to true should un-hide \
            the invader container again.
            """
        )
    }

    func testDefeatedInvaderNodeIsRemovedFromTheScene() {
        let simulation = AntColonySimulation()

        var invader = ColonyInvader(
            type: .cockroach,
            x: Double(simulation.nestCenterX),
            y: Double(simulation.nestCenterY)
        )

        simulation.invaders = [invader]

        let coordinator = makeConfiguredCoordinator()

        coordinator.update(
            simulation: simulation,
            soilTransparency: 0.5,
            showGround: true,
            showFood: true,
            showAnts: true,
            showPheromones: false,
            showInvaders: true,
            cameraResetToken: UUID()
        )

        XCTAssertEqual(
            coordinator.debugInvaderNodeCount,
            1,
            "A live invader should create exactly one scene node."
        )

        // Defeat the invader the same way combat resolution does:
        // health reaches zero.
        invader.health = 0
        simulation.invaders = [invader]

        coordinator.update(
            simulation: simulation,
            soilTransparency: 0.5,
            showGround: true,
            showFood: true,
            showAnts: true,
            showPheromones: false,
            showInvaders: true,
            cameraResetToken: UUID()
        )

        XCTAssertEqual(
            coordinator.debugInvaderNodeCount,
            0,
            """
            A defeated invader's node should be removed from \
            the scene once its health reaches zero.
            """
        )
    }

    func testEachInvaderTypeProducesANode() {
        let simulation = AntColonySimulation()

        for type in InvaderType.allCases {
            let invader = ColonyInvader(
                type: type,
                x: Double(simulation.nestCenterX),
                y: Double(simulation.nestCenterY)
            )

            simulation.invaders = [invader]

            let coordinator = makeConfiguredCoordinator()

            coordinator.update(
                simulation: simulation,
                soilTransparency: 0.5,
                showGround: true,
                showFood: true,
                showAnts: true,
                showPheromones: false,
                showInvaders: true,
                cameraResetToken: UUID()
            )

            XCTAssertEqual(
                coordinator.debugInvaderNodeCount,
                1,
                "\(type.displayName) did not produce a scene node."
            )
        }
    }

    // MARK: - Helpers

    private func makeConfiguredCoordinator() -> AntColony3DView.Coordinator {
        let coordinator = AntColony3DView.Coordinator()

        let scene = SCNScene()
        let view = SCNView()

        coordinator.configure(
            scene: scene,
            view: view
        )

        return coordinator
    }
}
