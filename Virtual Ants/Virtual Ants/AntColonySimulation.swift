//
//  AntColonySimulation.swift
//  Virtual Ants
//
//  Corrected colony simulation.
//  Works with the existing DataStructures.swift unchanged.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class AntColonySimulation: ObservableObject {

    // MARK: - Energy / Food

    private var storageCellIndices: [Int] = []
    private var storageCellTotal = 0

    private let lowEnergyReturnThreshold = 30.0
    private let recoveredEnergyThreshold = 75.0
    private let maximumFoodPerRecoveryStep = 2.0
    private let personalEnergyPerFoodUnit = 7.0
    private let reproductionInterval = 3
    private let movementEnergyCost = 0.45

    private let normalFoodReturnSpeed = 0.68
    private let emergencyFoodReturnSpeed = 0.82
    private let normalNestReturnSpeed = 0.60
    private let emergencyNestReturnSpeed = 0.76

    private let foodEmergencyRatio = 0.35
    private let criticalFoodRatio = 0.18
    private let minimumBreedingFoodRatio = 0.45

    // MARK: - Defense

    let detectionRadius = 20.0
    let breachRadius = 10.0
    let recruitmentRadius = 11.0
    let spawnChance = 0.75

    private let maximumInvaders = 12
    private let defenseActivationThreshold = 0.18
    private let defenseCriticalThreshold = 0.72

    // MARK: - Performance caches

    private var foodCellLookup: [Int] = []
    private var neighborCache: [[Int]] = []

    private let constructionUpdateInterval = 2
    private let pheromoneUpdateInterval = 2
    private let foodCleanupInterval = 4
    private let foodSenseRadius = 8

    private var defenseStepCounter = 0
    private var defenseInitialized = false
    private var nextInvaderGeneration = 2
    private var cachedPopulationPressure = 0.0
    private var cachedBroodCareWorkers = 0

    // MARK: - Published state

    @Published var colonyAlarm = 0.0
    @Published var invaders: [ColonyInvader] = []
    @Published var defenseCells: [DefenseCell] = []
    @Published var defensiveAlarm: Double = 0.0
    @Published var defendersActive: Int = 0
    @Published var invadersDefeated: Int = 0
    @Published var invaderBreaches: Int = 0
    @Published var defenseGeneration: Int = 0

    @Published var cells: [ColonyCell]
    @Published var ants: [Ant] = []
    @Published var foodSources: [FoodSource] = []
    @Published var generation: Int = 0
    @Published var colonyEnergy: Double = 0.0
    @Published var storedFood: Double = 250.0
    @Published var storageCapacity: Double = 100.0
    @Published var foodCollected: Double = 0.0
    @Published var foodCreated: Double = 0.0
    @Published var births: Int = 0
    @Published var deaths: Int = 0
    @Published var tunnelsBuilt: Int = 0
    @Published var storageChambersBuilt: Int = 0
    @Published var colonyAlive: Bool = true
    @Published var paused: Bool = false

    // MARK: - World

    let width: Int
    let height: Int
    let nestCenterX: Int
    let nestCenterY: Int

    let initialPopulation = 250
    let maximumPopulation = 1000

    private let maximumFoodSources = 95
    private let chamberFoodCapacity = 85.0

    private var currentReproductionRate: Double = 0.0
    private var nextFoodGeneration = 1
    private var constructionCandidates: Set<Int> = []

    // MARK: - Colony status

    private var foodReserveRatio: Double {
        guard storageCapacity > 0 else { return 0.0 }
        return min(1.0, max(0.0, storedFood / storageCapacity))
    }

    private var foodEmergencyActive: Bool {
        foodReserveRatio < foodEmergencyRatio
    }

    private var criticalFoodEmergency: Bool {
        foodReserveRatio < criticalFoodRatio
    }

    var broodCareLevel: Double {
        switch foodReserveRatio {
        case ..<0.15:
            return 0.10
        case 0.15..<0.45:
            return 0.40
        case 0.45..<0.75:
            return 0.75
        default:
            return 1.0
        }
    }

    private var desiredBroodCareWorkers: Int {
        let base = max(12, ants.count / 10)

        if criticalFoodEmergency {
            return max(base, ants.count / 3)
        }

        if foodEmergencyActive {
            return max(base, ants.count / 5)
        }

        return base
    }

    // MARK: - Init

    init(width: Int = 100, height: Int = 65) {
        self.width = width
        self.height = height
        self.nestCenterX = width / 2
        self.nestCenterY = height / 2
        self.cells = Array(repeating: ColonyCell(), count: width * height)
        self.colonyEnergy = Double(initialPopulation) * 8.0

        self.foodCellLookup = Array(repeating: -1, count: width * height)

        buildNeighborCache()
        buildInitialWorld()
        createInitialColony()
        createInitialFood()
        rebuildFoodLookup()
        rebuildStorageIndex()

        if storageCellTotal == 0 {
            createInitialStorageCells()
            rebuildStorageIndex()
        }

        distributeInitialStoredFood()
        rebuildCellOccupancy()
    }

    // MARK: - Step

    func step() {
        guard colonyAlive, !paused else { return }

        generation += 1
        cachedPopulationPressure = min(
            1.0,
            Double(ants.count) / Double(maximumPopulation)
        )
        cachedBroodCareWorkers = countBroodCareWorkers()

        generateFoodIfNeeded()
        regenerateFoodSources()
        moveAnts()

        if generation % constructionUpdateInterval == 0 {
            performColonyConstruction()
        }

        if generation % pheromoneUpdateInterval == 0 {
            evaporatePheromones()
        }

        consumeColonyEnergy()
        convertStoredFoodToEnergy()
        populationDynamics()

        defenseStepCounter += 1
        if defenseStepCounter >= 3 {
            defenseStepCounter = 0
            stepDefenseSystem()
        }

        removeDeadAnts()

        if generation % foodCleanupInterval == 0 {
            removeDepletedFood()
        }

        evaluateColony()
    }

    // MARK: - Grid helpers

    @inline(__always)
    private func indexFor(_ x: Int, _ y: Int) -> Int {
        y * width + x
    }

    private func clamp(_ value: Double, _ minimum: Double, _ maximum: Double) -> Double {
        min(maximum, max(minimum, value))
    }

    private func normalized(x: Double, y: Double) -> (x: Double, y: Double) {
        let magnitude = sqrt(x * x + y * y)

        guard magnitude > 0.0001 else {
            return (0.0, 0.0)
        }

        return (x / magnitude, y / magnitude)
    }

    private func distance(
        x1: Double,
        y1: Double,
        x2: Double,
        y2: Double
    ) -> Double {
        let dx = x2 - x1
        let dy = y2 - y1
        return sqrt(dx * dx + dy * dy)
    }

    private func distanceFromNestSquared(x: Double, y: Double) -> Double {
        let dx = x - Double(nestCenterX)
        let dy = y - Double(nestCenterY)
        return dx * dx + dy * dy
    }

    private func isInsideNest(x: Double, y: Double) -> Bool {
        distanceFromNestSquared(x: x, y: y) <= 36.0
    }

    // MARK: - World setup

    private func buildInitialWorld() {
        for y in 0..<height {
            for x in 0..<width {
                let dx = Double(x - nestCenterX)
                let dy = Double(y - nestCenterY)
                let distanceSquared = dx * dx + dy * dy
                let index = indexFor(x, y)

                if distanceSquared <= 36.0 {
                    cells[index].terrain = .nest
                    cells[index].nestStrength = 1.0
                } else if abs(dx) < 1.5 || abs(dy) < 1.5 {
                    cells[index].terrain = .tunnel
                    cells[index].construction = 1.0
                    cells[index].nestStrength = 0.8
                }
            }
        }

        var obstaclesPlaced = 0

        while obstaclesPlaced < 85 {
            let x = Int.random(in: 3..<(width - 3))
            let y = Int.random(in: 3..<(height - 3))

            let dx = Double(x - nestCenterX)
            let dy = Double(y - nestCenterY)

            guard dx * dx + dy * dy > 169.0 else {
                continue
            }

            let index = indexFor(x, y)

            guard cells[index].terrain == .empty else {
                continue
            }

            cells[index].terrain = .obstacle
            obstaclesPlaced += 1
        }
    }

    private func createInitialStorageCells() {
        let storageLocations = [
            (nestCenterX - 4, nestCenterY),
            (nestCenterX + 4, nestCenterY),
            (nestCenterX, nestCenterY - 4),
            (nestCenterX, nestCenterY + 4),
            (nestCenterX - 3, nestCenterY - 3),
            (nestCenterX + 3, nestCenterY + 3),
            (nestCenterX - 3, nestCenterY + 3),
            (nestCenterX + 3, nestCenterY - 3)
        ]

        for location in storageLocations {
            let x = location.0
            let y = location.1

            guard x >= 1, x < width - 1,
                  y >= 1, y < height - 1 else {
                continue
            }

            let index = indexFor(x, y)

            guard cells[index].terrain == .nest ||
                    cells[index].terrain == .tunnel else {
                continue
            }

            cells[index].terrain = .storage
            cells[index].construction = 1.0
            cells[index].nestStrength = 1.0
        }
    }

    private func createInitialColony() {
        ants.reserveCapacity(maximumPopulation)

        for _ in 0..<initialPopulation {
            let angle = Double.random(in: 0...(Double.pi * 2.0))
            let radius = sqrt(Double.random(in: 0...1)) * 5.5

            ants.append(
                Ant(
                    x: clamp(
                        Double(nestCenterX) + cos(angle) * radius,
                        1,
                        Double(width - 2)
                    ),
                    y: clamp(
                        Double(nestCenterY) + sin(angle) * radius,
                        1,
                        Double(height - 2)
                    ),
                    state: .resting,
                    energy: Double.random(in: 75...100),
                    pheromoneSensitivity: Double.random(in: 0.75...1.25),
                    explorationBias: Double.random(in: 0.75...1.25)
                )
            )
        }
    }

    // MARK: - Neighbors / occupancy

    private func buildNeighborCache() {
        let count = width * height
        neighborCache = Array(repeating: [], count: count)

        for index in 0..<count {
            let x = index % width
            let y = index / width

            var neighbors: [Int] = []
            neighbors.reserveCapacity(8)

            for dy in -1...1 {
                for dx in -1...1 {
                    guard dx != 0 || dy != 0 else {
                        continue
                    }

                    let nx = x + dx
                    let ny = y + dy

                    guard nx >= 0, nx < width,
                          ny >= 0, ny < height else {
                        continue
                    }

                    neighbors.append(indexFor(nx, ny))
                }
            }

            neighborCache[index] = neighbors
        }
    }

    private func rebuildCellOccupancy() {
        for index in cells.indices {
            cells[index].antCount = 0
        }

        for ant in ants {
            let x = Int(ant.x.rounded())
            let y = Int(ant.y.rounded())

            guard x >= 0, x < width,
                  y >= 0, y < height else {
                continue
            }

            cells[indexFor(x, y)].antCount += 1
        }
    }

    @inline(__always)
    private func updateOccupancy(
        fromOldX oldX: Int,
        oldY: Int,
        toNewX newX: Int,
        newY: Int
    ) {
        guard oldX != newX || oldY != newY else {
            return
        }

        if oldX >= 0, oldX < width,
           oldY >= 0, oldY < height {
            let oldIndex = indexFor(oldX, oldY)
            cells[oldIndex].antCount = max(0, cells[oldIndex].antCount - 1)
        }

        if newX >= 0, newX < width,
           newY >= 0, newY < height {
            cells[indexFor(newX, newY)].antCount += 1
        }
    }

    @inline(__always)
    private func finishMove(index: Int, oldX: Int, oldY: Int) {
        guard ants.indices.contains(index) else {
            return
        }

        updateOccupancy(
            fromOldX: oldX,
            oldY: oldY,
            toNewX: Int(ants[index].x.rounded()),
            newY: Int(ants[index].y.rounded())
        )
    }

    // MARK: - Storage

    private func rebuildStorageIndex() {
        storageCellIndices.removeAll(keepingCapacity: true)

        for index in cells.indices where cells[index].terrain == .storage {
            storageCellIndices.append(index)
        }

        storageCellTotal = storageCellIndices.count
        updateStorageCapacityFromTotal()
        synchronizeStoredFoodFromCells()
    }

    private func registerStorageCell(at index: Int) {
        guard !storageCellIndices.contains(index) else {
            return
        }

        storageCellIndices.append(index)
        storageCellTotal = storageCellIndices.count
        storageChambersBuilt += 1
        updateStorageCapacityFromTotal()
    }

    private func updateStorageCapacityFromTotal() {
        storageCapacity = max(
            220.0,
            Double(storageCellTotal) * chamberFoodCapacity
        )

        storedFood = min(storedFood, storageCapacity)
    }

    private func synchronizeStoredFoodFromCells() {
        let actualStoredFood = storageCellIndices.reduce(0.0) { total, index in
            total + cells[index].storedFood
        }

        if actualStoredFood > 0.0001 {
            storedFood = min(storageCapacity, actualStoredFood)
        }
    }

    private func distributeInitialStoredFood() {
        guard !storageCellIndices.isEmpty else {
            storedFood = 0
            return
        }

        let amount = min(storedFood, storageCapacity)

        for index in storageCellIndices {
            cells[index].storedFood = 0
        }

        depositIntoStorageChambers(
            nearX: Double(nestCenterX),
            nearY: Double(nestCenterY),
            amount: amount
        )

        synchronizeStoredFoodFromCells()
    }

    @discardableResult
    private func depositIntoStorageChambers(
        nearX: Double,
        nearY: Double,
        amount: Double
    ) -> Double {
        guard amount > 0,
              !storageCellIndices.isEmpty else {
            return 0
        }

        var remaining = amount

        let sortedStorage = storageCellIndices.sorted {
            let x0 = Double($0 % width)
            let y0 = Double($0 / width)
            let x1 = Double($1 % width)
            let y1 = Double($1 / width)

            let dx0 = x0 - nearX
            let dy0 = y0 - nearY
            let dx1 = x1 - nearX
            let dy1 = y1 - nearY

            return dx0 * dx0 + dy0 * dy0 < dx1 * dx1 + dy1 * dy1
        }

        for index in sortedStorage {
            guard remaining > 0 else {
                break
            }

            let room = max(0, chamberFoodCapacity - cells[index].storedFood)

            guard room > 0 else {
                continue
            }

            let deposit = min(room, remaining)
            cells[index].storedFood += deposit
            remaining -= deposit
        }

        return amount - remaining
    }

    @discardableResult
    private func withdrawFromStorageChambers(amount: Double) -> Double {
        guard amount > 0,
              !storageCellIndices.isEmpty else {
            return 0
        }

        var remaining = amount

        let sortedStorage = storageCellIndices.sorted {
            cells[$0].storedFood > cells[$1].storedFood
        }

        for index in sortedStorage {
            guard remaining > 0 else {
                break
            }

            let withdrawal = min(cells[index].storedFood, remaining)
            cells[index].storedFood -= withdrawal
            remaining -= withdrawal
        }

        return amount - remaining
    }

    @discardableResult
    private func consumeStoredFood(_ requestedAmount: Double) -> Double {
        guard requestedAmount > 0,
              storedFood > 0 else {
            return 0
        }

        let actualAmount = min(requestedAmount, storedFood)
        let removed = withdrawFromStorageChambers(amount: actualAmount)

        storedFood = max(0, storedFood - removed)

        return removed
    }

    // MARK: - Food

    private func rebuildFoodLookup() {
        foodCellLookup = Array(repeating: -1, count: width * height)

        for (sourceIndex, source) in foodSources.enumerated()
        where !source.depleted {
            let index = indexFor(source.x, source.y)

            guard foodCellLookup.indices.contains(index) else {
                continue
            }

            foodCellLookup[index] = sourceIndex
        }
    }

    @inline(__always)
    private func foodIndexAt(x: Int, y: Int) -> Int? {
        guard x >= 0, x < width,
              y >= 0, y < height else {
            return nil
        }

        let foodIndex = foodCellLookup[indexFor(x, y)]

        return foodIndex >= 0 ? foodIndex : nil
    }

    private func createInitialFood() {
        for _ in 0..<12 {
            createFoodSource()
        }

        nextFoodGeneration = generation + Int.random(in: 12...25)
        rebuildFoodLookup()
    }

    private func generateFoodIfNeeded() {
        guard generation >= nextFoodGeneration else {
            return
        }

        let population = max(ants.count, 1)

        let target = min(
            maximumFoodSources,
            max(8, Int(ceil(Double(population) / 30.0)))
        )

        let needed = max(0, target - foodSources.count)

        if needed > 0 {
            let lowerBound = min(
                needed,
                max(2, Int(ceil(Double(population) / 60.0)))
            )

            let upperBound = min(
                needed,
                max(lowerBound, Int(ceil(Double(population) / 30.0)))
            )

            for _ in 0..<Int.random(in: lowerBound...upperBound) {
                guard foodSources.count < maximumFoodSources else {
                    break
                }

                createFoodSource()
            }
        }

        let intervalLow = max(3, 10 - population / 100)
        let intervalHigh = max(intervalLow + 2, 16 - population / 120)

        nextFoodGeneration = generation + Int.random(in: intervalLow...intervalHigh)
    }

    private func regenerateFoodSources() {
        guard !foodSources.isEmpty else {
            return
        }

        let populationFactor = foodEmergencyActive ? 1.35 : 1.0

        for index in foodSources.indices where !foodSources[index].depleted {
            foodSources[index].regenerate(populationFactor: populationFactor)
        }
    }

    private func createFoodSource() {
        guard let location = randomFoodLocation() else {
            return
        }

        let type = chooseFoodType()

        let populationFactor = min(
            2.0,
            max(
                0.75,
                Double(max(ants.count, 1)) / Double(initialPopulation)
            )
        )

        let amount: Double

        switch type {
        case .seed:
            amount = Double.random(in: 55...150) * populationFactor
        case .fruit:
            amount = Double.random(in: 28...90) * populationFactor
        case .insect:
            amount = Double.random(in: 10...40) * populationFactor
        case .nectar:
            amount = Double.random(in: 36...115) * populationFactor
        }

        foodSources.append(
            FoodSource(
                x: location.x,
                y: location.y,
                type: type,
                amount: amount,
                maximumAmount: amount,
                regenerationRate: max(0.15, amount * 0.002)
            )
        )

        let index = indexFor(location.x, location.y)
        cells[index].terrain = .food
        foodCellLookup[index] = foodSources.count - 1
        foodCreated += amount
    }

    private func chooseFoodType() -> FoodType {
        let energyPerAnt = colonyEnergy / Double(max(ants.count, 1))
        let roll = Double.random(in: 0..<1)

        if energyPerAnt < 4 {
            if roll < 0.40 { return .insect }
            if roll < 0.70 { return .fruit }
            if roll < 0.88 { return .nectar }
            return .seed
        }

        if energyPerAnt < 8 {
            if roll < 0.30 { return .insect }
            if roll < 0.55 { return .fruit }
            if roll < 0.80 { return .nectar }
            return .seed
        }

        return FoodType.allCases.randomElement() ?? .seed
    }

    private func randomFoodLocation() -> (x: Int, y: Int)? {
        for _ in 0..<100 {
            let x = Int.random(in: 4..<(width - 4))
            let y = Int.random(in: 4..<(height - 4))

            let dx = Double(x - nestCenterX)
            let dy = Double(y - nestCenterY)

            guard dx * dx + dy * dy > 144 else {
                continue
            }

            let index = indexFor(x, y)

            guard cells[index].terrain == .empty,
                  foodCellLookup[index] < 0 else {
                continue
            }

            return (x, y)
        }

        return nil
    }

    private func removeDepletedFood() {
        var removedAny = false

        for source in foodSources where source.depleted {
            let index = indexFor(source.x, source.y)

            if cells[index].terrain == .food {
                cells[index].terrain = .empty
            }

            if foodCellLookup.indices.contains(index) {
                foodCellLookup[index] = -1
            }

            removedAny = true
        }

        if removedAny {
            foodSources.removeAll { $0.depleted }
            rebuildFoodLookup()
        }
    }

    // MARK: - Ant movement

    private func moveAnts() {
        let pressure = cachedPopulationPressure

        let foodRatio = storedFood / max(storageCapacity, 1.0)

        // High stored food means the colony can safely send more workers out.
        let broodCareFraction: Double

        switch foodRatio {
        case 0.75...:
            broodCareFraction = 0.05

        case 0.50..<0.75:
            broodCareFraction = 0.10

        case 0.25..<0.50:
            broodCareFraction = 0.15

        default:
            broodCareFraction = 0.20
        }

        let broodCareTarget = max(
            6,
            min(40, Int(Double(ants.count) * broodCareFraction))
        )

        var nestCareCount = ants.reduce(into: 0) { count, ant in
            if ant.state == .resting &&
               isInsideNest(x: ant.x, y: ant.y) {
                count += 1
            }
        }

        for i in ants.indices {
            let oldX = Int(ants[i].x.rounded())
            let oldY = Int(ants[i].y.rounded())

            ants[i].age += 1

            guard ants[i].energy > 0 else {
                continue
            }

            // Food delivery is always the highest worker priority.
            if ants[i].hasFood {
                ants[i].defending = false
                ants[i].defenseTargetID = nil
                ants[i].state = .returning

                moveReturningAnt(index: i)

                finishMove(index: i, oldX: oldX, oldY: oldY)
                continue
            }

            // Defenders move only in stepDefenseSystem().
            if ants[i].defending {
                ants[i].state = .defending
                continue
            }

            let density = localCrowdingFast(atX: oldX, atY: oldY)

            ants[i].energy = max(
                0.0,
                ants[i].energy - movementCost(
                    state: ants[i].state,
                    density: density,
                    populationPressure: pressure
                )
            )

            guard ants[i].energy > 0 else {
                continue
            }

            // Weak workers return for feeding and recovery.
            if ants[i].energy <= lowEnergyReturnThreshold,
               ants[i].state != .returningForFood {
                ants[i].state = .returningForFood
            }

            if ants[i].state == .returningForFood {
                moveAntToNestForFood(index: i)

                finishMove(index: i, oldX: oldX, oldY: oldY)
                continue
            }

            // Nest worker behavior:
            // recover if weak; otherwise leave unless needed for brood care.
            if ants[i].state == .resting {
                guard isInsideNest(x: ants[i].x, y: ants[i].y) else {
                    ants[i].state = .returningForFood

                    finishMove(index: i, oldX: oldX, oldY: oldY)
                    continue
                }

                feedAntFromStoredFood(index: i)

                ants[i].energy = min(
                    100.0,
                    ants[i].energy + 0.30
                )

                guard ants[i].energy >= recoveredEnergyThreshold else {
                    finishMove(index: i, oldX: oldX, oldY: oldY)
                    continue
                }

                // High food: release excess nest ants immediately.
                if nestCareCount > broodCareTarget {
                    ants[i].state = .searching
                    nestCareCount -= 1
                } else if nestCareCount < broodCareTarget {
                    // This ant remains in the small brood-care group.
                    nestCareCount += 1
                } else {
                    // At the exact target, continue rotating workers out.
                    let releaseChance = foodRatio >= 0.75 ? 0.45 : 0.18

                    if Double.random(in: 0...1) < releaseChance {
                        ants[i].state = .searching
                        nestCareCount -= 1
                    }
                }

                finishMove(index: i, oldX: oldX, oldY: oldY)
                continue
            }

            // Construction is disabled if food is low.
            if foodRatio >= 0.40,
               shouldConstruct(ant: ants[i]) {
                ants[i].state = .building

                moveConstructionAnt(index: i)

                finishMove(index: i, oldX: oldX, oldY: oldY)
                continue
            }

            // Pick up food if close enough.
            if let foodIndex = foodAt(
                x: ants[i].x,
                y: ants[i].y,
                radius: 1.5
            ) {
                collectFood(
                    antIndex: i,
                    foodIndex: foodIndex
                )

                finishMove(index: i, oldX: oldX, oldY: oldY)
                continue
            }

            // Healthy non-nest workers forage.
            ants[i].state = .searching

            moveSearchingAnt(
                index: i,
                density: density,
                populationPressure: pressure
            )

            finishMove(index: i, oldX: oldX, oldY: oldY)
        }

        removeDeadAnts()
    }
    private func shouldRecallAntForBroodCare(index: Int) -> Bool {
        guard ants.indices.contains(index) else {
            return false
        }

        guard foodEmergencyActive,
              !ants[index].hasFood,
              ants[index].state != .returning,
              ants[index].state != .returningForFood,
              ants[index].state != .defending else {
            return false
        }

        let deficit = max(0, desiredBroodCareWorkers - cachedBroodCareWorkers)

        if criticalFoodEmergency {
            return deficit > 0
                ? Double.random(in: 0...1) < 0.55
                : Double.random(in: 0...1) < 0.16
        }

        return deficit > 0
            ? Double.random(in: 0...1) < 0.20
            : Double.random(in: 0...1) < 0.04
    }

    private func countBroodCareWorkers() -> Int {
        ants.reduce(into: 0) { count, ant in
            if ant.state == .resting && isInsideNest(x: ant.x, y: ant.y) {
                count += 1
            }
        }
    }

    private func handleRestingAnt(index: Int) {
        guard ants.indices.contains(index) else {
            return
        }

        guard isInsideNest(x: ants[index].x, y: ants[index].y) else {
            ants[index].state = .returningForFood
            return
        }

        feedAntFromStoredFood(index: index)

        let broodRecoveryBonus: Double

        if criticalFoodEmergency {
            broodRecoveryBonus = 0.42
        } else if foodEmergencyActive {
            broodRecoveryBonus = 0.30
        } else {
            broodRecoveryBonus = 0.20
        }

        ants[index].energy = min(
            100,
            ants[index].energy + broodRecoveryBonus
        )

        guard ants[index].energy >= recoveredEnergyThreshold else {
            return
        }

        if foodEmergencyActive {
            let releaseChance = criticalFoodEmergency ? 0.006 : 0.015

            if cachedBroodCareWorkers >= desiredBroodCareWorkers,
               Double.random(in: 0...1) < releaseChance {
                ants[index].state = .searching
            }

            return
        }

        if Double.random(in: 0...1) < 0.05 {
            ants[index].state = .searching
        }
    }

    private func moveSearchingAnt(
        index: Int,
        density: Double,
        populationPressure: Double
    ) {
        let ant = ants[index]

        let exploration = max(
            0.08,
            ant.explorationBias * (1.0 - populationPressure * 0.65)
        )

        let trailWeight = ant.pheromoneSensitivity * (
            0.8 + populationPressure * 1.6
        )

        var vx = 0.0
        var vy = 0.0

        let food = foodDirection(for: ant)
        vx += food.x * 3.2
        vy += food.y * 3.2

        let pheromone = pheromoneDirection(for: ant)
        vx += pheromone.x * trailWeight
        vy += pheromone.y * trailWeight

        if let memoryX = ant.rememberedFoodX,
           let memoryY = ant.rememberedFoodY {
            let dx = memoryX - ant.x
            let dy = memoryY - ant.y
            let distanceSquared = dx * dx + dy * dy

            if distanceSquared > 0.25,
               distanceSquared < 1225 {
                let inverseDistance = 1.0 / sqrt(distanceSquared)
                vx += dx * inverseDistance * 0.55
                vy += dy * inverseDistance * 0.55
            }
        }

        let nestDistanceSquared = distanceFromNestSquared(
            x: ant.x,
            y: ant.y
        )

        if nestDistanceSquared < 81 {
            let dx = ant.x - Double(nestCenterX)
            let dy = ant.y - Double(nestCenterY)
            let inverseDistance = 1.0 / max(0.001, sqrt(nestDistanceSquared))

            vx += dx * inverseDistance * 0.7
            vy += dy * inverseDistance * 0.7
        }

        let crowd = crowdingDirectionFast(
            cx: Int(ant.x.rounded()),
            cy: Int(ant.y.rounded())
        )

        vx += crowd.x * (0.5 + populationPressure * 1.5)
        vy += crowd.y * (0.5 + populationPressure * 1.5)

        vx += Double.random(in: -1...1) * exploration
        vy += Double.random(in: -1...1) * exploration

        let direction = normalized(x: vx, y: vy)
        let speed = max(0.18, 0.52 - density * 0.025)

        _ = moveAntSafely(
            index: index,
            directionX: direction.x,
            directionY: direction.y,
            speed: speed
        )

        ants[index].state = Double.random(in: 0...1) < 0.003
            ? .exploring
            : .searching
    }

    private func moveReturningAnt(index: Int) {
        let ant = ants[index]

        let dx = Double(nestCenterX) - ant.x
        let dy = Double(nestCenterY) - ant.y
        let inverseDistance = 1.0 / max(0.001, sqrt(dx * dx + dy * dy))

        let trail = nestDirection(for: ant)

        let direction = normalized(
            x: dx * inverseDistance * 0.90 + trail.x * 0.10,
            y: dy * inverseDistance * 0.90 + trail.y * 0.10
        )

        let speed = foodEmergencyActive
            ? emergencyFoodReturnSpeed
            : normalFoodReturnSpeed

        _ = moveAntSafely(
            index: index,
            directionX: direction.x,
            directionY: direction.y,
            speed: speed
        )

        depositReturningPheromone(ant: ants[index])

        if isInsideNest(x: ants[index].x, y: ants[index].y) {
            deliverFood(antIndex: index)
        }
    }

    private func moveAntToNestForFood(index: Int) {
        guard ants.indices.contains(index) else {
            return
        }

        let ant = ants[index]

        let dx = Double(nestCenterX) - ant.x
        let dy = Double(nestCenterY) - ant.y
        let distance = sqrt(dx * dx + dy * dy)

        guard distance > 0.001 else {
            ants[index].state = .resting
            return
        }

        let inverseDistance = 1.0 / distance
        let trail = nestDirection(for: ant)

        let direction = normalized(
            x: dx * inverseDistance * 0.92 + trail.x * 0.08,
            y: dy * inverseDistance * 0.92 + trail.y * 0.08
        )

        let speed = foodEmergencyActive
            ? emergencyNestReturnSpeed
            : normalNestReturnSpeed

        _ = moveAntSafely(
            index: index,
            directionX: direction.x,
            directionY: direction.y,
            speed: speed
        )

        if isInsideNest(x: ants[index].x, y: ants[index].y) {
            ants[index].state = .resting
        }
    }
    private func moveAntSafely(
        index: Int,
        directionX: Double,
        directionY: Double,
        speed: Double
    ) -> Bool {
        guard ants.indices.contains(index) else {
            return false
        }

        let oldX = ants[index].x
        let oldY = ants[index].y

        let candidateX = oldX + directionX * speed
        let candidateY = oldY + directionY * speed

        if isWalkable(x: candidateX, y: candidateY) {
            ants[index].x = candidateX
            ants[index].y = candidateY
            ants[index].directionX = directionX
            ants[index].directionY = directionY
            return true
        }

        let alternatives = [
            (-directionY, directionX),
            (directionY, -directionX),
            (-directionX, -directionY)
        ]

        for alternative in alternatives {
            let alternateX = oldX + alternative.0 * speed
            let alternateY = oldY + alternative.1 * speed

            if isWalkable(x: alternateX, y: alternateY) {
                ants[index].x = alternateX
                ants[index].y = alternateY
                ants[index].directionX = alternative.0
                ants[index].directionY = alternative.1
                return true
            }
        }

        return false
    }

    private func isWalkable(x: Double, y: Double) -> Bool {
        guard x >= 1,
              x < Double(width - 1),
              y >= 1,
              y < Double(height - 1) else {
            return false
        }

        let xIndex = Int(x.rounded())
        let yIndex = Int(y.rounded())

        return cells[indexFor(xIndex, yIndex)].terrain != .obstacle
    }

    // MARK: - Food collection / delivery

    private func foodAt(x: Double, y: Double, radius: Double) -> Int? {
        let centerX = Int(x.rounded())
        let centerY = Int(y.rounded())
        let searchRadius = max(1, Int(radius.rounded()))

        var bestFoodIndex: Int?
        var bestDistanceSquared = radius * radius

        for dy in -searchRadius...searchRadius {
            for dx in -searchRadius...searchRadius {
                guard let foodIndex = foodIndexAt(
                    x: centerX + dx,
                    y: centerY + dy
                ) else {
                    continue
                }

                guard foodSources.indices.contains(foodIndex),
                      !foodSources[foodIndex].depleted else {
                    continue
                }

                let foodDX = Double(foodSources[foodIndex].x) - x
                let foodDY = Double(foodSources[foodIndex].y) - y
                let distanceSquared = foodDX * foodDX + foodDY * foodDY

                if distanceSquared <= bestDistanceSquared {
                    bestDistanceSquared = distanceSquared
                    bestFoodIndex = foodIndex
                }
            }
        }

        return bestFoodIndex
    }

    private func collectFood(antIndex: Int, foodIndex: Int) {
        guard ants.indices.contains(antIndex),
              foodSources.indices.contains(foodIndex) else {
            return
        }

        let availableFood = foodSources[foodIndex].amount

        guard availableFood > 0 else {
            return
        }

        let type = foodSources[foodIndex].type

        let collectionMultiplier = foodEmergencyActive ? 1.25 : 1.0

        let amount = min(
            (4.0 / type.collectionDifficulty) * collectionMultiplier,
            availableFood
        )

        foodSources[foodIndex].amount -= amount

        if foodSources[foodIndex].amount <= 0.01 {
            foodSources[foodIndex].amount = 0

            let cellIndex = indexFor(
                foodSources[foodIndex].x,
                foodSources[foodIndex].y
            )

            if foodCellLookup.indices.contains(cellIndex) {
                foodCellLookup[cellIndex] = -1
            }
        }

        ants[antIndex].carriedFood += amount
        ants[antIndex].carriedFoodType = type
        ants[antIndex].state = .returning
        ants[antIndex].rememberedFoodX = Double(foodSources[foodIndex].x)
        ants[antIndex].rememberedFoodY = Double(foodSources[foodIndex].y)

        let cellIndex = indexFor(
            foodSources[foodIndex].x,
            foodSources[foodIndex].y
        )

        cells[cellIndex].foodPheromone = min(
            25.0,
            cells[cellIndex].foodPheromone + 3.0 * type.attraction
        )
    }

    private func deliverFood(antIndex: Int) {
        guard ants.indices.contains(antIndex) else {
            return
        }

        guard ants[antIndex].hasFood else {
            assignPostDeliveryRole(antIndex: antIndex)
            return
        }

        let amount = ants[antIndex].carriedFood
        let type = ants[antIndex].carriedFoodType ?? .seed

        // The worker consumes enough food to remain productive.
        let selfFeed = min(amount, 1.5)
        let selfEnergy = selfFeed * type.energyPerUnit

        ants[antIndex].energy = min(
            100.0,
            ants[antIndex].energy + selfEnergy
        )

        colonyEnergy = min(
            100_000.0,
            colonyEnergy + selfEnergy * 0.25
        )

        let foodForColony = max(0.0, amount - selfFeed)

        // Keep the existing function signature if your current
        // depositIntoStorageChambers does not return a value.
        let availableStorage = max(0.0, storageCapacity - storedFood)
        let storedAmount = min(foodForColony, availableStorage)

        storedFood += storedAmount

        depositIntoStorageChambers(
            nearX: ants[antIndex].x,
            nearY: ants[antIndex].y,
            amount: storedAmount
        )

        foodCollected += storedAmount

        let overflow = max(0.0, foodForColony - storedAmount)

        if overflow > 0 {
            colonyEnergy = min(
                100_000.0,
                colonyEnergy + overflow * type.energyPerUnit * 0.70
            )
        }

        ants[antIndex].carriedFood = 0.0
        ants[antIndex].carriedFoodType = nil

        let x = Int(ants[antIndex].x.rounded())
        let y = Int(ants[antIndex].y.rounded())

        if x >= 0, x < width,
           y >= 0, y < height {
            let cellIndex = indexFor(x, y)

            cells[cellIndex].nestPheromone = min(
                25.0,
                cells[cellIndex].nestPheromone + 2.0
            )
        }

        assignPostDeliveryRole(antIndex: antIndex)
    }

    private func assignPostDeliveryRole(antIndex: Int) {
        guard ants.indices.contains(antIndex) else {
            return
        }

        // A food carrier must always finish its delivery first.
        guard !ants[antIndex].hasFood else {
            ants[antIndex].state = .returning
            return
        }

        // 1. Defense takes priority if an invader is close enough.
        if let target = nearestActiveInvader(
            fromX: ants[antIndex].x,
            y: ants[antIndex].y,
            maximumDistance: recruitmentRadius
        ) {
            ants[antIndex].defending = true
            ants[antIndex].defenseTargetID = target.id
            ants[antIndex].state = .defending
            return
        }

        // 2. Keep only a small, controlled brood-care group in the nest.
        let broodWorkersNeeded = max(8, ants.count / 12)

        let broodWorkersPresent = ants.reduce(into: 0) { count, ant in
            if ant.state == .resting &&
               isInsideNest(x: ant.x, y: ant.y) {
                count += 1
            }
        }

        if broodWorkersPresent < broodWorkersNeeded,
           ants[antIndex].energy < recoveredEnergyThreshold {
            ants[antIndex].defending = false
            ants[antIndex].defenseTargetID = nil
            ants[antIndex].state = .resting
            return
        }

        // 3. Low-energy ants recover in the nest.
        if ants[antIndex].energy < 50.0 {
            ants[antIndex].defending = false
            ants[antIndex].defenseTargetID = nil
            ants[antIndex].state = .resting
            return
        }

        // 4. Healthy ants immediately resume searching.
        ants[antIndex].defending = false
        ants[antIndex].defenseTargetID = nil
        ants[antIndex].state = .searching
    }
    private func nearestActiveInvader(
        fromX x: Double,
        y: Double,
        maximumDistance: Double
    ) -> ColonyInvader? {
        var nearest: ColonyInvader?
        var nearestDistance = maximumDistance

        for invader in invaders where invader.alive && invader.health > 0 {
            let distanceToInvader = distance(
                x1: x,
                y1: y,
                x2: invader.x,
                y2: invader.y
            )

            if distanceToInvader <= nearestDistance {
                nearestDistance = distanceToInvader
                nearest = invader
            }
        }

        return nearest
    }
    private func feedAntFromStoredFood(index: Int) {
        guard ants.indices.contains(index),
              isInsideNest(x: ants[index].x, y: ants[index].y),
              ants[index].energy < recoveredEnergyThreshold,
              storedFood > 0 else {
            return
        }

        let foodRequested = min(
            maximumFoodPerRecoveryStep,
            (recoveredEnergyThreshold - ants[index].energy) / personalEnergyPerFoodUnit,
            storedFood
        )

        let foodConsumed = consumeStoredFood(foodRequested)

        guard foodConsumed > 0 else {
            return
        }

        ants[index].energy = min(
            100,
            ants[index].energy + foodConsumed * personalEnergyPerFoodUnit
        )
    }

    // MARK: - Directions / pheromones

    private func foodDirection(for ant: Ant) -> (x: Double, y: Double) {
        if let rememberedX = ant.rememberedFoodX,
           let rememberedY = ant.rememberedFoodY {
            let dx = rememberedX - ant.x
            let dy = rememberedY - ant.y
            let distanceSquared = dx * dx + dy * dy

            if distanceSquared > 0.25,
               distanceSquared < 1225 {
                let inverseDistance = 1.0 / sqrt(distanceSquared)
                return (dx * inverseDistance, dy * inverseDistance)
            }
        }

        let centerX = Int(ant.x.rounded())
        let centerY = Int(ant.y.rounded())
        let radius = foodSenseRadius
        let radiusSquared = Double(radius * radius)

        var vx = 0.0
        var vy = 0.0

        for dy in -radius...radius {
            for dx in -radius...radius {
                guard let foodIndex = foodIndexAt(
                    x: centerX + dx,
                    y: centerY + dy
                ) else {
                    continue
                }

                guard foodSources.indices.contains(foodIndex),
                      !foodSources[foodIndex].depleted else {
                    continue
                }

                let source = foodSources[foodIndex]
                let foodDX = Double(source.x) - ant.x
                let foodDY = Double(source.y) - ant.y
                let distanceSquared = foodDX * foodDX + foodDY * foodDY

                guard distanceSquared > 0.0001,
                      distanceSquared <= radiusSquared else {
                    continue
                }

                let distance = sqrt(distanceSquared)

                let weight = source.type.attraction
                    * min(3.0, max(0.2, source.amount / 20.0))
                    / max(distance, 1.0)

                vx += (foodDX / distance) * weight
                vy += (foodDY / distance) * weight
            }
        }

        return normalized(x: vx, y: vy)
    }

    private func pheromoneDirection(for ant: Ant) -> (x: Double, y: Double) {
        let centerX = Int(ant.x.rounded())
        let centerY = Int(ant.y.rounded())

        var bestValue = 0.0
        var bestX = 0
        var bestY = 0

        for dy in -2...2 {
            for dx in -2...2 {
                guard dx != 0 || dy != 0 else {
                    continue
                }

                let x = centerX + dx
                let y = centerY + dy

                guard x >= 0, x < width,
                      y >= 0, y < height else {
                    continue
                }

                let value = cells[indexFor(x, y)].foodPheromone

                if value > bestValue {
                    bestValue = value
                    bestX = dx
                    bestY = dy
                }
            }
        }

        return normalized(x: Double(bestX), y: Double(bestY))
    }

    private func nestDirection(for ant: Ant) -> (x: Double, y: Double) {
        let centerX = Int(ant.x.rounded())
        let centerY = Int(ant.y.rounded())

        var vx = 0.0
        var vy = 0.0

        for dy in -2...2 {
            for dx in -2...2 {
                guard dx != 0 || dy != 0 else {
                    continue
                }

                let x = centerX + dx
                let y = centerY + dy

                guard x >= 0, x < width,
                      y >= 0, y < height else {
                    continue
                }

                let value = cells[indexFor(x, y)].nestPheromone

                guard value > 0 else {
                    continue
                }

                let inverseDistance = 1.0 / sqrt(Double(dx * dx + dy * dy))

                vx += Double(dx) * inverseDistance * value
                vy += Double(dy) * inverseDistance * value
            }
        }

        return normalized(x: vx, y: vy)
    }

    private func depositReturningPheromone(ant: Ant) {
        let x = Int(ant.x.rounded())
        let y = Int(ant.y.rounded())

        guard x >= 0, x < width,
              y >= 0, y < height else {
            return
        }

        let index = indexFor(x, y)

        cells[index].foodPheromone = min(
            25.0,
            cells[index].foodPheromone + 0.22
        )

        cells[index].nestPheromone = min(
            25.0,
            cells[index].nestPheromone + 0.14
        )
    }

    private func evaporatePheromones() {
        for index in cells.indices {
            if cells[index].foodPheromone > 0.0005 {
                cells[index].foodPheromone *= 0.992

                if cells[index].foodPheromone < 0.001 {
                    cells[index].foodPheromone = 0
                }
            }

            if cells[index].nestPheromone > 0.0005 {
                cells[index].nestPheromone *= 0.995

                if cells[index].nestPheromone < 0.001 {
                    cells[index].nestPheromone = 0
                }
            }
        }
    }

    // MARK: - Crowding

    @inline(__always)
    private func localCrowdingFast(atX centerX: Int, atY centerY: Int) -> Double {
        var count = 0

        for dy in -2...2 {
            for dx in -2...2 {
                let x = centerX + dx
                let y = centerY + dy

                guard x >= 0, x < width,
                      y >= 0, y < height else {
                    continue
                }

                count += cells[indexFor(x, y)].antCount
            }
        }

        return min(3.0, Double(count) / 12.0)
    }

    private func crowdingDirectionFast(
        cx: Int,
        cy: Int
    ) -> (x: Double, y: Double) {
        var vx = 0.0
        var vy = 0.0

        for dy in -2...2 {
            for dx in -2...2 {
                guard dx != 0 || dy != 0 else {
                    continue
                }

                let x = cx + dx
                let y = cy + dy

                guard x >= 0, x < width,
                      y >= 0, y < height else {
                    continue
                }

                let antCount = cells[indexFor(x, y)].antCount

                guard antCount > 0 else {
                    continue
                }

                let inverseDistance = 1.0 / sqrt(Double(dx * dx + dy * dy))

                vx -= Double(dx) * inverseDistance * Double(antCount)
                vy -= Double(dy) * inverseDistance * Double(antCount)
            }
        }

        return normalized(x: vx, y: vy)
    }

    // MARK: - Construction

    private func shouldConstruct(ant: Ant) -> Bool {
        guard !ant.hasFood,
              !foodEmergencyActive,
              ant.energy >= 55.0 else {
            return false
        }

        let requiredCells = Double(ants.count) * 0.20
        let currentCells = Double(nestCellCount)
        let foodRatio = foodReserveRatio
        let growth = min(1.0, currentReproductionRate / 0.113)

        if currentCells < requiredCells * (1.0 + growth * 0.6) {
            return Double.random(in: 0...1) < (0.020 + growth * 0.030)
        }

        if foodRatio > 0.60 {
            return Double.random(in: 0...1) < 0.012
        }

        return false
    }

    private func performColonyConstruction() {
        guard !foodEmergencyActive else {
            constructionCandidates.removeAll(keepingCapacity: true)
            return
        }

        constructionCandidates.removeAll(keepingCapacity: true)

        let desiredCandidates = max(
            2,
            Int(3.0 + cachedPopulationPressure * 8.0)
        )

        for _ in 0..<desiredCandidates {
            let x = Int.random(in: 2..<(width - 2))
            let y = Int.random(in: 2..<(height - 2))
            let index = indexFor(x, y)

            guard cells[index].terrain == .empty,
                  numberOfBuiltNeighbors(x: x, y: y) >= 2 else {
                continue
            }

            constructionCandidates.insert(index)
        }
    }

    private func nearestConstructionSite(from ant: Ant) -> (x: Double, y: Double)? {
        guard !constructionCandidates.isEmpty else {
            return nil
        }

        var bestIndex: Int?
        var bestDistanceSquared = Double.infinity

        for index in constructionCandidates {
            let x = index % width
            let y = index / width

            let dx = Double(x) - ant.x
            let dy = Double(y) - ant.y
            let distanceSquared = dx * dx + dy * dy

            if distanceSquared < bestDistanceSquared {
                bestDistanceSquared = distanceSquared
                bestIndex = index
            }
        }

        guard let index = bestIndex else {
            return nil
        }

        return (
            Double(index % width),
            Double(index / width)
        )
    }

    private func moveConstructionAnt(index: Int) {
        guard ants.indices.contains(index) else {
            return
        }

        guard let target = nearestConstructionSite(from: ants[index]) else {
            ants[index].state = .searching
            return
        }

        let dx = target.x - ants[index].x
        let dy = target.y - ants[index].y
        let distanceSquared = dx * dx + dy * dy
        let inverseDistance = 1.0 / max(0.001, sqrt(distanceSquared))

        _ = moveAntSafely(
            index: index,
            directionX: dx * inverseDistance,
            directionY: dy * inverseDistance,
            speed: 0.34
        )

        if distanceSquared < 3.24 {
            buildAt(x: target.x, y: target.y)
            ants[index].state = .resting
        }
    }

    private func buildAt(x: Double, y: Double) {
        let cellX = Int(x.rounded())
        let cellY = Int(y.rounded())

        guard cellX >= 1, cellX < width - 1,
              cellY >= 1, cellY < height - 1 else {
            return
        }

        let index = indexFor(cellX, cellY)

        guard cells[index].terrain == .empty,
              numberOfBuiltNeighbors(x: cellX, y: cellY) >= 2 else {
            return
        }

        let storageDemand = foodReserveRatio

        if Double.random(in: 0...1) < (storageDemand > 0.70 ? 0.65 : 0.20) {
            cells[index].terrain = .storage
            cells[index].nestStrength = 0.75
            cells[index].construction = 1.0
            registerStorageCell(at: index)
        } else {
            cells[index].terrain = .tunnel
            cells[index].nestStrength = 0.70
            cells[index].construction = 1.0
            tunnelsBuilt += 1
        }

        constructionCandidates.remove(index)
    }

    private func numberOfBuiltNeighbors(x: Int, y: Int) -> Int {
        let index = indexFor(x, y)

        guard neighborCache.indices.contains(index) else {
            return 0
        }

        var count = 0

        for neighbor in neighborCache[index] {
            let terrain = cells[neighbor].terrain

            if terrain == .nest ||
                terrain == .tunnel ||
                terrain == .storage {
                count += 1
            }
        }

        return count
    }

    // MARK: - Energy / Population

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
            base = 0.24
        case .returningForFood:
            base = 0.20
        case .resting:
            base = 0.04
        case .building:
            base = 0.36
        case .defending:
            base = 0.48
        }

        return base * (1.0 + density * 0.10 + populationPressure * 0.15)
    }

    private func consumeColonyEnergy() {
        var activeAntCount = 0

        for ant in ants where ant.state != .resting {
            activeAntCount += 1
        }

        colonyEnergy = max(
            0,
            colonyEnergy - (
                Double(ants.count) * 0.055
                + Double(activeAntCount) * 0.025
            )
        )
    }

    private func convertStoredFoodToEnergy() {
        guard storedFood > 0 else {
            return
        }

        let reserve: Double

        switch foodReserveRatio {
        case ..<0.20:
            reserve = storedFood * 0.92
        case 0.20..<0.50:
            reserve = storageCapacity * 0.18
        default:
            reserve = storageCapacity * 0.20
        }

        let available = max(0.0, storedFood - reserve)

        guard available > 0 else {
            return
        }

        let requestedRate = min(
            available,
            storedFood * 0.015,
            Double(ants.count) * 0.004
        )

        let convertedFood = consumeStoredFood(requestedRate)

        colonyEnergy = min(
            100_000,
            colonyEnergy + convertedFood * 7.0
        )
    }

    private func populationDynamics() {
        // Check births more frequently than the original every-3-step cycle.
        // This function is still called every simulation step from step().
        guard generation % 2 == 0 else {
            return
        }

        guard ants.count < maximumPopulation else {
            currentReproductionRate = 0.0
            return
        }

        let foodRatio = storedFood / max(storageCapacity, 1.0)
        let energyPerAnt = colonyEnergy / Double(max(ants.count, 1))

        // Do not reproduce during a real shortage.
        guard foodRatio >= 0.30 else {
            currentReproductionRate = 0.0
            return
        }

        // Require only modest colony energy; food is the primary resource.
        guard energyPerAnt >= 0.75 else {
            currentReproductionRate = 0.0
            return
        }

        // More stored food means a substantially larger brood allocation.
        let rate: Double

        switch foodRatio {
        case 0.30..<0.45:
            rate = 0.015       // 1.5% of population every 2 steps

        case 0.45..<0.65:
            rate = 0.035       // 3.5% every 2 steps

        case 0.65..<0.85:
            rate = 0.060       // 6.0% every 2 steps

        default:
            rate = 0.090       // 9.0% every 2 steps
        }

        currentReproductionRate = rate

        let requestedBirths = max(
            1,
            Int((Double(ants.count) * rate).rounded(.down))
        )

        let remainingPopulationSpace = maximumPopulation - ants.count

        // Keep a ceiling so a high-speed timer does not jump instantly to 1,000.
        let maximumBirthsThisCycle = min(
            30,
            remainingPopulationSpace
        )

        // Preserve food for worker recovery and emergency return-to-nest behavior.
        let protectedFood = storageCapacity * 0.20
        let foodAvailableForBrood = max(0.0, storedFood - protectedFood)

        let foodCostPerBirth = 3.5
        let foodAffordableBirths = Int(foodAvailableForBrood / foodCostPerBirth)

        let birthCount = min(
            requestedBirths,
            maximumBirthsThisCycle,
            foodAffordableBirths
        )

        guard birthCount > 0 else {
            currentReproductionRate = 0.0
            return
        }

        let totalFoodCost = Double(birthCount) * foodCostPerBirth

        // Update global food, which is the canonical food amount used by
        // worker feeding, food ratio, UI, and subsequent birth decisions.
        storedFood = max(0.0, storedFood - totalFoodCost)

        // Update physical storage cells when they exist.
        // This call safely does nothing if no storage cells were built yet.
        withdrawFromStorageChambers(amount: totalFoodCost)

        colonyEnergy = max(
            0.0,
            colonyEnergy - Double(birthCount) * 0.35
        )

        for _ in 0..<birthCount {
            let angle = Double.random(in: 0...(Double.pi * 2.0))
            let radius = Double.random(in: 1.0...4.0)

            let newborn = Ant(
                x: clamp(
                    Double(nestCenterX) + cos(angle) * radius,
                    1.0,
                    Double(width - 2)
                ),
                y: clamp(
                    Double(nestCenterY) + sin(angle) * radius,
                    1.0,
                    Double(height - 2)
                ),
                state: .resting,
                energy: Double.random(in: 84.0...98.0),
                pheromoneSensitivity: Double.random(in: 0.8...1.2),
                explorationBias: Double.random(in: 0.8...1.2)
            )

            ants.append(newborn)

            let childX = Int(newborn.x.rounded())
            let childY = Int(newborn.y.rounded())

            if childX >= 0, childX < width,
               childY >= 0, childY < height {
                cells[indexFor(childX, childY)].antCount += 1
            }
        }

        births += birthCount
    }

    private func removeDeadAnts() {
        let previousCount = ants.count

        ants.removeAll {
            $0.energy <= 0 || $0.age > 6000
        }

        let removedCount = previousCount - ants.count

        guard removedCount > 0 else {
            return
        }

        deaths += removedCount
        rebuildCellOccupancy()
    }

    private func evaluateColony() {
        guard !ants.isEmpty else {
            colonyAlive = false
            return
        }

        let averageEnergy = ants.reduce(0.0) {
            $0 + $1.energy
        } / Double(ants.count)

        if colonyEnergy <= 0,
           storedFood <= 0,
           averageEnergy < 5 {
            colonyAlive = false
        }
    }

    // MARK: - Defense public controls

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

    func alertAllHands() {
        guard !ants.isEmpty,
              let target = invaders.max(
                by: { $0.threatLevel < $1.threatLevel }
              ) else {
            return
        }

        defensiveAlarm = max(defensiveAlarm, 1.0)

        for index in ants.indices where ants[index].energy > 0 {
            guard !ants[index].hasFood else {
                continue
            }

            ants[index].defending = true
            ants[index].defenseTargetID = target.id
            ants[index].state = .defending
        }
    }

    func allHandsOnDeck() {
        let activeInvaders = invaders.filter {
            $0.alive && $0.health > 0
        }

        guard !activeInvaders.isEmpty else {
            return
        }

        initializeDefenseSystem()

        defensiveAlarm = min(
            1.0,
            max(defensiveAlarm, 0.85)
        )

        for index in defenseCells.indices {
            defenseCells[index].alarm = min(
                1.0,
                defenseCells[index].alarm + 0.6
            )

            defenseCells[index].defenderSignal = 1.0
        }

        for index in ants.indices {
            guard !ants[index].hasFood else {
                continue
            }

            var nearestInvader: ColonyInvader?
            var bestDistance = Double.infinity

            for invader in activeInvaders {
                let distance = distance(
                    x1: ants[index].x,
                    y1: ants[index].y,
                    x2: invader.x,
                    y2: invader.y
                )

                if distance < bestDistance {
                    bestDistance = distance
                    nearestInvader = invader
                }
            }

            guard let target = nearestInvader else {
                continue
            }

            ants[index].defending = true
            ants[index].defenseTargetID = target.id
            ants[index].state = .defending
        }
    }

    // MARK: - Public food controls

    var manualFoodDropCeiling: Int {
        maximumFoodSources + 15
    }

    var canAddFoodNow: Bool {
        foodSources.count < manualFoodDropCeiling
    }

    func addFoodNow() {
        guard canAddFoodNow else {
            return
        }

        let count = max(1, min(5, ants.count / 250))

        for _ in 0..<count {
            createFoodSource()
        }
    }

    // MARK: - Statistics

    var averageAntEnergy: Double {
        guard !ants.isEmpty else {
            return 0
        }

        return ants.reduce(0.0) {
            $0 + $1.energy
        } / Double(ants.count)
    }

    var totalFoodRemaining: Double {
        foodSources.reduce(0.0) {
            $0 + $1.amount
        }
    }

    var nestCellCount: Int {
        cells.reduce(into: 0) { count, cell in
            if cell.terrain == .nest ||
                cell.terrain == .tunnel ||
                cell.terrain == .storage {
                count += 1
            }
        }
    }

    var storageCellCount: Int {
        storageCellTotal
    }

    var tunnelCellCount: Int {
        cells.reduce(into: 0) { count, cell in
            if cell.terrain == .tunnel {
                count += 1
            }
        }
    }

    var searchingCount: Int {
        ants.reduce(into: 0) { count, ant in
            if ant.state == .searching {
                count += 1
            }
        }
    }

    var returningCount: Int {
        ants.reduce(into: 0) { count, ant in
            if ant.state == .returning {
                count += 1
            }
        }
    }

    var restingCount: Int {
        ants.reduce(into: 0) { count, ant in
            if ant.state == .resting {
                count += 1
            }
        }
    }

    var exploringCount: Int {
        ants.reduce(into: 0) { count, ant in
            if ant.state == .exploring {
                count += 1
            }
        }
    }

    var buildingCount: Int {
        ants.reduce(into: 0) { count, ant in
            if ant.state == .building {
                count += 1
            }
        }
    }

    var defendingCount: Int {
        ants.reduce(into: 0) { count, ant in
            if ant.state == .defending {
                count += 1
            }
        }
    }

    var populationProgress: Double {
        Double(ants.count) / Double(maximumPopulation)
    }

    var foodPriorityStatus: String {
        if criticalFoodEmergency {
            return "CRITICAL — RETURN TO NEST"
        }

        if foodEmergencyActive {
            return "LOW FOOD — BROOD CARE PRIORITY"
        }

        if foodReserveRatio < 0.60 {
            return "FOOD RECOVERY"
        }

        return "STABLE"
    }
}

