//
//  File.swift
//  Virtual Ants
//
//  Created by David Nishimoto on 9/17/26.
//

import Foundation
import SwiftUI
import Combine

// MARK: - Simulation

@MainActor
final class AntColonySimulation: ObservableObject {
    private let movementEnergyCost = 0.45
    
    let spawnChance = 0.50
    
    private var defenseStepCounter = 0
    
    @Published var invaders: [ColonyInvader] = []

    @Published var defenseCells: [DefenseCell] = []

    @Published var defensiveAlarm: Double = 0.0

    @Published var defendersActive: Int = 0

    @Published var invadersDefeated: Int = 0

    @Published var invaderBreaches: Int = 0

    @Published var defenseGeneration: Int = 0

    // MARK: Defensive Configuration

    private var defenseInitialized = false

    private var nextInvaderGeneration: Int = 5

    private let maximumInvaders = 12

    private let defenseActivationThreshold = 0.18

    private let defenseCriticalThreshold = 0.72


    // MARK: Published State

    @Published var cells: [ColonyCell]

    @Published var ants: [Ant] = []

    @Published var foodSources: [FoodSource] = []

    @Published var generation: Int = 0

    // Energy immediately available to the colony.
    @Published var colonyEnergy: Double = 0.0

    // Physical food stored inside the colony.
    @Published var storedFood: Double = 0.0

    // Maximum physical food the current nest can store.
    @Published var storageCapacity: Double = 100.0

    @Published var foodCollected: Double = 0.0

    @Published var foodCreated: Double = 0.0

    @Published var births: Int = 0

    @Published var deaths: Int = 0

    @Published var tunnelsBuilt: Int = 0

    @Published var storageChambersBuilt: Int = 0

    @Published var colonyAlive: Bool = true

    @Published var paused: Bool = false

    // MARK: World

    let width: Int
    let height: Int

    let nestCenterX: Int
    let nestCenterY: Int

    let initialPopulation = 250
    let maximumPopulation = 1000

    // Maximum number of food patches outside the colony.
    private let maximumFoodSources = 25

    private var nextFoodGeneration = 1

    // MARK: Construction

    private var constructionCandidates: Set<Int> = []

    // MARK: Initialization

    init(
        width: Int = 100,
        height: Int = 65
    ) {

        self.width = width
        self.height = height

        self.nestCenterX = width / 2
        self.nestCenterY = height / 2

        self.cells = Array(
            repeating: ColonyCell(),
            count: width * height
        )

        // Initial energy reserve.
        self.colonyEnergy =
            Double(initialPopulation) * 8.0

        buildInitialWorld()

        createInitialColony()

        createInitialFood()
    }

    // MARK: Initial World

    private func buildInitialWorld() {

        for y in 0..<height {

            for x in 0..<width {

                let dx =
                    Double(x - nestCenterX)

                let dy =
                    Double(y - nestCenterY)

                let distance =
                    sqrt(
                        dx * dx +
                        dy * dy
                    )

                let index =
                    indexFor(x, y)

                // Initial nest.
                if distance <= 6 {

                    cells[index].terrain =
                        .nest

                    cells[index].nestStrength =
                        1.0
                }

                // Initial tunnel axes.
                else if abs(dx) < 1.5 ||
                        abs(dy) < 1.5 {

                    cells[index].terrain =
                        .tunnel

                    cells[index].construction =
                        1.0

                    cells[index].nestStrength =
                        0.8
                }
            }
        }

        // Environmental obstacles.
        var obstacles = 0

        while obstacles < 85 {

            let x =
                Int.random(
                    in: 3..<(width - 3)
                )

            let y =
                Int.random(
                    in: 3..<(height - 3)
                )

            let dx =
                Double(x - nestCenterX)

            let dy =
                Double(y - nestCenterY)

            let distance =
                sqrt(
                    dx * dx +
                    dy * dy
                )

            guard distance > 13 else {
                continue
            }

            let index =
                indexFor(x, y)

            guard cells[index].terrain == .empty else {
                continue
            }

            cells[index].terrain =
                .obstacle

            obstacles += 1
        }

        updateStorageCapacity()
    }

    // MARK: Initial Colony

    private func createInitialColony() {

        ants.reserveCapacity(
            maximumPopulation
        )

        for _ in 0..<initialPopulation {

            let angle =
                Double.random(
                    in: 0...(Double.pi * 2)
                )

            let radius =
                sqrt(
                    Double.random(in: 0...1)
                ) * 8.0

            let x =
                Double(nestCenterX) +
                cos(angle) * radius

            let y =
                Double(nestCenterY) +
                sin(angle) * radius

            ants.append(
                Ant(
                    x:
                        clamp(
                            x,
                            1,
                            Double(width - 2)
                        ),
                    y:
                        clamp(
                            y,
                            1,
                            Double(height - 2)
                        ),
                    state: .resting,
                    energy:
                        Double.random(
                            in: 75...100
                        ),
                    pheromoneSensitivity:
                        Double.random(
                            in: 0.75...1.25
                        ),
                    explorationBias:
                        Double.random(
                            in: 0.75...1.25
                        )
                )
            )
        }
    }

    // MARK: Initial Food

    private func createInitialFood() {

        for _ in 0..<12 {
            createFoodSource()
        }

        nextFoodGeneration =
            generation +
            Int.random(in: 12...25)
    }

    // MARK: Food Generation

    private func generateFoodIfNeeded() {

        guard generation >= nextFoodGeneration else {
            return
        }

        guard foodSources.count <
                maximumFoodSources
        else {
            nextFoodGeneration =
                generation +
                Int.random(in: 8...18)

            return
        }

        let populationDemand =
            max(
                1,
                min(
                    5,
                    Int(
                        ceil(
                            Double(
                                max(
                                    ants.count,
                                    1
                                )
                            ) /
                            Double(
                                initialPopulation
                            )
                        )
                    )
                )
            )

        let lower =
            max(
                1,
                populationDemand - 1
            )

        let upper =
            min(
                5,
                populationDemand + 1
            )

        let sourceCount =
            Int.random(
                in: lower...upper
            )

        for _ in 0..<sourceCount {

            guard foodSources.count <
                    maximumFoodSources
            else {
                break
            }

            createFoodSource()
        }

        let intervalLow =
            max(
                7,
                20 - ants.count / 80
            )

        let intervalHigh =
            max(
                intervalLow + 3,
                32 - ants.count / 60
            )

        nextFoodGeneration =
            generation +
            Int.random(
                in: intervalLow...intervalHigh
            )
    }

    private func createFoodSource() {

        guard let location =
                randomFoodLocation()
        else {
            return
        }

        let type =
            chooseFoodType()

        let populationFactor =
            min(
                2.0,
                max(
                    0.75,
                    Double(
                        max(
                            ants.count,
                            1
                        )
                    ) /
                    Double(
                        initialPopulation
                    )
                )
            )

        let amount: Double

        switch type {

        case .seed:

            amount =
                Double.random(
                    in: 30...85
                ) *
                populationFactor

        case .fruit:

            amount =
                Double.random(
                    in: 15...50
                ) *
                populationFactor

        case .insect:

            amount =
                Double.random(
                    in: 5...22
                ) *
                populationFactor

        case .nectar:

            amount =
                Double.random(
                    in: 20...65
                ) *
                populationFactor
        }

        foodSources.append(
            FoodSource(
                x: location.x,
                y: location.y,
                type: type,
                amount: amount
            )
        )

        let index =
            indexFor(
                location.x,
                location.y
            )

        cells[index].terrain =
            .food

        foodCreated += amount
    }

    private func chooseFoodType()
        -> FoodType {

        let energyPerAnt =
            colonyEnergy /
            Double(
                max(
                    ants.count,
                    1
                )
            )

        let roll =
            Double.random(
                in: 0..<1
            )

        if energyPerAnt < 4 {

            if roll < 0.40 {
                return .insect
            }

            if roll < 0.70 {
                return .fruit
            }

            if roll < 0.88 {
                return .nectar
            }

            return .seed
        }

        if energyPerAnt < 8 {

            if roll < 0.30 {
                return .insect
            }

            if roll < 0.55 {
                return .fruit
            }

            if roll < 0.80 {
                return .nectar
            }

            return .seed
        }

        return FoodType.allCases.randomElement()!
    }

