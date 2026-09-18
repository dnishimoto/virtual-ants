import SwiftUI
import Foundation
import Combine
import SceneKit
import UIKit

// MARK: - Content View

struct ContentView: View {

    @StateObject private var simulation = AntColonySimulation()

    // Pause belongs to the UI, not the simulation model.
    @State private var isPaused = false

    @State private var soilTransparency: Double = 0.42
    @State private var showGround = true
    @State private var showFood = true
    @State private var showAnts = true
    @State private var showPheromones = false

    @State private var cameraResetToken = UUID()

    private let simulationTimer =
        Timer.publish(
            every: 0.07,
            on: .main,
            in: .common
        )
        .autoconnect()

    var body: some View {

        ScrollView {

            VStack(spacing: 16) {

                header

                populationPanel

                AntColony3DView(
                    simulation: simulation,
                    soilTransparency: soilTransparency,
                    showGround: showGround,
                    showFood: showFood,
                    showAnts: showAnts,
                    showPheromones: showPheromones,
                    cameraResetToken: cameraResetToken
                )
                .frame(
                    minHeight: 620
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 18
                    )
                )

                controlPanel

                visualizationPanel

                statisticsPanel

                developmentPanel
            }
            .padding()
        }
        .background(
            Color.black.opacity(0.96)
        )
        .preferredColorScheme(.dark)

        // The simulation clock is independent of SceneKit rendering.
        //
        // Simulation:
        // approximately 14 updates/sec
        //
        // SceneKit:
        // continuously renders at its configured frame rate.
        .onReceive(simulationTimer) { _ in

            guard !isPaused else {
                return
            }

            guard simulation.colonyAlive else {
                return
            }

            simulation.step()
        }
    }
}

// MARK: - Header

private extension ContentView {