// MARK: - Defense System

@MainActor
extension AntColonySimulation {

    func stepDefenseSystem() {
        initializeDefenseSystem()

        guard defenseCells.count == cells.count else {
            return
        }

        defenseGeneration += 1

        spawnInvadersIfNeeded()
        moveInvaders()
        updateInvaderOccupancy()
        propagateThreat()
        calculateColonyThreat()
        updateDefensiveSignals()
        recruitDefenders()
        moveDefendingAnts()
        resolveDefensiveContacts()
        reinforceColony()
        dissipateDefenseField()
        removeDefeatedInvaders()
        calculateDefensiveAlarm()

        defendersActive = ants.reduce(into: 0) { count, ant in
            if ant.defending {
                count += 1
            }
        }
    }

    private func randomInvaderType() -> InvaderType {
        let weightedTypes: [(InvaderType, Double)] = [
            (.rivalAnt, InvaderType.rivalAnt.spawnWeight),
            (.worm, InvaderType.worm.spawnWeight),
            (.cockroach, InvaderType.cockroach.spawnWeight),
            (.spider, InvaderType.spider.spawnWeight),
            (.mouse, InvaderType.mouse.spawnWeight)
        ]

        let totalWeight = weightedTypes.reduce(0.0) {
            $0 + $1.1
        }

        guard totalWeight > 0 else {
            return .rivalAnt
        }

        var randomValue = Double.random(in: 0..<totalWeight)

        for (type, weight) in weightedTypes {
            randomValue -= weight

            if randomValue <= 0 {
                return type
            }
        }

        return .rivalAnt
    }