    private func randomFoodLocation()
        -> (x: Int, y: Int)? {

        for _ in 0..<100 {

            let x =
                Int.random(
                    in: 4..<(width - 4)
                )

            let y =
                Int.random(
                    in: 4..<(height - 4)
                )

            let dx =
                Double(
                    x - nestCenterX
                )

            let dy =
                Double(
                    y - nestCenterY
                )

            let distance =
                sqrt(
                    dx * dx +
                    dy * dy
                )

            guard distance > 12 else {
                continue
            }

            let index =
                indexFor(x, y)

            guard cells[index].terrain ==
                    .empty
            else {
                continue
            }

            return (x, y)
        }

        return nil
    }

    // MARK: Simulation

    func step() {

        guard colonyAlive else {
            return
        }

        generation += 1
        
        // Existing simulation work.
        defenseStepCounter += 1

        if defenseStepCounter >= 10 {
            defenseStepCounter = 0
            stepDefenseSystem()
        }

        generateFoodIfNeeded()

        updateLocalPopulationDensity()

        moveAnts()

        performColonyConstruction()

        evaporatePheromones()

        consumeColonyEnergy()

        convertStoredFoodToEnergy()

        populationDynamics()

        removeDepletedFood()

        updateStorageCapacity()

        evaluateColony()
    }

    // MARK: Density

    private func updateLocalPopulationDensity() {

        for i in cells.indices {
            cells[i].antCount = 0
        }

        for ant in ants {

            let x =
                Int(
                    ant.x.rounded()
                )

            let y =
                Int(
                    ant.y.rounded()
                )

            guard x >= 0,
                  x < width,
                  y >= 0,
                  y < height
            else {
                continue
            }

            cells[
                indexFor(x, y)
            ].antCount += 1
        }
    }

    // MARK: Ant Movement

    private func moveAnts() {

        for i in ants.indices {

            ants[i].age += 1

            let density =
                localCrowding(
                    atX: ants[i].x,
                    y: ants[i].y
                )

            let populationPressure =
                min(
                    1.0,
                    Double(
                        ants.count
                    ) /
                    Double(
                        maximumPopulation
                    )
                )

            ants[i].energy -=
                movementCost(
                    state:
                        ants[i].state,
                    density:
                        density,
                    populationPressure:
                        populationPressure
                )

            if ants[i].energy <= 0 {
                continue
            }

            // Returning workers take food to storage.
            if ants[i].hasFood {

                ants[i].state =
                    .returning

                moveReturningAnt(
                    index: i
                )

                continue
            }

            // Construction workers emerge naturally
            // when the colony requires expansion.
            if shouldConstruct(
                ant: ants[i]
            ) {

                ants[i].state =
                    .building

                moveConstructionAnt(
                    index: i
                )

                continue
            }

            if ants[i].state == .resting {

                if isInsideNest(
                    x: ants[i].x,
                    y: ants[i].y
                ) {

                    ants[i].energy =
                        min(
                            100,
                            ants[i].energy + 0.10
                        )
                }

                if Double.random(
                    in: 0...1
                ) < 0.025 {

                    ants[i].state =
                        .searching
                }

                continue
            }

            if let foodIndex =
                foodAt(
                    x: ants[i].x,
                    y: ants[i].y,
                    radius: 1.5
                ) {

                collectFood(
                    antIndex: i,
                    foodIndex: foodIndex
                )

                continue
            }

            moveSearchingAnt(
                index: i
            )
        }

        removeDeadAnts()
    }

    // MARK: Searching

    private func moveSearchingAnt(
        index: Int
    ) {

        let ant =
            ants[index]

        let populationPressure =
            min(
                1.0,
                Double(
                    ants.count
                ) /
                Double(
                    maximumPopulation
                )
            )

        let exploration =
            max(
                0.08,
                ant.explorationBias *
                (
                    1.0 -
                    populationPressure * 0.65
                )
            )

        let trailWeight =
            ant.pheromoneSensitivity *
            (
                0.8 +
                populationPressure * 1.6
            )

        var vx = 0.0
        var vy = 0.0

        let foodVector =
            foodDirection(
                for: ant
            )

        vx +=
            foodVector.x * 3.0

        vy +=
            foodVector.y * 3.0

        let pheromone =
            pheromoneDirection(
                for: ant
            )

        vx +=
            pheromone.x *
            trailWeight

        vy +=
            pheromone.y *
            trailWeight

        if let memoryX =
            ant.rememberedFoodX,
           let memoryY =
            ant.rememberedFoodY {

            let dx =
                memoryX - ant.x

            let dy =
                memoryY - ant.y

            let distance =
                sqrt(
                    dx * dx +
                    dy * dy
                )

            if distance > 0.5 &&
               distance < 35 {

                vx +=
                    dx /
                    distance *
                    0.35

                vy +=
                    dy /
                    distance *
                    0.35
            }
        }

        let nestDistance =
            distanceFromNest(
                x: ant.x,
                y: ant.y
            )

        if nestDistance < 9 {

            let dx =
                ant.x -
                Double(
                    nestCenterX
                )

            let dy =
                ant.y -
                Double(
                    nestCenterY
                )

            let distance =
                max(
                    0.001,
                    sqrt(
                        dx * dx +
                        dy * dy
                    )
                )

            vx +=
                dx /
                distance *
                0.6

            vy +=
                dy /
                distance *
                0.6
        }

        let crowd =
            crowdingDirection(
                for: ant
            )

        vx +=
            crowd.x *
            (
                0.5 +
                populationPressure * 1.5
            )

        vy +=
            crowd.y *
            (
                0.5 +
                populationPressure * 1.5
            )

        vx +=
            Double.random(
                in: -1...1
            ) *
            exploration

        vy +=
            Double.random(
                in: -1...1
            ) *
            exploration

        let direction =
            normalized(
                x: vx,
                y: vy
            )

        let speed =
            max(
                0.18,
                0.48 -
                localCrowding(
                    atX: ant.x,
                    y: ant.y
                ) * 0.025
            )

        _ = moveAntSafely(
            index: index,
            directionX:
                direction.x,
            directionY:
                direction.y,
            speed:
                speed
        )

        if Double.random(
            in: 0...1
        ) < 0.003 {

            ants[index].state =
                .exploring
        }
        else {

            ants[index].state =
                .searching
        }
    }

    // MARK: Returning

    private func moveReturningAnt(
        index: Int
    ) {

        let ant =
            ants[index]

        let dx =
            Double(
                nestCenterX
            ) -
            ant.x

        let dy =
            Double(
                nestCenterY
            ) -
            ant.y

        let distance =
            max(
                0.001,
                sqrt(
                    dx * dx +
                    dy * dy
                )
            )

        let trail =
            nestDirection(
                for: ant
            )

        let direction =
            normalized(
                x:
                    dx /
                    distance *
                    0.75 +
                    trail.x *
                    0.25,
                y:
                    dy /
                    distance *
                    0.75 +
                    trail.y *
                    0.25
            )

        _ = moveAntSafely(
            index: index,
            directionX:
                direction.x,
            directionY:
                direction.y,
            speed: 0.60
        )

        depositReturningPheromone(
            ant: ants[index]
        )

        if isInsideNest(
            x: ants[index].x,
            y: ants[index].y
        ) {

            deliverFood(
                antIndex: index
            )
        }
    }

    // MARK: Construction

    private func shouldConstruct(
        ant: Ant
    ) -> Bool {

        guard !ant.hasFood else {
            return false
        }

        let requiredPopulationArea =
            Double(
                ants.count
            ) * 0.20

        let currentNestArea =
            Double(
                nestCellCount
            )

        // More workers create more construction pressure.
        if currentNestArea <
            requiredPopulationArea {

            return Double.random(
                in: 0...1
            ) < 0.035
        }

        // Storage shortage creates additional construction.
        if storedFood >
            storageCapacity * 0.75 {

            return Double.random(
                in: 0...1
            ) < 0.025
        }

        // Normal maintenance.
        return Double.random(
            in: 0...1
        ) < 0.004
    }

