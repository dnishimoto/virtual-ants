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
@State private var showInvaders = true
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


            vitalsPanel

            populationPanel

            invaderThreatPanel

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



// MARK: - Vitals

private extension ContentView {

var vitalsPanel: some View {

    HStack(
        spacing: 10
    ) {
        VStack
        {
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
        vitalIndicator(
            title: "Births",
            value: "\(simulation.births)",
            systemImage: "arrow.up.circle.fill",
            tint: .green
        )

        vitalIndicator(
            title: "Deaths",
            value: "\(simulation.deaths)",
            systemImage: "arrow.down.circle.fill",
            tint: .red
        )
    }
}

func vitalIndicator(
    title: String,
    value: String,
    systemImage: String,
    tint: Color
) -> some View {

    HStack(
        spacing: 10
    ) {

        Image(
            systemName: systemImage
        )
        .font(
            .system(
                size: 22,
                weight: .semibold
            )
        )
        .foregroundStyle(tint)

        VStack(
            alignment: .leading,
            spacing: 2
        ) {

            Text(
                title.uppercased()
            )
            .font(
                .caption2.weight(.bold)
            )
            .foregroundStyle(.secondary)

            Text(value)
                .font(
                    .title3
                        .weight(.bold)
                        .monospacedDigit()
                )
                .foregroundStyle(.white)
        }

        Spacer()
    }
    .padding(.vertical, 10)
    .padding(.horizontal, 12)
    .frame(
        maxWidth: .infinity
    )
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

// MARK: - Invader Threat

private extension ContentView {

var invaderThreatPanel: some View {

    VStack(
        alignment: .leading,
        spacing: 12
    ) {

        HStack {

            HStack(spacing: 8) {

                Image(
                    systemName: invaderThreatIcon
                )
                .font(
                    .system(
                        size: 22,
                        weight: .bold
                    )
                )
                .foregroundStyle(
                    invaderThreatColor
                )

                Text("INVADER THREAT")
                    .font(
                        .headline.weight(.bold)
                    )
            }

            Spacer()

            Text(invaderThreatStatus)
                .font(
                    .caption.weight(.bold)
                )
                .foregroundStyle(
                    invaderThreatColor
                )
                .padding(
                    .horizontal,
                    9
                )
                .padding(
                    .vertical,
                    5
                )
                .background(
                    Capsule()
                        .fill(
                            invaderThreatColor.opacity(0.16)
                        )
                )
        }

        HStack(spacing: 10) {

            threatMetric(
                title: "INVADERS",
                value: "\(simulation.invaders.filter { $0.alive }.count)",
                systemImage: "exclamationmark.triangle.fill"
            )

            threatMetric(
                title: "DEFENDERS",
                value: "\(simulation.defendersActive)",
                systemImage: "shield.fill"
            )

            threatMetric(
                title: "DEFEATED",
                value: "\(simulation.invadersDefeated)",
                systemImage: "checkmark.shield.fill"
            )

            threatMetric(
                title: "BREACHES",
                value: "\(simulation.invaderBreaches)",
                systemImage: "arrow.triangle.branch"
            )
        }

        HStack(spacing: 8) {

            Text("DEFENSIVE ALARM")

            Spacer()

            Text(
                String(
                    format: "%.2f",
                    simulation.defensiveAlarm
                )
            )
            .monospacedDigit()
            .fontWeight(.bold)
        }
        .font(.caption)
        .foregroundStyle(.secondary)

        ProgressView(
            value: min(
                max(
                    simulation.defensiveAlarm,
                    0.0
                ),
                1.0
            )
        )
        .tint(invaderThreatColor)
    }
    .padding()
    .background(
        RoundedRectangle(
            cornerRadius: 14
        )
        .fill(
            invaderThreatColor.opacity(0.08)
        )
    )
    .overlay(
        RoundedRectangle(
            cornerRadius: 14
        )
        .stroke(
            invaderThreatColor.opacity(0.35),
            lineWidth: 1
        )
    )
}

func threatMetric(
    title: String,
    value: String,
    systemImage: String
) -> some View {

    VStack(
        alignment: .leading,
        spacing: 5
    ) {

        Image(
            systemName: systemImage
        )
        .font(
            .caption
        )
        .foregroundStyle(
            invaderThreatColor
        )

        Text(value)
            .font(
                .system(
                    size: 17,
                    weight: .bold,
                    design: .rounded
                )
            )
            .monospacedDigit()

        Text(title)
            .font(
                .system(
                    size: 9,
                    weight: .bold
                )
            )
            .foregroundStyle(.secondary)
    }
    .frame(
        maxWidth: .infinity,
        alignment: .leading
    )
}

var activeInvaderCount: Int {
    simulation.invaders.filter { $0.alive }.count
}

var invaderThreatLevel: Double {

    let active = Double(
        activeInvaderCount
    )

    let alarm = max(
        simulation.defensiveAlarm,
        0.0
    )

    let breaches = Double(
        simulation.invaderBreaches
    )

    return min(
        max(
            alarm
            + min(active * 0.08, 0.45)
            + min(breaches * 0.12, 0.35),
            0.0
        ),
        1.0
    )
}

var invaderThreatStatus: String {

    if activeInvaderCount == 0 &&
        simulation.defensiveAlarm < 0.20 {

        return "SECURE"
    }

    if invaderThreatLevel < 0.40 {
        return "WATCH"
    }

    if invaderThreatLevel < 0.70 {
        return "ALERT"
    }

    return "CRITICAL"
}

var invaderThreatColor: Color {

    if activeInvaderCount == 0 &&
        simulation.defensiveAlarm < 0.20 {

        return .green
    }

    if invaderThreatLevel < 0.40 {
        return .yellow
    }

    if invaderThreatLevel < 0.70 {
        return .orange
    }

    return .red
}

var invaderThreatIcon: String {

    if activeInvaderCount == 0 &&
        simulation.defensiveAlarm < 0.20 {

        return "checkmark.shield.fill"
    }

    if invaderThreatLevel < 0.40 {
        return "eye.fill"
    }

    if invaderThreatLevel < 0.70 {
        return "exclamationmark.triangle.fill"
    }

    return "shield.lefthalf.filled.badge.exclamationmark"
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
            "Invaders",
            isOn: $showInvaders
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

        statistic(
            title: "Active Invaders",
            value:
                "\(activeInvaderCount)"
        )

        statistic(
            title: "Defense Generation",
            value:
                "\(simulation.defenseGeneration)"
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