    private func spawnInvadersIfNeeded() {
        guard defenseGeneration >= nextInvaderGeneration,
              invaders.count < maximumInvaders else {
            return
        }

        let colonyPressure = cachedPopulationPressure
        let baseChance = 0.02 + colonyPressure * 0.02

        guard Double.random(in: 0...1) < baseChance else {
            nextInvaderGeneration = defenseGeneration + Int.random(in: 10...24)
            return
        }

        let spawnCount = defenseGeneration < 150
            ? 1
            : Int.random(in: 1...2)

        for _ in 0..<spawnCount {
            guard invaders.count < maximumInvaders,
                  let location = randomInvaderEntry() else {
                continue
            }

            invaders.append(
                ColonyInvader(
                    type: randomInvaderType(),
                    x: location.x,
                    y: location.y
                )
            )
        }

        nextInvaderGeneration = defenseGeneration + Int.random(in: 18...40)
    }

    private func randomInvaderEntry() -> (x: Double, y: Double)? {
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

            let dx = Double(x - nestCenterX)
            let dy = Double(y - nestCenterY)

            guard dx * dx + dy * dy > 169.0 else {
                continue
            }

            guard cells[indexFor(x, y)].terrain != .obstacle else {
                continue
            }

            return (Double(x), Double(y))
        }