    private func moveConstructionAnt(
        index: Int
    ) {

        guard let target =
                nearestConstructionSite(
                    from: ants[index]
                )
        else {

            ants[index].state =
                .searching

            return
        }

        let dx =
            target.x -
            ants[index].x

        let dy =
            target.y -
            ants[index].y

        let distance =
            max(
                0.001,
                sqrt(
                    dx * dx +
                    dy * dy
                )
            )

        let direction =
            normalized(
                x:
                    dx / distance,
                y:
                    dy / distance
            )

        _ = moveAntSafely(
            index: index,
            directionX:
                direction.x,
            directionY:
                direction.y,
            speed: 0.30
        )

        if distance < 1.8 {

            buildAt(
                x: target.x,
                y: target.y
            )

            ants[index].state =
                .resting
        }
    }

    private func nearestConstructionSite(
        from ant: Ant
    ) -> (x: Double, y: Double)? {
        
        var best: (x: Double, y: Double)?
        var bestDistance = Double.infinity
        
        let searchRadius = 18
        
        let centerX = Int(ant.x.rounded())
        let centerY = Int(ant.y.rounded())
        
        let minX = max(1, centerX - searchRadius)
        let maxX = min(width - 2, centerX + searchRadius)
        let minY = max(1, centerY - searchRadius)
        let maxY = min(height - 2, centerY + searchRadius)
        
        // Avoid constructing an invalid closed range if the ant is
        // somehow outside or very near an invalid map boundary.
        guard minX <= maxX, minY <= maxY else {
            return nil
        }
        
        for y in minY...maxY {
            for x in minX...maxX {
                let index = indexFor(x, y)
                
                guard cells[index].terrain == .empty else {
                    continue
                }
                
                let builtNeighborCount = numberOfBuiltNeighbors(
                    x: x,
                    y: y
                )
                
                guard builtNeighborCount >= 2 else {
                    continue
                }
                
                let dx = Double(x) - ant.x
                let dy = Double(y) - ant.y
                let distanceSquared = dx * dx + dy * dy
                
                // No need for sqrt: comparing squared distances yields
                // exactly the same nearest-cell result.
                if distanceSquared < bestDistance {
                    bestDistance = distanceSquared
                    
                    best = (
                        x: Double(x),
                        y: Double(y)
                    )
                }
            }
        }
        
        return best
    }

    private func buildAt(
        x: Double,
        y: Double
    ) {

        let ix =
            Int(
                x.rounded()
            )

        let iy =
            Int(
                y.rounded()
            )

        guard ix >= 1,
              ix < width - 1,
              iy >= 1,
              iy < height - 1
        else {
            return
        }

        let index =
            indexFor(ix, iy)

        guard cells[index].terrain ==
                .empty
        else {
            return
        }

        let neighbors =
            numberOfBuiltNeighbors(
                x: ix,
                y: iy
            )

        guard neighbors >= 2 else {
            return
        }

        // Decide whether this newly constructed room
        // becomes a tunnel or storage chamber.
        let storageDemand =
            storedFood /
            max(
                storageCapacity,
                1
            )

        let storageProbability =
            storageDemand > 0.70
            ? 0.65
            : 0.20

        if Double.random(
            in: 0...1
        ) < storageProbability {

            cells[index].terrain =
                .storage

            cells[index].nestStrength =
                0.75

            cells[index].construction =
                1.0

            storageChambersBuilt += 1

        } else {

            cells[index].terrain =
                .tunnel

            cells[index].nestStrength =
                0.70

            cells[index].construction =
                1.0

            tunnelsBuilt += 1
        }

        updateStorageCapacity()
    }

    private func performColonyConstruction() {

        // Mature construction pressure creates a small
        // number of new construction candidates.
        constructionCandidates.removeAll()

        let pressure =
            min(
                1.0,
                Double(
                    ants.count
                ) /
                Double(
                    maximumPopulation
                )
            )

        let desiredCandidates =
            max(
                2,
                Int(
                    3 +
                    pressure * 8
                )
            )

        for _ in 0..<desiredCandidates {

            let x =
                Int.random(
                    in: 2..<(width - 2)
                )

            let y =
                Int.random(
                    in: 2..<(height - 2)
                )

            let index =
                indexFor(x, y)

            guard cells[index].terrain ==
                    .empty
            else {
                continue
            }

            if numberOfBuiltNeighbors(
                x: x,
                y: y
            ) >= 2 {

                constructionCandidates
                    .insert(index)
            }
        }
    }

    private func numberOfBuiltNeighbors(
        x: Int,
        y: Int
    ) -> Int {

        var count = 0

        for dy in -1...1 {

            for dx in -1...1 {

                if dx == 0 &&
                   dy == 0 {
                    continue
                }

                let nx =
                    x + dx

                let ny =
                    y + dy

                guard nx >= 0,
                      nx < width,
                      ny >= 0,
                      ny < height
                else {
                    continue
                }

                let terrain =
                    cells[
                        indexFor(
                            nx,
                            ny
                        )
                    ].terrain

                if terrain == .nest ||
                   terrain == .tunnel ||
                   terrain == .storage {

                    count += 1
                }
            }
        }

        return count
    }

    // MARK: Food Delivery / Storage

    private func deliverFood(
        antIndex: Int
    ) {

        guard ants[antIndex].hasFood else {

            ants[antIndex].state =
                .resting

            return
        }

        let amount =
            ants[antIndex].carriedFood

        let type =
            ants[antIndex].carriedFoodType
            ?? .seed

        // Food physically enters colony storage.
        let availableCapacity =
            max(
                0,
                storageCapacity -
                storedFood
            )

        let amountStored =
            min(
                amount,
                availableCapacity
            )

        storedFood +=
            amountStored

        foodCollected +=
            amountStored

        // Excess food that cannot fit in storage
        // is immediately converted into energy.
        let overflow =
            max(
                0,
                amount -
                amountStored
            )

        colonyEnergy +=
            overflow *
            type.energyPerUnit *
            0.75

        ants[antIndex].carriedFood = 0

        ants[antIndex].carriedFoodType =
            nil

        ants[antIndex].energy =
            min(
                100,
                ants[antIndex].energy + 25
            )

        ants[antIndex].state =
            .resting

        let x =
            Int(
                ants[antIndex].x.rounded()
            )

        let y =
            Int(
                ants[antIndex].y.rounded()
            )

        if x >= 0,
           x < width,
           y >= 0,
           y < height {

            let index =
                indexFor(x, y)

            cells[index].nestPheromone =
                min(
                    25,
                    cells[index].nestPheromone +
                    2
                )
        }

        updateStorageCapacity()
    }

    // MARK: Stored Food → Energy

    private func convertStoredFoodToEnergy() {

        guard storedFood > 0 else {
            return
        }

        // Stored food is gradually metabolized.
        // This provides the colony's usable energy.
        let consumptionRate =
            min(
                storedFood,
                Double(
                    ants.count
                ) * 0.018
            )

        storedFood -=
            consumptionRate

        // Average stored food is treated as
        // moderate-energy colony nutrition.
        colonyEnergy +=
            consumptionRate * 7.0

        colonyEnergy =
            min(
                colonyEnergy,
                100_000
            )
    }

    // MARK: Reproduction

    private func populationDynamics() {

        guard generation % 20 == 0 else {
            return
        }

        guard ants.count <
                maximumPopulation
        else {
            return
        }

        // -------------------------------------------------
        // REPRODUCTION IS NOW DIRECTLY CONTROLLED BY
        // PHYSICAL FOOD STORAGE.
        // -------------------------------------------------

        let minimumFoodForBreeding =
            20.0

        guard storedFood >=
                minimumFoodForBreeding
        else {
            return
        }

        let foodRatio =
            min(
                1.0,
                storedFood /
                max(
                    storageCapacity,
                    1
                )
            )

        let energyPerAnt =
            colonyEnergy /
            Double(
                max(
                    ants.count,
                    1
                )
            )

        guard energyPerAnt > 5.0 else {
            return
        }

        // Reproduction probability increases
        // as food storage becomes healthier.
        let reproductionRate =
            min(
                0.035,
                0.004 +
                foodRatio * 0.030
            )

        let requestedBirths =
            max(
                1,
                Int(
                    Double(
                        ants.count
                    ) *
                    reproductionRate
                )
            )

        let availableSlots =
            maximumPopulation -
            ants.count

        let birthCount =
            min(
                requestedBirths,
                availableSlots
            )

        // Each new worker consumes stored food.
        let foodCostPerBirth =
            12.0

        let totalFoodCost =
            Double(
                birthCount
            ) *
            foodCostPerBirth

        guard storedFood >=
                totalFoodCost
        else {
            return
        }

        // Stored food is explicitly consumed
        // to produce new workers.
        storedFood -=
            totalFoodCost

        for _ in 0..<birthCount {

            let angle =
                Double.random(
                    in: 0...(Double.pi * 2)
                )

            let radius =
                Double.random(
                    in: 1...5
                )

            ants.append(
                Ant(
                    x:
                        Double(
                            nestCenterX
                        ) +
                        cos(angle) *
                        radius,

                    y:
                        Double(
                            nestCenterY
                        ) +
                        sin(angle) *
                        radius,

                    state:
                        .resting,

                    energy:
                        Double.random(
                            in: 75...95
                        ),

                    pheromoneSensitivity:
                        Double.random(
                            in: 0.8...1.2
                        ),

                    explorationBias:
                        Double.random(
                            in: 0.8...1.2
                        )
                )
            )
        }

        births +=
            birthCount
    }

