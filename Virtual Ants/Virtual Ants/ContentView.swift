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

    // Unified command API used by AntColony3DView.
    @State private var command =
        AntColony3DCommand(
            action: .resetCamera
        )

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
                    showInvaders: showInvaders,
                    command: command
                )
                .frame(
                    minHeight: 320
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 18
                    )
                )

                ScrollView {
                    controlPanel
                    statisticsPanel
                    visualizationPanel
                    developmentPanel
                }
            }
            .padding()
        }
        .background(
            Color.black.opacity(0.96)
        )
        .preferredColorScheme(.dark)

        // Simulation clock is independent
        // of SceneKit rendering.
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

// MARK: - Vitals

private extension ContentView {

    var vitalsPanel: some View {

        HStack(
            spacing: 10
        ) {

            VStack {

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
                systemImage:
                    "arrow.up.circle.fill",
                tint: .green
            )

            vitalIndicator(
                title: "Deaths",
                value: "\(simulation.deaths)",
                systemImage:
                    "arrow.down.circle.fill",
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
                    )
                    .monospacedDigit()
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

                HStack(spacing: 6) {

                    Text("Population")
                        .font(.headline)

                    Text(
                        "\(simulation.ants.count)"
                    )
                    .font(
                        .headline.monospacedDigit()
                    )
                }

                Spacer()

                HStack(spacing: 4) {

                    Image(
                        systemName:
                            "archivebox.fill"
                    )
                    .foregroundColor(.yellow)

                    Text(
                        "\(Int(simulation.storedFood))/\(Int(simulation.storageCapacity))"
                    )
                    .font(
                        .headline.monospacedDigit()
                    )
                    .foregroundColor(.secondary)
                }
                .fixedSize()
            }

            ProgressView(
                value:
                    simulation.populationProgress
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

    private func compactThreatValue(
        _ title: String,
        value: Int,
        icon: String
    ) -> some View {

        compactThreatValue(
            title,
            value: "\(value)",
            icon: icon
        )
    }

    private func compactThreatValue(
        _ title: String,
        value: String,
        icon: String
    ) -> some View {

        HStack(spacing: 2) {

            Image(
                systemName: icon
            )
            .font(
                .system(
                    size: 8,
                    weight: .bold
                )
            )
            .foregroundStyle(
                invaderThreatColor
            )

            Text(value)
                .font(
                    .system(
                        size: 11,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(title)
                .font(
                    .system(
                        size: 7,
                        weight: .bold
                    )
                )
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(
            maxWidth: .infinity,
            alignment: .center
        )
    }

    var invaderThreatPanel: some View {

        VStack(
            alignment: .leading,
            spacing: 5
        ) {

            HStack(spacing: 6) {

                Image(
                    systemName:
                        invaderThreatIcon
                )
                .font(
                    .system(
                        size: 15,
                        weight: .bold
                    )
                )
                .foregroundStyle(
                    invaderThreatColor
                )

                Text("INVADER THREAT")
                    .font(
                        .system(
                            size: 11,
                            weight: .heavy
                        )
                    )
                    .lineLimit(1)

                Spacer(minLength: 3)

                Text(
                    invaderThreatStatus
                )
                .font(
                    .system(
                        size: 8,
                        weight: .heavy
                    )
                )
                .foregroundStyle(
                    invaderThreatColor
                )
                .lineLimit(1)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(
                            invaderThreatColor
                                .opacity(0.16)
                        )
                )
            }

            HStack(spacing: 4) {

                compactThreatValue(
                    "INV",
                    value:
                        simulation.invaders
                            .filter {
                                $0.alive
                            }
                            .count,
                    icon:
                        "exclamationmark.triangle.fill"
                )

                compactThreatValue(
                    "DEF",
                    value:
                        simulation.defendersActive,
                    icon:
                        "shield.fill"
                )

                compactThreatValue(
                    "TIME",
                    value:
                        longestInvaderTimeAliveLabel,
                    icon:
                        "clock.fill"
                )

                compactThreatValue(
                    "KO",
                    value:
                        simulation.invadersDefeated,
                    icon:
                        "checkmark.shield.fill"
                )

                compactThreatValue(
                    "BR",
                    value:
                        simulation.invaderBreaches,
                    icon:
                        "arrow.triangle.branch"
                )
            }

            ZStack(
                alignment: .trailing
            ) {

                ProgressView(
                    value:
                        min(
                            max(
                                simulation.defensiveAlarm,
                                0
                            ),
                            1
                        )
                )
                .tint(
                    invaderThreatColor
                )
                .scaleEffect(
                    y: 0.55
                )
                .frame(height: 6)

                Text(
                    "ALARM \(String(format: "%.2f", simulation.defensiveAlarm))"
                )
                .font(
                    .system(
                        size: 8,
                        weight: .heavy,
                        design: .monospaced
                    )
                )
                .foregroundStyle(.secondary)
                .padding(.trailing, 2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(
            maxWidth: 230,
            alignment: .leading
        )
        .background(
            RoundedRectangle(
                cornerRadius: 9,
                style: .continuous
            )
            .fill(
                invaderThreatColor
                    .opacity(0.08)
            )
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: 9,
                style: .continuous
            )
            .stroke(
                invaderThreatColor
                    .opacity(0.30),
                lineWidth: 1
            )
        )
    }

    var activeInvaderCount: Int {

        simulation.invaders.filter {
            $0.alive
        }.count
    }

    private var secondsPerInvaderAgeTick:
        Double {

        3.0 * 0.07
    }

    var longestInvaderTimeAlive:
        Double {

        let oldestAge =
            simulation.invaders
                .filter {
                    $0.alive
                }
                .map {
                    $0.age
                }
                .max() ?? 0

        return Double(oldestAge)
            * secondsPerInvaderAgeTick
    }

    var longestInvaderTimeAliveLabel:
        String {

        guard activeInvaderCount > 0 else {
            return "—"
        }

        let seconds =
            Int(longestInvaderTimeAlive)

        if seconds < 60 {
            return "\(seconds)s"
        }

        return
            "\(seconds / 60)m\(seconds % 60)s"
    }

    var invaderThreatLevel:
        Double {

        let active =
            Double(activeInvaderCount)

        let alarm =
            max(
                simulation.defensiveAlarm,
                0.0
            )

        let breaches =
            Double(
                simulation.invaderBreaches
            )

        return min(
            max(
                alarm
                    + min(
                        active * 0.08,
                        0.45
                    )
                    + min(
                        breaches * 0.12,
                        0.35
                    ),
                0.0
            ),
            1.0
        )
    }

    var invaderThreatStatus:
        String {

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

    var invaderThreatColor:
        Color {

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

    var invaderThreatIcon:
        String {

        if activeInvaderCount == 0 &&
            simulation.defensiveAlarm < 0.20 {

            return "checkmark.shield.fill"
        }

        if invaderThreatLevel < 0.40 {
            return "eye.fill"
        }

        if invaderThreatLevel < 0.70 {
            return
                "exclamationmark.triangle.fill"
        }

        return
            "shield.lefthalf.filled.badge.exclamationmark"
    }
}

// MARK: - Controls

private extension ContentView {

    var controlPanel: some View {

        VStack(spacing: 6) {

            HStack(spacing: 6) {

                // Pause / resume
                controlIconButton(
                    systemImage:
                        isPaused
                        ? "play.fill"
                        : "pause.fill",
                    title:
                        isPaused
                        ? "Run simulation"
                        : "Pause simulation",
                    tint: .blue,
                    prominent: true
                ) {
                    isPaused.toggle()
                }

                // Advance one simulation step
                controlIconButton(
                    systemImage:
                        "forward.fill",
                    title:
                        "Advance one simulation step",
                    tint: .secondary
                ) {
                    simulation.step()
                }

                // Add food
                controlIconButton(
                    systemImage:
                        "leaf.fill",
                    title: "Add food",
                    tint: .green,
                    isEnabled:
                        simulation.canAddFoodNow
                ) {
                    simulation.addFoodNow()
                }

                // Reset camera
                controlIconButton(
                    systemImage:
                        "camera.rotate",
                    title:
                        "Reset camera",
                    tint: .secondary
                ) {
                    command =
                        AntColony3DCommand(
                            action:
                                .resetCamera
                        )
                }

                // All hands on deck
                //
                // The command is passed to
                // AntColony3DView, which handles
                // the .allHands action.
                controlIconButton(
                    systemImage:
                        "shield.lefthalf.filled",
                    title:
                        "All hands on deck",
                    tint: .red,
                    prominent: true,
                    isEnabled:
                        simulation.invaders.contains {
                            $0.alive &&
                            $0.health > 0.0
                        }
                ) {
                    command =
                        AntColony3DCommand(
                            action:
                                .allHands
                        )
                }
            }
        }
        .padding(7)
        .background(
            RoundedRectangle(
                cornerRadius: 9,
                style: .continuous
            )
            .fill(
                Color.white.opacity(0.06)
            )
        )
    }

    private func controlIconButton(
        systemImage: String,
        title: String,
        tint: Color,
        prominent: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {

        Button(
            action: action
        ) {

            Image(
                systemName: systemImage
            )
            .font(
                .system(
                    size: 15,
                    weight: .bold
                )
            )
            .frame(
                width: 36,
                height: 30
            )
            .contentShape(
                Rectangle()
            )
        }
        .buttonStyle(.bordered)
        .tint(
            isEnabled
            ? tint
            : .gray
        )
        .disabled(!isEnabled)
        .accessibilityLabel(title)
        .help(title)
    }
}

// MARK: - Visualization Controls

private extension ContentView {

    var visualizationPanel: some View {

        VStack(
            alignment: .leading,
            spacing: 6
        ) {

            HStack {

                Label(
                    "3D VIEW",
                    systemImage:
                        "cube.fill"
                )
                .font(
                    .system(
                        size: 11,
                        weight: .heavy
                    )
                )

                Spacer()

                Text(
                    "\(Int(soilTransparency * 100))% SOIL"
                )
                .font(
                    .system(
                        size: 9,
                        weight: .bold,
                        design: .monospaced
                    )
                )
                .foregroundStyle(
                    .secondary
                )
            }

            HStack(spacing: 6) {

                Text("SOIL")
                    .font(
                        .system(
                            size: 9,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        .secondary
                    )

                Slider(
                    value:
                        $soilTransparency,
                    in:
                        0.05...0.85
                )
                .controlSize(.mini)

                Text(
                    "\(Int(soilTransparency * 100))%"
                )
                .font(
                    .system(
                        size: 9,
                        weight: .bold,
                        design: .monospaced
                    )
                )
                .frame(
                    width: 26,
                    alignment: .trailing
                )
            }

            HStack(spacing: 4) {

                compactVisualizationToggle(
                    "Ground",
                    icon:
                        "square.3.layers.3d",
                    isOn:
                        $showGround
                )

                compactVisualizationToggle(
                    "Ants",
                    icon:
                        "ant.fill",
                    isOn:
                        $showAnts
                )
            }

            HStack(spacing: 4) {

                compactVisualizationToggle(
                    "Invaders",
                    icon:
                        "exclamationmark.triangle.fill",
                    isOn:
                        $showInvaders
                )

                compactVisualizationToggle(
                    "Food",
                    icon:
                        "leaf.fill",
                    isOn:
                        $showFood
                )
            }

            compactVisualizationToggle(
                "Pheromones",
                icon:
                    "wave.3.right",
                isOn:
                    $showPheromones
            )

            Text(
                "Drag orbit • Scroll zoom • Pan move"
            )
            .font(
                .system(
                    size: 8,
                    weight: .medium
                )
            )
            .foregroundStyle(
                .secondary
            )
            .lineLimit(1)
        }
        .padding(8)
        .frame(
            maxWidth: 250,
            alignment: .leading
        )
        .background(
            RoundedRectangle(
                cornerRadius: 9,
                style: .continuous
            )
            .fill(
                Color.white.opacity(0.06)
            )
        )
    }

    private func compactVisualizationToggle(
        _ title: String,
        icon: String,
        isOn: Binding<Bool>
    ) -> some View {

        Toggle(
            isOn: isOn
        ) {

            Label(
                title,
                systemImage: icon
            )
            .font(
                .system(
                    size: 9,
                    weight: .semibold
                )
            )
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
    }
}

// MARK: - Statistics

private extension ContentView {

    var statisticsPanel: some View {

        VStack(spacing: 3) {

            compactStatistic(
                title: "ENERGY",
                value:
                    String(
                        format: "%.1f",
                        simulation.colonyEnergy
                    ),
                icon:
                    "bolt.fill",
                color:
                    .yellow
            )

            compactStatistic(
                title: "TUNNELS",
                value:
                    "\(simulation.tunnelsBuilt)",
                icon:
                    "point.3.connected.trianglepath.dotted",
                color:
                    .brown
            )

            compactStatistic(
                title: "SEARCHING",
                value:
                    "\(simulation.searchingCount)",
                icon:
                    "magnifyingglass",
                color:
                    .cyan
            )

            compactStatistic(
                title: "RETURNING",
                value:
                    "\(simulation.returningCount)",
                icon:
                    "arrow.uturn.backward.circle.fill",
                color:
                    .green
            )

            compactStatistic(
                title: "BUILDING",
                value:
                    "\(simulation.buildingCount)",
                icon:
                    "hammer.fill",
                color:
                    .orange
            )
        }
        .padding(6)
        .background(
            RoundedRectangle(
                cornerRadius: 8,
                style: .continuous
            )
            .fill(
                Color.white.opacity(0.05)
            )
        )
    }

    private func compactStatistic(
        title: String,
        value: String,
        icon: String,
        color: Color
    ) -> some View {

        HStack(spacing: 5) {

            Image(
                systemName: icon
            )
            .font(
                .system(
                    size: 9,
                    weight: .bold
                )
            )
            .foregroundStyle(color)
            .frame(width: 12)

            Text(title)
                .font(
                    .system(
                        size: 9,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    .secondary
                )
                .lineLimit(1)

            Spacer(minLength: 4)

            Text(value)
                .font(
                    .system(
                        size: 12,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .monospacedDigit()
        }
        .frame(
            maxWidth: .infinity,
            minHeight: 19,
            alignment: .leading
        )
        .padding(.horizontal, 5)
        .background(
            RoundedRectangle(
                cornerRadius: 5,
                style: .continuous
            )
            .fill(
                Color.white.opacity(0.035)
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