        return nil
    }

    private func updateInvaderOccupancy() {
        for index in defenseCells.indices {
            defenseCells[index].occupiedByInvader = false
        }

        for invader in invaders where invader.alive && invader.health > 0 {
            let x = Int(clamp(invader.x.rounded(), 0, Double(width - 1)))
            let y = Int(clamp(invader.y.rounded(), 0, Double(height - 1)))
            let index = indexFor(x, y)

            guard defenseCells.indices.contains(index) else {
                continue
            }

            defenseCells[index].occupiedByInvader = true
            defenseCells[index].threat = 1.0
            defenseCells[index].alarm = 1.0
            defenseCells[index].defenderSignal = 1.0
        }
    }

    private func propagateThreat() {
        for index in defenseCells.indices {
            defenseCells[index].threat *= 0.82
        }

        for invader in invaders where invader.alive && invader.health > 0 {
            let radius = threatRadius(for: invader.type)
            let centerX = Int(invader.x.rounded())
            let centerY = Int(invader.y.rounded())

            for dy in -radius...radius {
                for dx in -radius...radius {
                    let x = centerX + dx
                    let y = centerY + dy

                    guard x >= 0, x < width,
                          y >= 0, y < height else {
                        continue
                    }

                    let distanceSquared = Double(dx * dx + dy * dy)

                    guard distanceSquared <= Double(radius * radius) else {
                        continue
                    }

                    let distance = sqrt(distanceSquared)
                    let falloff = 1.0 - distance / Double(radius + 1)
                    let index = indexFor(x, y)

                    defenseCells[index].threat = min(
                        1.0,
                        defenseCells[index].threat
                            + invader.type.threat * falloff * 0.18
                    )
                }
            }
        }
    }

    private func threatRadius(for type: InvaderType) -> Int {
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

    private func updateDefensiveSignals() {
        var totalAlarm = 0.0

        for y in 0..<height {
            for x in 0..<width {
                let index = indexFor(x, y)

                let localThreat = min(
                    1.0,
                    max(0.0, defenseCells[index].threat)
                )

                var neighboringAlarm = 0.0

                for neighbor in neighborCache[index] {
                    neighboringAlarm += defenseCells[neighbor].alarm
                }

                let alarm = min(
                    1.0,
                    localThreat * 0.65
                        + min(0.35, neighboringAlarm * 0.045)
                )

                defenseCells[index].alarm = alarm
                totalAlarm += alarm
            }
        }

        defensiveAlarm = min(
            1.0,
            totalAlarm / Double(max(1, cells.count)) * 8.0
                + colonyAlarm * 0.50
        )
    }

    private func calculateColonyThreat() {
        var totalThreat = 0.0
        var threatenedCells = 0

        for cell in defenseCells {
            let threat = min(1.0, max(0.0, cell.threat))

            guard threat > 0.01 else {
                continue
            }

            totalThreat += threat
            threatenedCells += 1
        }

        colonyAlarm = threatenedCells > 0
            ? min(1.0, totalThreat / Double(threatenedCells))
            : 0.0
    }

    private func recruitDefenders() {
        guard !invaders.isEmpty else {
            return
        }

        for antIndex in ants.indices {
            if ants[antIndex].defending,
               let targetID = ants[antIndex].defenseTargetID {
                let targetStillAlive = invaders.contains {
                    $0.id == targetID && $0.alive && $0.health > 0
                }

                if targetStillAlive {
                    continue
                }

                ants[antIndex].defending = false
                ants[antIndex].defenseTargetID = nil

                if ants[antIndex].state == .defending {
                    ants[antIndex].state = .searching
                }
            }

            guard !ants[antIndex].hasFood,
                  ants[antIndex].energy > 15 else {
                continue
            }

            let antX = ants[antIndex].x
            let antY = ants[antIndex].y

            var selectedInvader: ColonyInvader?
            var selectedDistance = Double.infinity

            for invader in invaders where invader.alive && invader.health > 0 {
                let targetDistance = distance(
                    x1: antX,
                    y1: antY,
                    x2: invader.x,
                    y2: invader.y
                )

                guard targetDistance <= recruitmentRadius else {
                    continue
                }

                let x = Int(clamp(invader.x.rounded(), 0, Double(width - 1)))
                let y = Int(clamp(invader.y.rounded(), 0, Double(height - 1)))
                let defenseIndex = indexFor(x, y)
                let cell = defenseCells[defenseIndex]

                guard cell.threat > 0 ||
                        cell.alarm > 0 ||
                        cell.defenderSignal > 0 else {
                    continue
                }

                if targetDistance < selectedDistance {
                    selectedDistance = targetDistance
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

    private func moveDefendingAnts() {
        for antIndex in ants.indices {
            guard ants[antIndex].defending,
                  let targetID = ants[antIndex].defenseTargetID else {
                continue
            }

            guard let invader = invaders.first(where: {
                $0.id == targetID && $0.alive && $0.health > 0
            }) else {
                ants[antIndex].defending = false
                ants[antIndex].defenseTargetID = nil
                ants[antIndex].state = .searching
                continue
            }

            let oldX = Int(ants[antIndex].x.rounded())
            let oldY = Int(ants[antIndex].y.rounded())

            let dx = invader.x - ants[antIndex].x
            let dy = invader.y - ants[antIndex].y
            let distanceSquared = dx * dx + dy * dy

            if distanceSquared > 1.0 {
                moveTowardDefense(
                    ant: &ants[antIndex],
                    targetX: invader.x,
                    targetY: invader.y
                )

                ants[antIndex].energy = max(
                    0,
                    ants[antIndex].energy - movementEnergyCost
                )
            } else {
                resolveAntDefensiveContact(
                    antIndex: antIndex,
                    targetID: targetID
                )
            }

            let newX = Int(ants[antIndex].x.rounded())
            let newY = Int(ants[antIndex].y.rounded())

            updateOccupancy(
                fromOldX: oldX,
                oldY: oldY,
                toNewX: newX,
                newY: newY
            )
        }
    }

    private func moveTowardDefense(
        ant: inout Ant,
        targetX: Double,
        targetY: Double
    ) {
        let dx = targetX - ant.x
        let dy = targetY - ant.y

        guard abs(dx) > 0.0001 || abs(dy) > 0.0001 else {
            ant.directionX = 0
            ant.directionY = 0
            return
        }

        if abs(dx) > abs(dy) {
            ant.directionX = dx > 0 ? 1.0 : -1.0
            ant.directionY = 0
        } else {
            ant.directionX = 0
            ant.directionY = dy > 0 ? 1.0 : -1.0
        }

        let newX = ant.x + ant.directionX
        let newY = ant.y + ant.directionY

        guard isDefenseWalkable(x: newX, y: newY) else {
            return
        }

        ant.x = newX
        ant.y = newY
    }

    private func moveInvaders() {
        for index in invaders.indices {
            guard invaders[index].alive,
                  invaders[index].health > 0 else {
                continue
            }

            invaders[index].age += 1

            let dx = Double(nestCenterX) - invaders[index].x
            let dy = Double(nestCenterY) - invaders[index].y
            let inverseDistance = 1.0 / max(0.001, sqrt(dx * dx + dy * dy))

            let directionX = dx * inverseDistance
            let directionY = dy * inverseDistance

            invaders[index].directionX = directionX
            invaders[index].directionY = directionY

            let spawnRamp = min(
                1.0,
                Double(invaders[index].age) / 18.0
            )

            let speed = invaders[index].type.speed
                * (0.40 + 0.60 * spawnRamp)

            let newX = invaders[index].x + directionX * speed
            let newY = invaders[index].y + directionY * speed

            if isDefenseWalkable(x: newX, y: newY) {
                invaders[index].x = newX
                invaders[index].y = newY
            }
        }
    }

    private func resolveDefensiveContacts() {
        guard !ants.isEmpty,
              !invaders.isEmpty,
              !defenseCells.isEmpty else {
            return
        }

        for antIndex in ants.indices {
            guard ants[antIndex].defending,
                  let targetID = ants[antIndex].defenseTargetID else {
                continue
            }

            guard let invaderIndex = invaders.firstIndex(where: {
                $0.id == targetID && $0.alive && $0.health > 0
            }) else {
                ants[antIndex].defending = false
                ants[antIndex].defenseTargetID = nil
                ants[antIndex].state = .searching
                continue
            }

            let dx = invaders[invaderIndex].x - ants[antIndex].x
            let dy = invaders[invaderIndex].y - ants[antIndex].y

            guard dx * dx + dy * dy <= 1.0 else {
                continue
            }

            applyDefenseDamage(
                antIndex: antIndex,
                invaderIndex: invaderIndex
            )
        }
    }

    private func resolveAntDefensiveContact(
        antIndex: Int,
        targetID: UUID
    ) {
        guard ants.indices.contains(antIndex),
              let invaderIndex = invaders.firstIndex(where: {
                  $0.id == targetID && $0.alive && $0.health > 0
              }) else {
            return
        }

        let dx = invaders[invaderIndex].x - ants[antIndex].x
        let dy = invaders[invaderIndex].y - ants[antIndex].y

        guard dx * dx + dy * dy <= 1.0 else {
            return
        }

        applyDefenseDamage(
            antIndex: antIndex,
            invaderIndex: invaderIndex
        )
    }

    private func applyDefenseDamage(
        antIndex: Int,
        invaderIndex: Int
    ) {
        guard ants.indices.contains(antIndex),
              invaders.indices.contains(invaderIndex) else {
            return
        }

        let x = Int(clamp(
            invaders[invaderIndex].x.rounded(),
            0,
            Double(width - 1)
        ))

        let y = Int(clamp(
            invaders[invaderIndex].y.rounded(),
            0,
            Double(height - 1)
        ))

        let defenseIndex = indexFor(x, y)

        let defenseStrength = defenseCells.indices.contains(defenseIndex)
            ? max(0.0, defenseCells[defenseIndex].defenseStrength)
            : 0.0

        let damage = 2.5 * (1.0 + defenseStrength)

        invaders[invaderIndex].health = max(
            0,
            invaders[invaderIndex].health - damage
        )

        ants[antIndex].energy = max(
            0,
            ants[antIndex].energy - 0.5
        )

        if invaders[invaderIndex].health <= 0 {
            invaders[invaderIndex].alive = false
            invadersDefeated += 1

            ants[antIndex].defending = false
            ants[antIndex].defenseTargetID = nil
            ants[antIndex].state = .searching
        }
    }

    private func reinforceColony() {
        for y in 0..<height {
            for x in 0..<width {
                let index = indexFor(x, y)
                let alarm = defenseCells[index].alarm
                let threat = defenseCells[index].threat
                let builtCell = isColonyCell(x: x, y: y)

                if builtCell {
                    defenseCells[index].defenseStrength = min(
                        1.0,
                        defenseCells[index].defenseStrength + alarm * 0.16
                    )
                }

                defenseCells[index].defenderSignal = min(
                    1.0,
                    threat * 0.7 + alarm * 0.3
                )

                if alarm > defenseCriticalThreshold,
                   builtCell {
                    defenseCells[index].blocked = min(
                        1.0,
                        defenseCells[index].blocked + 0.05
                    )
                }
            }
        }
    }

    private func dissipateDefenseField() {
        for index in defenseCells.indices {
            defenseCells[index].alarm *= 0.93
            defenseCells[index].defenderSignal *= 0.95
            defenseCells[index].defenseStrength *= 0.998
            defenseCells[index].blocked *= 0.996
        }
    }

    private func removeDefeatedInvaders() {
        let previousCount = invaders.count

        invaders.removeAll {
            !$0.alive || $0.health <= 0
        }

        let removedCount = previousCount - invaders.count

        if removedCount > 0 {
            defensiveAlarm = max(
                0,
                defensiveAlarm - Double(removedCount) * 0.04
            )
        }
    }

    private func calculateDefensiveAlarm() {
        var breaches = 0
        let breachDistanceSquared = breachRadius * breachRadius

        for invader in invaders where invader.alive && invader.health > 0 {
            let dx = invader.x - Double(nestCenterX)
            let dy = invader.y - Double(nestCenterY)

            if dx * dx + dy * dy < breachDistanceSquared {
                breaches += 1
            }
        }

        invaderBreaches = breaches
    }

    private func isDefenseWalkable(x: Double, y: Double) -> Bool {
        guard x >= 1,
              x < Double(width - 1),
              y >= 1,
              y < Double(height - 1) else {
            return false
        }

        let cellX = Int(x.rounded())
        let cellY = Int(y.rounded())

        guard cellX >= 0, cellX < width,
              cellY >= 0, cellY < height else {
            return false
        }

        return cells[indexFor(cellX, cellY)].terrain != .obstacle
    }

    private func isColonyCell(x: Int, y: Int) -> Bool {
        guard x >= 0, x < width,
              y >= 0, y < height else {
            return false
        }

        let terrain = cells[indexFor(x, y)].terrain

        return terrain == .nest ||
            terrain == .tunnel ||
            terrain == .storage
    }

    func addInvader(type: InvaderType) {
        guard invaders.count < maximumInvaders,
              let location = randomInvaderEntry() else {
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

    var activeInvaderCount: Int {
        invaders.count
    }

    var criticalDefenseCells: Int {
        defenseCells.reduce(into: 0) { count, cell in
            if cell.alarm > defenseCriticalThreshold {
                count += 1
            }
        }
    }

    var averageDefenseStrength: Double {
        guard !defenseCells.isEmpty else {
            return 0
        }

        return defenseCells.reduce(0.0) {
            $0 + $1.defenseStrength
        } / Double(defenseCells.count)
    }

    var defenseStatus: String {
        if invaders.isEmpty {
            return "SECURE"
        }

        if defensiveAlarm > defenseCriticalThreshold {
            return "CRITICAL"
        }

        if defensiveAlarm > defenseActivationThreshold {
            return "DEFENDING"
        }

        return "ALERT"
    }
}