    // MARK: Mortality

    private func removeDeadAnts() {

        let before =
            ants.count

        ants.removeAll {
            $0.energy <= 0 ||
            $0.age > 6000
        }

        deaths +=
            before -
            ants.count
    }

    // MARK: Energy Consumption

    private func movementCost(
        state: AntState,
        density: Double,
        populationPressure: Double
    ) -> Double {

        let base: Double

        switch state {

        case .searching:
            base = 0.32

        case .exploring:
            base = 0.42

        case .returning:
            base = 0.28

        case .resting:
            base = 0.05

        case .building:
            base = 0.36

        case .defending:
            base = 0.48
        }

        return base *
            (
                1.0 +
                density * 0.10 +
                populationPressure * 0.15
            )
    }

    private func consumeColonyEnergy() {

        let population =
            Double(
                ants.count
            )

        let active =
            Double(
                ants.filter {
                    $0.state != .resting
                }.count
            )

        let metabolicCost =
            population * 0.055

        let activityCost =
            active * 0.025

        colonyEnergy -=
            metabolicCost +
            activityCost

        colonyEnergy =
            max(
                0,
                colonyEnergy
            )
    }

    // MARK: Food Detection

    private func foodAt(
        x: Double,
        y: Double,
        radius: Double
    ) -> Int? {

        var closest:
            Int?

        var closestDistance =
            Double.infinity

        for index in
            foodSources.indices {

            let source =
                foodSources[index]

            let dx =
                Double(source.x) -
                x

            let dy =
                Double(source.y) -
                y

            let distance =
                sqrt(
                    dx * dx +
                    dy * dy
                )

            if distance <= radius &&
               distance <
                closestDistance &&
               !source.depleted {

                closest =
                    index

                closestDistance =
                    distance
            }
        }

        return closest
    }

    private func collectFood(
        antIndex: Int,
        foodIndex: Int
    ) {

        guard foodSources.indices
                .contains(foodIndex)
        else {
            return
        }

        let available =
            foodSources[
                foodIndex
            ].amount

        guard available > 0 else {
            return
        }

        let type =
            foodSources[
                foodIndex
            ].type

        let amount =
            min(
                4.0 /
                type.collectionDifficulty,
                available
            )

        foodSources[
            foodIndex
        ].amount -= amount

        ants[antIndex].carriedFood +=
            amount

        ants[antIndex].carriedFoodType =
            type

        ants[antIndex].state =
            .returning

        ants[antIndex].rememberedFoodX =
            Double(
                foodSources[
                    foodIndex
                ].x
            )

        ants[antIndex].rememberedFoodY =
            Double(
                foodSources[
                    foodIndex
                ].y
            )

        let x =
            foodSources[
                foodIndex
            ].x

        let y =
            foodSources[
                foodIndex
            ].y

        let cellIndex =
            indexFor(x, y)

        cells[cellIndex]
            .foodPheromone =
            min(
                25,
                cells[cellIndex]
                    .foodPheromone +
                3.0 *
                type.attraction
            )
    }

    // MARK: Pheromones

    private func depositReturningPheromone(
        ant: Ant
    ) {

        let x =
            Int(
                ant.x.rounded()
            )

        let y =
            Int(
                ant.y.rounded()
            )

        guard x >= 0,
              x < width,
              y >= 0,
              y < height
        else {
            return
        }

        let index =
            indexFor(x, y)

        cells[index].foodPheromone =
            min(
                25,
                cells[index]
                    .foodPheromone +
                0.18
            )

        cells[index].nestPheromone =
            min(
                25,
                cells[index]
                    .nestPheromone +
                0.10
            )
    }

    private func evaporatePheromones() {

        for i in cells.indices {

            cells[i].foodPheromone *=
                0.992

            cells[i].nestPheromone *=
                0.995
        }
    }

    // MARK: Storage Capacity

    private func updateStorageCapacity() {

        let storageCells =
            cells.filter {
                $0.terrain == .storage
            }.count

        // Base nest storage.
        let base =
            100.0

        // Each storage chamber adds real capacity.
        let chamberCapacity =
            Double(
                storageCells
            ) * 45.0

        storageCapacity =
            base +
            chamberCapacity

        storedFood =
            min(
                storedFood,
                storageCapacity
            )
    }

    // MARK: Food Cleanup

    private func removeDepletedFood() {

        for source in foodSources {

            guard source.depleted else {
                continue
            }

            let index =
                indexFor(
                    source.x,
                    source.y
                )

            if cells[index].terrain ==
                .food {

                cells[index].terrain =
                    .empty
            }
        }

        foodSources.removeAll {
            $0.depleted
        }
    }

    // MARK: Local Behavior

    private func localCrowding(
        atX x: Double,
        y: Double
    ) -> Double {

        let cx =
            Int(
                x.rounded()
            )

        let cy =
            Int(
                y.rounded()
            )

        var count = 0

        for dy in -2...2 {

            for dx in -2...2 {

                let nx =
                    cx + dx

                let ny =
                    cy + dy

                guard nx >= 0,
                      nx < width,
                      ny >= 0,
                      ny < height
                else {
                    continue
                }

                count +=
                    cells[
                        indexFor(
                            nx,
                            ny
                        )
                    ].antCount
            }
        }

        return min(
            3,
            Double(count) /
            12
        )
    }

    private func crowdingDirection(
        for ant: Ant
    ) -> (x: Double, y: Double) {

        let cx =
            Int(
                ant.x.rounded()
            )

        let cy =
            Int(
                ant.y.rounded()
            )

        var vx = 0.0
        var vy = 0.0

        for dy in -2...2 {

            for dx in -2...2 {

                if dx == 0 &&
                   dy == 0 {
                    continue
                }

                let nx =
                    cx + dx

                let ny =
                    cy + dy

                guard nx >= 0,
                      nx < width,
                      ny >= 0,
                      ny < height
                else {
                    continue
                }

                let count =
                    cells[
                        indexFor(
                            nx,
                            ny
                        )
                    ].antCount

                guard count > 0 else {
                    continue
                }

                let distance =
                    sqrt(
                        Double(
                            dx * dx +
                            dy * dy
                        )
                    )

                guard distance > 0 else {
                    continue
                }

                vx -=
                    Double(dx) /
                    distance *
                    Double(count)

                vy -=
                    Double(dy) /
                    distance *
                    Double(count)
            }
        }

        return normalized(
            x: vx,
            y: vy
        )
    }

    // MARK: Food Direction

    private func foodDirection(
        for ant: Ant
    ) -> (x: Double, y: Double) {

        var vx = 0.0
        var vy = 0.0

        let sensoryRadius =
            22.0

        for source in foodSources {

            let dx =
                Double(source.x) -
                ant.x

            let dy =
                Double(source.y) -
                ant.y

            let distance =
                sqrt(
                    dx * dx +
                    dy * dy
                )

            guard distance > 0.01,
                  distance <
                    sensoryRadius
            else {
                continue
            }

            let amountFactor =
                min(
                    3,
                    max(
                        0.2,
                        source.amount / 20
                    )
                )

            let weight =
                source.type.attraction *
                amountFactor /
                max(
                    distance,
                    1
                )

            vx +=
                dx /
                distance *
                weight

            vy +=
                dy /
                distance *
                weight
        }

        return normalized(
            x: vx,
            y: vy
        )
    }

