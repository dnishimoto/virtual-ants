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
                showInvaders: showInvaders,
                cameraResetToken: cameraResetToken
            )
            .frame(
                minHeight: 320
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 18
                )
            )
            ScrollView
            {
                controlPanel
                
                visualizationPanel
                
                statisticsPanel
                
                developmentPanel
            }
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
            // Population + Food Storage on the same row
            HStack {
                HStack(spacing: 6) {
                    Text("Population")
                        .font(.headline)
                    
                    Text("\(simulation.ants.count)")
                        .font(.headline.monospacedDigit())
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: "archivebox.fill")
                        .foregroundColor(.yellow)
                    
                    Text(
                        "\(Int(simulation.storedFood))/\(Int(simulation.storageCapacity))"
                    )
                    .font(.headline.monospacedDigit())
                    .foregroundColor(.secondary)
                }
                .fixedSize()
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
private extension ContentView {
    private func compactThreatValue(
        _ title: String,
        value: Int,
        icon: String
    ) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(invaderThreatColor)

            Text("\(value)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()

            Text(title)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
    var invaderThreatPanel: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: invaderThreatIcon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(invaderThreatColor)

                Text("INVADER THREAT")
                    .font(.system(size: 11, weight: .heavy))
                    .lineLimit(1)

                Spacer(minLength: 3)

                Text(invaderThreatStatus)
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(invaderThreatColor)
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(invaderThreatColor.opacity(0.16))
                    )
            }

            HStack(spacing: 4) {
                compactThreatValue(
                    "INV",
                    value: simulation.invaders.filter(\.alive).count,
                    icon: "exclamationmark.triangle.fill"
                )

                compactThreatValue(
                    "DEF",
                    value: simulation.defendersActive,
                    icon: "shield.fill"
                )

                compactThreatValue(
                    "KO",
                    value: simulation.invadersDefeated,
                    icon: "checkmark.shield.fill"
                )

                compactThreatValue(
                    "BR",
                    value: simulation.invaderBreaches,
                    icon: "arrow.triangle.branch"
                )
            }

            ZStack(alignment: .trailing) {
                ProgressView(
                    value: min(max(simulation.defensiveAlarm, 0), 1)
                )
                .tint(invaderThreatColor)
                .scaleEffect(y: 0.55)
                .frame(height: 6)

                Text("ALARM \(String(format: "%.2f", simulation.defensiveAlarm))")
                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: 230, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(invaderThreatColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(invaderThreatColor.opacity(0.30), lineWidth: 1)
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

        HStack(
            spacing: 10
        ) {

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

            Button {

                simulation.allHandsOnDeck()

            } label: {

                Label(
                    "ALL HANDS",
                    systemImage:
                        "shield.lefthalf.filled"
                )
                .frame(
                    maxWidth: .infinity
                )
            }
            .buttonStyle(
                .borderedProminent
            )
            .tint(.red)
            .disabled(
                !simulation.invaders.contains {
                    $0.alive && $0.health > 0.0
                }
            )
        }
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
            title: "Colony Energy",
            value: String(
                format: "%.1f",
                simulation.colonyEnergy
            )
        )


        statistic(
            title: "Tunnels",
            value:
                "\(simulation.tunnelsBuilt)"
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