    var header: some View {

        HStack {

            VStack(
                alignment: .leading,
                spacing: 5
            ) {

                Text("ANT COLONY")
                    .font(
                        .system(
                            size: 27,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(.white)

                Text(
                    "Individual-Agent Colony Simulation"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(
                alignment: .trailing,
                spacing: 4
            ) {

                Text("GENERATION")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(
                    "\(simulation.generation)"
                )
                .font(
                    .system(
                        size: 22,
                        weight: .bold
                    )
                )
                .foregroundStyle(.white)

                Text(
                    simulation.colonyAlive
                    ? "ACTIVE"
                    : "COLONY LOST"
                )
                .font(
                    .caption2.weight(.bold)
                )
                .foregroundStyle(
                    simulation.colonyAlive
                    ? .green
                    : .red
                )
            }
        }
    }
}

// MARK: - Population

private extension ContentView {

    var populationPanel: some View {

        VStack(
            alignment: .leading,
            spacing: 9
        ) {

            HStack {

                Text("Population")
                    .font(.headline)

                Spacer()

                Text(
                    "\(simulation.ants.count)"
                )
                .font(
                    .headline.monospacedDigit()
                )
            }

            ProgressView(
                value: simulation.populationProgress
            )

            HStack {

                Text("Initial: 250")

                Spacer()

                Text("Maximum: 1,000")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(
                cornerRadius: 14
            )
            .fill(
                Color.white.opacity(0.06)
            )
        )
    }
}

// MARK: - Controls

private extension ContentView {

    var controlPanel: some View {

        VStack(
            spacing: 12
        ) {

            HStack(
                spacing: 10
            ) {

                Button {

                    isPaused.toggle()

                } label: {

                    Label(
                        isPaused
                        ? "RUN"
                        : "PAUSE",
                        systemImage:
                            isPaused
                            ? "play.fill"
                            : "pause.fill"
                    )
                    .frame(
                        maxWidth: .infinity
                    )
                }
                .buttonStyle(
                    .borderedProminent
                )

                Button {

                    simulation.step()

                } label: {

                    Label(
                        "STEP",
                        systemImage:
                            "forward.fill"
                    )
                    .frame(
                        maxWidth: .infinity
                    )
                }
                .buttonStyle(
                    .bordered
                )

                Button {

                    simulation.addFoodNow()

                } label: {

                    Label(
                        "ADD FOOD",
                        systemImage:
                            "leaf.fill"
                    )
                    .frame(
                        maxWidth: .infinity
                    )
                }
                .buttonStyle(
                    .bordered
                )
            }

            Button {

                cameraResetToken = UUID()

            } label: {

                Label(
                    "RESET CAMERA",
                    systemImage:
                        "camera.rotate"
                )
                .frame(
                    maxWidth: .infinity
                )
            }
            .buttonStyle(
                .bordered
            )
        }
    }
}

// MARK: - Visualization Controls

private extension ContentView {

    var visualizationPanel: some View {

        VStack(
            alignment: .leading,
            spacing: 14
        ) {

            Text("3D VIEW")
                .font(.headline)

            HStack {

                Text("Soil transparency")

                Slider(
                    value:
                        $soilTransparency,
                    in: 0.05...0.85
                )

                Text(
                    "\(Int(soilTransparency * 100))%"
                )
                .font(
                    .caption.monospacedDigit()
                )
                .frame(
                    width: 45
                )
            }

            Toggle(
                "Ground / soil",
                isOn: $showGround
            )

            Toggle(
                "Individual ants",
                isOn: $showAnts
            )

            Toggle(
                "Food sources",
                isOn: $showFood
            )

            Toggle(
                "Pheromone field",
                isOn: $showPheromones
            )

            Text(
                "Camera: drag to orbit • " +
                "scroll to zoom • " +
                "pan to move"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(
                cornerRadius: 14
            )
            .fill(
                Color.white.opacity(0.06)
            )
        )
    }
}

// MARK: - Statistics

private extension ContentView {

    var statisticsPanel: some View {

        LazyVGrid(
            columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ],
            spacing: 10
        ) {

            statistic(
                title: "Stored Food",
                value: String(
                    format: "%.1f",
                    simulation.storedFood
                )
            )

            statistic(
                title: "Food Capacity",
                value: String(
                    format: "%.1f",
                    simulation.storageCapacity
                )
            )

            statistic(
                title: "Colony Energy",
                value: String(
                    format: "%.1f",
                    simulation.colonyEnergy
                )
            )

            statistic(
                title: "Workers",
                value:
                    "\(simulation.ants.count)"
            )

            statistic(
                title: "Tunnels",
                value:
                    "\(simulation.tunnelsBuilt)"
            )

            statistic(
                title: "Storage Chambers",
                value:
                    "\(simulation.storageChambersBuilt)"
            )

            statistic(
                title: "Births",
                value:
                    "\(simulation.births)"
            )

            statistic(
                title: "Deaths",
                value:
                    "\(simulation.deaths)"
            )

            statistic(
                title: "Searching",
                value:
                    "\(simulation.searchingCount)"
            )

            statistic(
                title: "Returning",
                value:
                    "\(simulation.returningCount)"
            )

            statistic(
                title: "Building",
                value:
                    "\(simulation.buildingCount)"
            )

            statistic(
                title: "Food Sources",
                value:
                    "\(simulation.foodSources.count)"
            )
        }
    }

    func statistic(
        title: String,
        value: String
    ) -> some View {

        VStack(
            alignment: .leading,
            spacing: 4
        ) {

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(
                    .system(
                        size: 18,
                        weight: .semibold,
                        design: .rounded
                    )
                )
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .padding()
        .background(
            RoundedRectangle(
                cornerRadius: 12
            )
            .fill(
                Color.white.opacity(0.05)
            )
        )
    }
}

// MARK: - Development

private extension ContentView {

    var developmentPanel: some View {

        VStack(
            alignment: .leading,
            spacing: 8
        ) {

            Text(
                "COLONY DEVELOPMENT"
            )
            .font(.headline)

            Text(
                "Food discovery → collection → return → " +
                "storage → reproduction → more workers → " +
                "construction → larger tunnels and storage capacity."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .padding()
        .background(
            RoundedRectangle(
                cornerRadius: 14
            )
            .fill(
                Color.white.opacity(0.06)
            )
        )
    }
}




// MARK: - Preview

#Preview {
    ContentView()
}