    // MARK: Pheromone Direction

    private func pheromoneDirection(
        for ant: Ant
    ) -> (x: Double, y: Double) {

        let cx =
            Int(
                ant.x.rounded()
            )

        let cy =
            Int(
                ant.y.rounded()
            )

        var bestValue = 0.0

        var bestX = 0
        var bestY = 0

        for dy in -2...2 {

            for dx in -2...2 {

                if dx == 0 &&
                   dy == 0 {
                    continue
                }

                let x =
                    cx + dx

                let y =
                    cy + dy

                guard x >= 0,
                      x < width,
                      y >= 0,
                      y < height
                else {
                    continue
                }

                let value =
                    cells[
                        indexFor(
                            x,
                            y
                        )
                    ].foodPheromone

                if value >
                    bestValue {

                    bestValue =
                        value

                    bestX =
                        dx

                    bestY =
                        dy
                }
            }
        }

        return normalized(
            x:
                Double(bestX),
            y:
                Double(bestY)
        )
    }

    // MARK: Nest Direction

    private func nestDirection(
        for ant: Ant
    ) -> (x: Double, y: Double) {

        let cx =
            Int(
                ant.x.rounded()
            )

        let cy =
            Int(
                ant.y.rounded()
            )

        var vx = 0.0
        var vy = 0.0

        for dy in -2...2 {

            for dx in -2...2 {

                if dx == 0 &&
                   dy == 0 {
                    continue
                }

                let x =
                    cx + dx

                let y =
                    cy + dy

                guard x >= 0,
                      x < width,
                      y >= 0,
                      y < height
                else {
                    continue
                }

                let value =
                    cells[
                        indexFor(
                            x,
                            y
                        )
                    ].nestPheromone

                let distance =
                    sqrt(
                        Double(
                            dx * dx +
                            dy * dy
                        )
                    )

                guard distance > 0 else {
                    continue
                }

                vx +=
                    Double(dx) /
                    distance *
                    value

                vy +=
                    Double(dy) /
                    distance *
                    value
            }
        }

        return normalized(
            x: vx,
            y: vy
        )
    }

    // MARK: Movement

    private func moveAntSafely(
        index: Int,
        directionX: Double,
        directionY: Double,
        speed: Double
    ) -> Bool {

        let oldX =
            ants[index].x

        let oldY =
            ants[index].y

        let candidateX =
            oldX +
            directionX *
            speed

        let candidateY =
            oldY +
            directionY *
            speed

        if isWalkable(
            x: candidateX,
            y: candidateY
        ) {

            ants[index].x =
                candidateX

            ants[index].y =
                candidateY

            ants[index].directionX =
                directionX

            ants[index].directionY =
                directionY

            return true
        }

        let alternatives:
            [(Double, Double)] = [

                (
                    -directionY,
                    directionX
                ),

                (
                    directionY,
                    -directionX
                ),

                (
                    -directionX,
                    -directionY
                )
            ]

        for alternative in alternatives {

            let nx =
                oldX +
                alternative.0 *
                speed

            let ny =
                oldY +
                alternative.1 *
                speed

            if isWalkable(
                x: nx,
                y: ny
            ) {

                ants[index].x =
                    nx

                ants[index].y =
                    ny

                ants[index].directionX =
                    alternative.0

                ants[index].directionY =
                    alternative.1

                return true
            }
        }

        return false
    }

    private func isWalkable(
        x: Double,
        y: Double
    ) -> Bool {

        guard x >= 1,
              x < Double(width - 1),
              y >= 1,
              y < Double(height - 1)
        else {
            return false
        }

        let ix =
            Int(
                x.rounded()
            )

        let iy =
            Int(
                y.rounded()
            )

        return cells[
            indexFor(
                ix,
                iy
            )
        ].terrain != .obstacle
    }

    // MARK: Colony Status

    private func evaluateColony() {

        if ants.isEmpty {

            colonyAlive =
                false

            return
        }

        let averageEnergy =
            ants.reduce(0.0) {
                $0 + $1.energy
            } /
            Double(
                ants.count
            )

        if colonyEnergy <= 0 &&
           storedFood <= 0 &&
           averageEnergy < 5 {

            colonyAlive =
                false
        }
    }

    // MARK: Manual Food

    func addFoodNow() {

        guard foodSources.count <
                maximumFoodSources
        else {
            return
        }

        let count =
            max(
                1,
                min(
                    5,
                    ants.count / 250
                )
            )

        for _ in 0..<count {
            createFoodSource()
        }
    }

    // MARK: Statistics

    var averageAntEnergy: Double {

        guard !ants.isEmpty else {
            return 0
        }

        return ants.reduce(0.0) {
            $0 + $1.energy
        } /
        Double(
            ants.count
        )
    }

    var totalFoodRemaining: Double {

        foodSources.reduce(0.0) {
            $0 + $1.amount
        }
    }

    var nestCellCount: Int {

        cells.filter {
            $0.terrain == .nest ||
            $0.terrain == .tunnel ||
            $0.terrain == .storage
        }.count
    }

    var storageCellCount: Int {

        cells.filter {
            $0.terrain == .storage
        }.count
    }

    var tunnelCellCount: Int {

        cells.filter {
            $0.terrain == .tunnel
        }.count
    }

    var searchingCount: Int {

        ants.filter {
            $0.state == .searching
        }.count
    }

    var returningCount: Int {

        ants.filter {
            $0.state == .returning
        }.count
    }

    var restingCount: Int {

        ants.filter {
            $0.state == .resting
        }.count
    }

    var exploringCount: Int {

        ants.filter {
            $0.state == .exploring
        }.count
    }

    var buildingCount: Int {

        ants.filter {
            $0.state == .building
        }.count
    }

    var averageFoodPheromone: Double {

        guard !cells.isEmpty else {
            return 0
        }

        return cells.reduce(0.0) {
            $0 + $1.foodPheromone
        } /
        Double(
            cells.count
        )
    }

    var populationBehavior: String {

        let population =
            ants.count

        let active =
            searchingCount +
            returningCount +
            exploringCount

        let activeRatio =
            Double(active) /
            Double(
                max(
                    population,
                    1
                )
            )

        let storageRatio =
            storedFood /
            max(
                storageCapacity,
                1
            )

        if population <
            300 {

            return
                "Establishing colony: workers are expanding the original nest and establishing foraging routes."
        }

        if storageRatio >
            0.80 {

            return
                "Storage-rich colony: accumulated food is supporting reproduction and new storage chambers."
        }

        if buildingCount >
            population / 20 {

            return
                "Construction phase: workers are extending tunnels and building new colony chambers."
        }

        if returningCount >
            searchingCount {

            return
                "Recruitment phase: productive food trails are bringing workers back to the colony."
        }

        if activeRatio >
            0.80 {

            return
                "Exploration phase: most workers are searching for new resources."
        }

        if averageAntEnergy <
            20 {

            return
                "Resource stress: stored food is low and worker energy is falling."
        }

        if population >
            750 {

            return
                "Large colony: traffic density, storage demand, construction and trail competition dominate behavior."
        }

        return
            "Established colony: foraging, food storage, reproduction and construction are interacting."
    }

    var populationProgress: Double {

        Double(
            ants.count
        ) /
        Double(
            maximumPopulation
        )
    }

    // MARK: Helpers

    private func indexFor(
        _ x: Int,
        _ y: Int
    ) -> Int {

        y *
        width +
        x
    }

    private func distanceFromNest(
        x: Double,
        y: Double
    ) -> Double {

        let dx =
            x -
            Double(
                nestCenterX
            )

        let dy =
            y -
            Double(
                nestCenterY
            )

        return sqrt(
            dx * dx +
            dy * dy
        )
    }

    private func isInsideNest(
        x: Double,
        y: Double
    ) -> Bool {

        distanceFromNest(
            x: x,
            y: y
        ) <= 6
    }

    private func normalized(
        x: Double,
        y: Double
    ) -> (x: Double, y: Double) {

        let magnitude =
            sqrt(
                x * x +
                y * y
            )

        guard magnitude >
                0.0001
        else {
            return (0, 0)
        }

        return (
            x / magnitude,
            y / magnitude
        )
    }

    private func clamp(
        _ value: Double,
        _ minimum: Double,
        _ maximum: Double
    ) -> Double {

        min(
            maximum,
            max(
                minimum,
                value
            )
        )
    }
}

@MainActor
extension AntColonySimulation {

    // MARK: Published Defensive State

  
    // MARK: Defensive Initialization

    func initializeDefenseSystem() {

        guard !defenseInitialized else {
            return
        }

        defenseCells = Array(
            repeating: DefenseCell(),
            count: width * height
        )

        defenseInitialized = true
    }

    // MARK: Defensive Step

    private func stepDefenseSystem() {
        initializeDefenseSystem()

        defenseGeneration += 1

        spawnInvadersIfNeeded()

        updateInvaderOccupancy()

        propagateThreat()

        updateDefensiveSignals()

        recruitDefenders()

        moveInvaders()

        resolveDefensiveContacts()

        reinforceColony()

        dissipateDefenseField()

        removeDefeatedInvaders()

        calculateDefensiveAlarm()
    }
    private func resolveDefensiveContacts() {

        guard !ants.isEmpty,
              !invaders.isEmpty,
              !defenseCells.isEmpty
        else {
            return
        }

        let gridWidth = 100
        let gridHeight = defenseCells.count / gridWidth

        guard gridHeight > 0 else {
            return
        }

        let contactDistance = 1.0
        let baseDamage = 1.0

        for antIndex in ants.indices {

            guard ants[antIndex].defending,
                  let targetID = ants[antIndex].defenseTargetID
            else {
                continue
            }

            guard let invaderIndex = invaders.firstIndex(
                where: {
                    $0.id == targetID &&
                    $0.health > 0.0
                }
            )
            else {
                ants[antIndex].defending = false
                ants[antIndex].defenseTargetID = nil
                ants[antIndex].state = .searching
                continue
            }

            let antX = ants[antIndex].x
            let antY = ants[antIndex].y

            let invaderX = invaders[invaderIndex].x
            let invaderY = invaders[invaderIndex].y

            let dx = invaderX - antX
            let dy = invaderY - antY

            let distanceToInvader = sqrt(
                dx * dx + dy * dy
            )

            guard distanceToInvader <= contactDistance else {
                continue
            }

            // Convert the invader's Double position into
            // the canonical defense-grid coordinate.
            let gridX = Int(
                clamp(
                    invaderX.rounded(),
                    0.0,
                    Double(gridWidth - 1)
                )
            )

            let gridY = Int(
                clamp(
                    invaderY.rounded(),
                    0.0,
                    Double(gridHeight - 1)
                )
            )

            let defenseIndex = gridY * gridWidth + gridX

            guard defenseCells.indices.contains(defenseIndex) else {
                continue
            }

            let defenseStrength = max(
                0.0,
                defenseCells[defenseIndex].defenseStrength
            )

            // Defensive cellular-automaton strength
            // increases the damage delivered by the ant.
            let damage =
                baseDamage *
                (1.0 + defenseStrength)

            invaders[invaderIndex].health = max(
                0.0,
                invaders[invaderIndex].health - damage
            )

            // Combat consumes additional ant energy.
            ants[antIndex].energy = max(
                0.0,
                ants[antIndex].energy - 0.5
            )

            // alive is computed from health, so do NOT assign to it.
            if invaders[invaderIndex].health <= 0.0 {

                invaders[invaderIndex].health = 0.0

                invadersDefeated += 1

                ants[antIndex].defending = false
                ants[antIndex].defenseTargetID = nil
                ants[antIndex].state = .searching
            }
        }
    }
    // MARK: Invader Generation

    private func spawnInvadersIfNeeded() {

        guard invaders.count < maximumInvaders else {
            return
        }

        guard Double.random(in: 0...1) < spawnChance else {
              return
          }

        let colonyPressure = min(
            1.0,
            Double(ants.count) /
            Double(maximumPopulation)
        )

        let baseChance = 0.08 + colonyPressure * 0.12

        guard Double.random(in: 0...1) < baseChance else {
            nextInvaderGeneration =
                defenseGeneration +
                Int.random(in: 15...35)

            return
        }

        let count = defenseGeneration < 150
            ? 1
            : Int.random(in: 1...2)

        for _ in 0..<count {

            guard
                let location = randomInvaderEntry()
            else {
                continue
            }

            let type = chooseInvaderType()

            invaders.append(
                ColonyInvader(
                    type: type,
                    x: location.x,
                    y: location.y
                )
            )
        }

        nextInvaderGeneration =
            defenseGeneration +
            Int.random(in: 18...40)
    }

    private func chooseInvaderType() -> InvaderType {

        let roll = Double.random(in: 0..<1)

        if roll < 0.30 {
            return .rivalAnt
        }

        if roll < 0.52 {
            return .cockroach
        }

        if roll < 0.67 {
            return .worm
        }

        if roll < 0.84 {
            return .spider
        }

        return .mouse
    }

    private func randomInvaderEntry()
        -> (x: Double, y: Double)? {

        for _ in 0..<100 {

            let edge = Int.random(in: 0..<4)

            var x = 0
            var y = 0

            switch edge {

            case 0:
                x = Int.random(in: 2..<(width - 2))
                y = 2

            case 1:
                x = Int.random(in: 2..<(width - 2))
                y = height - 3

            case 2:
                x = 2
                y = Int.random(in: 2..<(height - 2))

            default:
                x = width - 3
                y = Int.random(in: 2..<(height - 2))
            }

            let distanceFromNest = sqrt(
                pow(
                    Double(x - nestCenterX),
                    2
                )
                +
                pow(
                    Double(y - nestCenterY),
                    2
                )
            )

            guard distanceFromNest > 18 else {
                continue
            }

            let index = indexFor(x, y)

            guard cells[index].terrain != .obstacle else {
                continue
            }

            return (
                Double(x),
                Double(y)
            )
        }

        return nil
    }

    // MARK: Occupancy

    private func updateInvaderOccupancy() {

        // The defense grid must correspond one-to-one
        // with the existing colony cell grid.
        guard defenseCells.count == cells.count else {
            print(
                "⚠️ Defense grid mismatch:",
                "cells =", cells.count,
                "defenseCells =", defenseCells.count
            )
            return
        }

        // Derive the grid dimensions from the existing colony grid.
        // This avoids depending on gridWidth/gridHeight being in scope here.
        let width = 100
        let height = cells.count / width

        guard width > 0, height > 0 else {
            return
        }

        // Reset current-generation defense occupancy/signals.
        for index in defenseCells.indices {
            defenseCells[index].occupiedByInvader = false
            defenseCells[index].threat = 0.0
            defenseCells[index].alarm = 0.0
            defenseCells[index].defenderSignal = 0.0
        }

        // Map every living invader onto the same
        // spatial grid used by the colony.
        for invader in invaders
        where invader.alive && invader.health > 0.0 {

            let x = Int(
                clamp(
                    invader.x.rounded(),
                    0.0,
                    Double(width - 1)
                )
            )

            let y = Int(
                clamp(
                    invader.y.rounded(),
                    0.0,
                    Double(height - 1)
                )
            )

            let index = y * width + x

            guard cells.indices.contains(index),
                  defenseCells.indices.contains(index)
            else {
                continue
            }

            defenseCells[index].occupiedByInvader = true
            defenseCells[index].threat = 1.0
            defenseCells[index].alarm = 1.0
            defenseCells[index].defenderSignal = 1.0
        }
    }
    // MARK: Threat Propagation

    private func propagateThreat() {

        for index in defenseCells.indices {

            defenseCells[index].threat *= 0.82
        }

        for invader in invaders {

            let radius = threatRadius(
                for: invader.type
            )

            let centerX =
                Int(invader.x.rounded())

            let centerY =
                Int(invader.y.rounded())

            for dy in -radius...radius {

                for dx in -radius...radius {

                    let x = centerX + dx
                    let y = centerY + dy

                    guard
                        x >= 0,
                        x < width,
                        y >= 0,
                        y < height
                    else {
                        continue
                    }

                    let distance = sqrt(
                        Double(
                            dx * dx +
                            dy * dy
                        )
                    )

                    guard distance <=
                            Double(radius)
                    else {
                        continue
                    }

                    let falloff =
                        1.0 -
                        distance /
                        Double(radius + 1)

                    let index =
                        indexFor(x, y)

                    defenseCells[index].threat =
                        min(
                            1.0,
                            defenseCells[index].threat
                            +
                            invader.type.threat
                            *
                            falloff
                            *
                            0.18
                        )
                }
            }
        }
    }

    private func threatRadius(
        for type: InvaderType
    ) -> Int {

        switch type {

        case .rivalAnt:
            return 5

        case .cockroach:
            return 6

        case .mouse:
            return 9

        case .worm:
            return 4

        case .spider:
            return 7
        }
    }

    // MARK: Alarm Signal

    private func updateDefensiveSignals() {

        var totalAlarm = 0.0

        for y in 0..<height {

            for x in 0..<width {

                let index =
                    indexFor(x, y)

                let localThreat =
                    defenseCells[index].threat

                var neighboringAlarm = 0.0

                for dy in -1...1 {

                    for dx in -1...1 {

                        if dx == 0 &&
                            dy == 0 {
                            continue
                        }

                        let nx = x + dx
                        let ny = y + dy

                        guard
                            nx >= 0,
                            nx < width,
                            ny >= 0,
                            ny < height
                        else {
                            continue
                        }

                        neighboringAlarm +=
                            defenseCells[
                                indexFor(nx, ny)
                            ].alarm
                    }
                }

                let alarm = min(
                    1.0,
                    localThreat * 0.65
                    +
                    min(
                        0.35,
                        neighboringAlarm * 0.045
                    )
                )

                defenseCells[index].alarm =
                    alarm

                totalAlarm += alarm
            }
        }

        defensiveAlarm =
            min(
                1.0,
                totalAlarm /
                Double(
                    max(
                        1,
                        cells.count
                    )
                )
                * 8.0
            )
    }
    private func distance(
        x1: Double,
        y1: Double,
        x2: Double,
        y2: Double
    ) -> Double {

        let dx = x2 - x1
        let dy = y2 - y1

        return sqrt(
            dx * dx +
            dy * dy
        )
    }
    private func nearestInvader(
        toX x: Int,
        y: Int
    ) -> ColonyInvader? {

        var nearest: ColonyInvader?
        var nearestDistance = Double.infinity

        for invader in invaders
        where invader.alive && invader.health > 0.0 {

            let d = distance(
                x1: Double(x),
                y1: Double(y),
                x2: invader.x,
                y2: invader.y
            )

            if d < nearestDistance {
                nearestDistance = d
                nearest = invader
            }
        }

        return nearest
    }
    // MARK: Defender Recruitment

    private func recruitDefenders() {

        guard !invaders.isEmpty else {
            return
        }

        let recruitmentRadius = 8.0

        for antIndex in ants.indices {

            // Do not continuously retarget an ant that is already defending.
            if ants[antIndex].defending,
               ants[antIndex].defenseTargetID != nil {
                continue
            }

            let antX = ants[antIndex].x
            let antY = ants[antIndex].y

            var selectedInvader: ColonyInvader?
            var selectedDistance = Double.infinity

            for invader in invaders
            where invader.alive && invader.health > 0.0 {

                let invaderX = Int(
                    invader.x.rounded()
                )

                let invaderY = Int(
                    invader.y.rounded()
                )

                let d = distance(
                    x1: antX,
                    y1: antY,
                    x2: Double(invaderX),
                    y2: Double(invaderY)
                )

                guard d <= recruitmentRadius else {
                    continue
                }

                let invaderIndexX = Int(
                    clamp(
                        invader.x.rounded(),
                        0.0,
                        99.0
                    )
                )

                let invaderIndexY = Int(
                    clamp(
                        invader.y.rounded(),
                        0.0,
                        64.0
                    )
                )

                let defenseIndex =
                    indexFor(
                        invaderIndexX,
                        invaderIndexY
                    )

                guard defenseCells.indices.contains(defenseIndex) else {
                    continue
                }

                let cell = defenseCells[defenseIndex]

                guard cell.threat > 0.0 ||
                      cell.alarm > 0.0 ||
                      cell.defenderSignal > 0.0
                else {
                    continue
                }

                if d < selectedDistance {
                    selectedDistance = d
                    selectedInvader = invader
                }
            }

            guard let target = selectedInvader else {
                continue
            }

            ants[antIndex].defending = true
            ants[antIndex].defenseTargetID = target.id
            ants[antIndex].state = .defending
        }
    }
    private func moveToward(
        ant: inout Ant,
        targetX: Double,
        targetY: Double
    ) {

        let width = 100
        let height = max(cells.count / width, 1)

        let dx = targetX - ant.x
        let dy = targetY - ant.y

        guard abs(dx) > 0.0001 || abs(dy) > 0.0001 else {
            ant.directionX = 0.0
            ant.directionY = 0.0
            return
        }

        if abs(dx) > abs(dy) {

            ant.directionX = dx > 0.0 ? 1.0 : -1.0
            ant.directionY = 0.0

        } else {

            ant.directionX = 0.0
            ant.directionY = dy > 0.0 ? 1.0 : -1.0
        }

        let newX = ant.x + ant.directionX
        let newY = ant.y + ant.directionY

        guard newX >= 0.0,
              newX < Double(width),
              newY >= 0.0,
              newY < Double(height)
        else {
            return
        }

        let gridX = Int(
            clamp(
                newX.rounded(),
                0.0,
                Double(width - 1)
            )
        )

        let gridY = Int(
            clamp(
                newY.rounded(),
                0.0,
                Double(height - 1)
            )
        )

        let index = gridY * width + gridX

        guard cells.indices.contains(index),
              cells[index].terrain != .obstacle
        else {
            return
        }

        ant.x = newX
        ant.y = newY
    }
    private func moveDefendingAnts() {

        guard !ants.isEmpty else {
            return
        }

        for antIndex in ants.indices {

            guard ants[antIndex].defending,
                  let targetID = ants[antIndex].defenseTargetID
            else {
                continue
            }

            guard let invader = invaders.first(
                where: {
                    $0.id == targetID &&
                    $0.alive &&
                    $0.health > 0.0
                }
            )
            else {
                ants[antIndex].defending = false
                ants[antIndex].defenseTargetID = nil
                ants[antIndex].state = .searching
                continue
            }

            let targetX = Int(
                clamp(
                    invader.x.rounded(),
                    0.0,
                    99.0
                )
            )

            let targetY = Int(
                clamp(
                    invader.y.rounded(),
                    0.0,
                    64.0
                )
            )

            let d = distance(
                x1: ants[antIndex].x,
                y1: ants[antIndex].y,
                x2: Double(targetX),
                y2: Double(targetY)
            )

            if d > 1.0 {

                moveToward(
                    ant: &ants[antIndex],
                    targetX: Double(targetX),
                    targetY: Double(targetY)
                )

                ants[antIndex].energy = max(
                    0.0,
                    ants[antIndex].energy - movementEnergyCost
                )

            } else {

                // The ant has reached the invader.
                resolveAntDefensiveContact(
                    antIndex: antIndex,
                    targetID: targetID
                )
            }
        }
    }
    private func moveDefender(
        antIndex: Int
    ) {

        guard
            let target =
                nearestInvader(
                    to: ants[antIndex]
                )
        else {
            return
        }

        let dx =
            target.x -
            ants[antIndex].x

        let dy =
            target.y -
            ants[antIndex].y

        let distance = max(
            0.001,
            sqrt(
                dx * dx +
                dy * dy
            )
        )

        let directionX =
            dx / distance

        let directionY =
            dy / distance

        let speed =
            0.34 +
            min(
                0.22,
                defensiveAlarm * 0.22
            )

        let newX =
            ants[antIndex].x +
            directionX * speed

        let newY =
            ants[antIndex].y +
            directionY * speed

        guard isDefenseWalkable(
            x: newX,
            y: newY
        )
        else {
            return
        }

        ants[antIndex].x = newX
        ants[antIndex].y = newY

        ants[antIndex].directionX =
            directionX

        ants[antIndex].directionY =
            directionY
    }

    private func nearestInvader(
        to ant: Ant
    ) -> ColonyInvader? {

        invaders.min {
            distanceSquared(
                x1: ant.x,
                y1: ant.y,
                x2: $0.x,
                y2: $0.y
            )
            <
            distanceSquared(
                x1: ant.x,
                y1: ant.y,
                x2: $1.x,
                y2: $1.y
            )
        }
    }

    // MARK: Invader Movement

    private func moveInvaders() {

        for index in invaders.indices {

            guard invaders[index].alive else {
                continue
            }

            invaders[index].age += 1

            let dx =
                Double(nestCenterX) -
                invaders[index].x

            let dy =
                Double(nestCenterY) -
                invaders[index].y

            let distance = max(
                0.001,
                sqrt(
                    dx * dx +
                    dy * dy
                )
            )

            let directionX =
                dx / distance

            let directionY =
                dy / distance

            invaders[index].directionX =
                directionX

            invaders[index].directionY =
                directionY

            let speed =
                invaders[index].type.speed

            let newX =
                invaders[index].x +
                directionX * speed

            let newY =
                invaders[index].y +
                directionY * speed

            if isDefenseWalkable(
                x: newX,
                y: newY
            ) {

                invaders[index].x =
                    newX

                invaders[index].y =
                    newY

            } else {

                // Turn when blocked.

                invaders[index].directionX =
                    -directionY

                invaders[index].directionY =
                    directionX
            }
        }
    }

    // MARK: Contact Resolution

    private func resolveAntDefensiveContact(
        antIndex: Int,
        targetID: UUID
    ) {

        guard ants.indices.contains(antIndex) else {
            return
        }

        guard let invaderIndex = invaders.firstIndex(
            where: {
                $0.id == targetID &&
                $0.alive &&
                $0.health > 0.0
            }
        )
        else {
            ants[antIndex].defending = false
            ants[antIndex].defenseTargetID = nil
            ants[antIndex].state = .searching
            return
        }

        let antX = ants[antIndex].x
        let antY = ants[antIndex].y

        let invaderX = Int(
            invaders[invaderIndex].x.rounded()
        )

        let invaderY = Int(
            invaders[invaderIndex].y.rounded()
        )

        let contactDistance = distance(
            x1: antX,
            y1: antY,
            x2: Double(invaderX),
            y2: Double(invaderY)
        )

        guard contactDistance <= 1.0 else {
            return
        }

        // Individual-ant defensive damage.
        let baseDamage = 1.0

        // Nearby defensive CA strength amplifies the response.
        let x = Int(
            clamp(
                invaders[invaderIndex].x.rounded(),
                0.0,
                99.0
            )
        )

        let y = Int(
            clamp(
                invaders[invaderIndex].y.rounded(),
                0.0,
                64.0
            )
        )

        let defenseIndex = indexFor(x, y)

        let defenseStrength =
            defenseCells.indices.contains(defenseIndex)
            ? defenseCells[defenseIndex].defenseStrength
            : 0.0

        let damage =
            baseDamage *
            (1.0 + defenseStrength)

        invaders[invaderIndex].health = max(
            0.0,
            invaders[invaderIndex].health - damage
        )

        ants[antIndex].energy = max(
            0.0,
            ants[antIndex].energy - 0.5
        )

        // Keep attacking while the invader is alive.
        if invaders[invaderIndex].health <= 0.0 {

            invaders[invaderIndex].alive = false

            invadersDefeated += 1

            ants[antIndex].defending = false
            ants[antIndex].defenseTargetID = nil
            ants[antIndex].state = .searching
        }
    }

    // MARK: Reinforcement CA

    private func reinforceColony() {

        for y in 0..<height {

            for x in 0..<width {

                let index =
                    indexFor(x, y)

                let alarm =
                    defenseCells[index].alarm

                let threat =
                    defenseCells[index].threat

                let localBuilt =
                    isColonyCell(
                        x: x,
                        y: y
                    )

                if localBuilt {

                    defenseCells[index]
                        .defenseStrength =
                        min(
                            1.0,
                            defenseCells[index]
                                .defenseStrength
                            +
                            alarm * 0.08
                        )
                }

                defenseCells[index]
                    .defenderSignal =
                    min(
                        1.0,
                        threat * 0.7
                        +
                        alarm * 0.3
                    )

                if alarm >
                        defenseCriticalThreshold &&
                    localBuilt {

                    defenseCells[index]
                        .blocked =
                        min(
                            1.0,
                            defenseCells[index]
                                .blocked
                            +
                            0.05
                        )
                }
            }
        }
    }

    private func reinforceDefenseAt(
        x: Int,
        y: Int,
        amount: Double
    ) {

        guard
            x >= 0,
            x < width,
            y >= 0,
            y < height
        else {
            return
        }

        defenseCells[
            indexFor(x, y)
        ].defenseStrength =
            min(
                1.0,
                defenseCells[
                    indexFor(x, y)
                ].defenseStrength
                +
                amount
            )
    }

    // MARK: Field Dissipation

    private func dissipateDefenseField() {

        for index in defenseCells.indices {

            defenseCells[index].alarm *=
                0.93

            defenseCells[index]
                .defenderSignal *=
                0.95

            defenseCells[index]
                .defenseStrength *=
                0.998

            defenseCells[index].blocked *=
                0.996
        }
    }

    // MARK: Invader Cleanup

    private func removeDefeatedInvaders() {

        let before = invaders.count

        invaders.removeAll {
            !$0.alive
        }

        let defeated =
            before - invaders.count

        if defeated > 0 {
            defensiveAlarm =
                max(
                    0,
                    defensiveAlarm -
                    Double(defeated) * 0.04
                )
        }
    }

    // MARK: Breach Detection

    private func calculateDefensiveAlarm() {

        var breachCount = 0

        for invader in invaders {

            let distance =
                sqrt(
                    pow(
                        invader.x -
                        Double(nestCenterX),
                        2
                    )
                    +
                    pow(
                        invader.y -
                        Double(nestCenterY),
                        2
                    )
                )

            if distance < 8 {
                breachCount += 1
            }
        }

        invaderBreaches =
            breachCount
    }

    // MARK: Helpers

    private func isDefenseWalkable(
        x: Double,
        y: Double
    ) -> Bool {

        guard
            x >= 1,
            x < Double(width - 1),
            y >= 1,
            y < Double(height - 1)
        else {
            return false
        }

        let ix =
            Int(x.rounded())

        let iy =
            Int(y.rounded())

        guard
            ix >= 0,
            ix < width,
            iy >= 0,
            iy < height
        else {
            return false
        }

        let terrain =
            cells[
                indexFor(ix, iy)
            ].terrain

        return terrain != .obstacle
    }

    private func isColonyCell(
        x: Int,
        y: Int
    ) -> Bool {

        guard
            x >= 0,
            x < width,
            y >= 0,
            y < height
        else {
            return false
        }

        let terrain =
            cells[
                indexFor(x, y)
            ].terrain

        return terrain == .nest ||
               terrain == .tunnel ||
               terrain == .storage
    }

    private func distanceSquared(
        x1: Double,
        y1: Double,
        x2: Double,
        y2: Double
    ) -> Double {

        let dx = x1 - x2
        let dy = y1 - y2

        return dx * dx + dy * dy
    }

    // MARK: Manual Invader

    func addInvader(
        type: InvaderType
    ) {

        guard invaders.count <
                maximumInvaders
        else {
            return
        }

        guard
            let location =
                randomInvaderEntry()
        else {
            return
        }

        invaders.append(
            ColonyInvader(
                type: type,
                x: location.x,
                y: location.y
            )
        )
    }

    // MARK: Statistics

    var activeInvaderCount: Int {
        invaders.count
    }

    var criticalDefenseCells: Int {

        defenseCells.filter {
            $0.alarm >
            defenseCriticalThreshold
        }.count
    }

    var averageDefenseStrength: Double {

        guard !defenseCells.isEmpty else {
            return 0
        }

        return defenseCells.reduce(0.0) {
            $0 + $1.defenseStrength
        }
        /
        Double(
            defenseCells.count
        )
    }

    var defenseStatus: String {

        if invaders.isEmpty {
            return "SECURE"
        }

        if defensiveAlarm >
            defenseCriticalThreshold {

            return "CRITICAL"
        }

        if defensiveAlarm >
            defenseActivationThreshold {

            return "DEFENDING"
        }

        return "ALERT"
    }
}

