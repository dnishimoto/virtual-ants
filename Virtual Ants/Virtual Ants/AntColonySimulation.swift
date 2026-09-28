///
//  AntColonySimulation.swift
//  Virtual Ants
//
//  Tier-1 optimized:
//  - local foodDirection via foodCellLookup
//  - incremental occupancy
//  - indexed storage cells
//  - incremental storageCellTotal
//  - cached population pressure
//  - defense every 3 steps
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class AntColonySimulation: ObservableObject {

    // MARK: Energy
    private var storageCellIndices: [Int] = []
    private var storageCellTotal = 0
    private let lowEnergyReturnThreshold = 30.0
    private let recoveredEnergyThreshold = 75.0
    private let maximumFoodPerRecoveryStep = 2.0
    private let personalEnergyPerFoodUnit = 7.0
    private let reproductionInterval = 3
    private let movementEnergyCost = 0.45

    // MARK: Defense constants

    let detectionRadius = 20.0
    let breachRadius = 10.0
    let recruitmentRadius = 11.0
    let spawnChance = 0.75

    private let maximumInvaders = 12
    private let defenseActivationThreshold = 0.18
    private let defenseCriticalThreshold = 0.72

    // MARK: Performance caches

    private var foodCellLookup: [Int] = []
    private var neighborCache: [[Int]] = []

    private let densityUpdateInterval = 2
    private let pheromoneUpdateInterval = 2
    private let constructionUpdateInterval = 2
    private let foodCleanupInterval = 4
    private let foodSenseRadius = 8

    private var defenseStepCounter = 0
    private var defenseInitialized = false
    private var nextInvaderGeneration = 2
    private var cachedPopulationPressure = 0.0

    // MARK: Published

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

    // MARK: World

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

    var broodCareLevel: Double {
        let foodRatio = storedFood / max(storageCapacity, 1.0)
        switch foodRatio {
        case ..<0.15: return 0.10
        case 0.15..<0.45: return 0.40
        case 0.45..<0.75: return 0.75
        default: return 1.0
        }
    }

    // MARK: Init

    init(width: Int = 100, height: Int = 65) {
        self.width = width
        self.height = height
        self.nestCenterX = width / 2
        self.nestCenterY = height / 2
        self.cells = Array(repeating: ColonyCell(), count: width * height)
        self.colonyEnergy = Double(initialPopulation) * 8.0
        foodCellLookup = Array(repeating: -1, count: width * height)
        buildNeighborCache()
        buildInitialWorld()
        createInitialColony()
        createInitialFood()
        rebuildFoodLookup()
        rebuildCellOccupancy()
        rebuildStorageIndex()
    }

   

    @inline(__always)
    private func finishMove(index: Int, oldX: Int, oldY: Int) {
        updateOccupancy(
            fromOldX: oldX,
            oldY: oldY,
            toNewX: Int(ants[index].x.rounded()),
            newY: Int(ants[index].y.rounded())
        )
    }

    private func rebuildCellOccupancy() {
        for i in cells.indices { cells[i].antCount = 0 }
        for ant in ants {
            let x = Int(ant.x.rounded())
            let y = Int(ant.y.rounded())
            guard x >= 0, x < width, y >= 0, y < height else { continue }
            cells[indexFor(x, y)].antCount += 1
        }
    }

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
                    if dx == 0 && dy == 0 { continue }
                    let nx = x + dx
                    let ny = y + dy
                    guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                    neighbors.append(ny * width + nx)
                }
            }
            neighborCache[index] = neighbors
        }
    }
   
      private func depositIntoStorageChambers(nearX: Double, nearY: Double, amount: Double) {
        guard amount > 0, !storageCellIndices.isEmpty else { return }
        var remaining = amount

        let sorted = storageCellIndices.sorted {
            let x0 = Double($0 % width), y0 = Double($0 / width)
            let x1 = Double($1 % width), y1 = Double($1 / width)
            let dx0 = x0 - nearX, dy0 = y0 - nearY
            let dx1 = x1 - nearX, dy1 = y1 - nearY
            return dx0 * dx0 + dy0 * dy0 < dx1 * dx1 + dy1 * dy1
        }

        for index in sorted {
            guard remaining > 0 else { break }
            let room = chamberFoodCapacity - cells[index].storedFood
            guard room > 0 else { continue }
            let deposit = min(room, remaining)
            cells[index].storedFood += deposit
            remaining -= deposit
        }
    }

    private func withdrawFromStorageChambers(amount: Double) {
        guard amount > 0, !storageCellIndices.isEmpty else { return }
        var remaining = amount

        let sorted = storageCellIndices.sorted {
            cells[$0].storedFood > cells[$1].storedFood
        }

        for index in sorted {
            guard remaining > 0 else { break }
            let w = min(cells[index].storedFood, remaining)
            cells[index].storedFood -= w
            remaining -= w
        }
    }

    private func rebuildFoodLookup() {
        foodCellLookup = Array(repeating: -1, count: width * height)
        for (i, source) in foodSources.enumerated() where !source.depleted {
            let index = indexFor(source.x, source.y)
            if foodCellLookup.indices.contains(index) {
                foodCellLookup[index] = i
            }
        }
    }

    @inline(__always)
    private func foodIndexAt(x: Int, y: Int) -> Int? {
        guard x >= 0, x < width, y >= 0, y < height else { return nil }
        let foodIndex = foodCellLookup[indexFor(x, y)]
        return foodIndex >= 0 ? foodIndex : nil
    }

    // MARK: Storage index

    private func rebuildStorageIndex() {
        storageCellIndices.removeAll(keepingCapacity: true)
        for i in cells.indices where cells[i].terrain == .storage {
            storageCellIndices.append(i)
        }
        storageCellTotal = storageCellIndices.count
        updateStorageCapacityFromTotal()
    }

    private func registerStorageCell(at index: Int) {
        guard !storageCellIndices.contains(index) else { return }
        storageCellIndices.append(index)
        storageCellTotal = storageCellIndices.count
        storageChambersBuilt += 1
        updateStorageCapacityFromTotal()
    }

    private func updateStorageCapacityFromTotal() {
        storageCapacity = 220.0 + Double(storageCellTotal) * chamberFoodCapacity
        storedFood = min(storedFood, storageCapacity)
    }

    private func updateStorageCapacity() {
        updateStorageCapacityFromTotal()
    }

  
  

    private func buildInitialWorld() {
        for y in 0..<height {
            for x in 0..<width {
                let dx = Double(x - nestCenterX)
                let dy = Double(y - nestCenterY)
                let distSq = dx * dx + dy * dy
                let index = indexFor(x, y)
                if distSq <= 36 {
                    cells[index].terrain = .nest
                    cells[index].nestStrength = 1.0
                } else if abs(dx) < 1.5 || abs(dy) < 1.5 {
                    cells[index].terrain = .tunnel
                    cells[index].construction = 1.0
                    cells[index].nestStrength = 0.8
                }
            }
        }
        var obstacles = 0
        while obstacles < 85 {
            let x = Int.random(in: 3..<(width - 3))
            let y = Int.random(in: 3..<(height - 3))
            let dx = Double(x - nestCenterX)
            let dy = Double(y - nestCenterY)
            guard dx * dx + dy * dy > 169 else { continue }
            let index = indexFor(x, y)
            guard cells[index].terrain == .empty else { continue }
            cells[index].terrain = .obstacle
            obstacles += 1
        }
        updateStorageCapacityFromTotal()
    }

    private func createInitialColony() {
        ants.reserveCapacity(maximumPopulation)
        for _ in 0..<initialPopulation {
            let angle = Double.random(in: 0...(Double.pi * 2))
            let radius = sqrt(Double.random(in: 0...1)) * 8.0
            ants.append(
                Ant(
                    x: clamp(Double(nestCenterX) + cos(angle) * radius, 1, Double(width - 2)),
                    y: clamp(Double(nestCenterY) + sin(angle) * radius, 1, Double(height - 2)),
                    state: .resting,
                    energy: Double.random(in: 75...100),
                    pheromoneSensitivity: Double.random(in: 0.75...1.25),
                    explorationBias: Double.random(in: 0.75...1.25)
                )
            )
        }
    }

    private func createInitialFood() {
        for _ in 0..<12 { createFoodSource() }
        nextFoodGeneration = generation + Int.random(in: 12...25)
        rebuildFoodLookup()
    }

    // MARK: Step

    func step() {
        guard colonyAlive else { return }
        generation += 1
        cachedPopulationPressure = min(1.0, Double(ants.count) / Double(maximumPopulation))

        defenseStepCounter += 1
        if defenseStepCounter >= 3 {
            defenseStepCounter = 0
            stepDefenseSystem()
        }

        generateFoodIfNeeded()
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

        if generation % foodCleanupInterval == 0 {
            removeDepletedFood()
        }
        evaluateColony()
    }

    // MARK: Food generation

    private func generateFoodIfNeeded() {
        guard generation >= nextFoodGeneration else { return }
        let population = max(ants.count, 1)
        let target = min(maximumFoodSources, max(8, Int(ceil(Double(population) / 30.0))))
        let needed = max(0, target - foodSources.count)
        if needed > 0 {
            let lo = min(needed, max(2, Int(ceil(Double(population) / 60.0))))
            let hi = min(needed, max(lo, Int(ceil(Double(population) / 30.0))))
            for _ in 0..<Int.random(in: lo...hi) {
                guard foodSources.count < maximumFoodSources else { break }
                createFoodSource()
            }
        }
        let intervalLow = max(3, 10 - population / 100)
        let intervalHigh = max(intervalLow + 2, 16 - population / 120)
        nextFoodGeneration = generation + Int.random(in: intervalLow...intervalHigh)
    }

    private func createFoodSource() {
        guard let location = randomFoodLocation() else { return }
        let type = chooseFoodType()
        let pf = min(2.0, max(0.75, Double(max(ants.count, 1)) / Double(initialPopulation)))
        let amount: Double
        switch type {
        case .seed: amount = Double.random(in: 55...150) * pf
        case .fruit: amount = Double.random(in: 28...90) * pf
        case .insect: amount = Double.random(in: 10...40) * pf
        case .nectar: amount = Double.random(in: 36...115) * pf
        }
        foodSources.append(
            FoodSource(
                x: location.x, y: location.y, type: type,
                amount: amount, maximumAmount: amount,
                regenerationRate: max(0.5, amount * 0.02)
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
        return FoodType.allCases.randomElement()!
    }

    private func randomFoodLocation() -> (x: Int, y: Int)? {
        for _ in 0..<100 {
            let x = Int.random(in: 4..<(width - 4))
            let y = Int.random(in: 4..<(height - 4))
            let dx = Double(x - nestCenterX)
            let dy = Double(y - nestCenterY)
            guard dx * dx + dy * dy > 144 else { continue }
            let index = indexFor(x, y)
            guard cells[index].terrain == .empty else { continue }
            if foodCellLookup[index] >= 0 { continue }
            return (x, y)
        }
        return nil
    }

    private func moveAnts() {
        let pressure = cachedPopulationPressure

        for i in ants.indices {
            let oldX = Int(ants[i].x.rounded())
            let oldY = Int(ants[i].y.rounded())
            ants[i].age += 1

            let density = localCrowdingFast(atX: oldX, atY: oldY)
            ants[i].energy = max(
                0,
                ants[i].energy - movementCost(
                    state: ants[i].state,
                    density: density,
                    populationPressure: pressure
                )
            )
            if ants[i].energy <= 0 {
                continue
            }

            // Carrying food → return home
            if ants[i].hasFood {
                ants[i].state = .returning
                moveReturningAnt(index: i)
                finishMove(index: i, oldX: oldX, oldY: oldY)
                continue
            }

            // Low energy → go eat
            if ants[i].energy <= lowEnergyReturnThreshold,
               ants[i].state != .returningForFood {
                ants[i].defending = false
                ants[i].defenseTargetID = nil
                ants[i].state = .returningForFood
            }

            if ants[i].state == .returningForFood {
                moveAntToNestForFood(index: i)
                finishMove(index: i, oldX: oldX, oldY: oldY)
                continue
            }

            // Resting in nest: feed, then sometimes leave
            if ants[i].state == .resting {
                if isInsideNest(x: ants[i].x, y: ants[i].y) {
                    feedAntFromStoredFood(index: i)
                    ants[i].energy = min(100, ants[i].energy + 0.20)
                    if ants[i].energy >= recoveredEnergyThreshold,
                       Double.random(in: 0...1) < 0.04 {
                        ants[i].state = .searching
                    }
                } else {
                    ants[i].state = .returningForFood
                }
                finishMove(index: i, oldX: oldX, oldY: oldY)
                continue
            }

            if ants[i].defending {
                ants[i].state = .defending
                finishMove(index: i, oldX: oldX, oldY: oldY)
                continue
            }

            if shouldConstruct(ant: ants[i]) {
                ants[i].state = .building
                moveConstructionAnt(index: i)
                finishMove(index: i, oldX: oldX, oldY: oldY)
                continue
            }

            // Pick up nearby food
            if let foodIndex = foodAt(x: ants[i].x, y: ants[i].y, radius: 1.5) {
                collectFood(antIndex: i, foodIndex: foodIndex)
                finishMove(index: i, oldX: oldX, oldY: oldY)
                continue
            }

            // Forage
            if ants[i].state == .searching || ants[i].state == .exploring {
                moveSearchingAnt(index: i, density: density, populationPressure: pressure)
            } else {
                // Fallback: any other non-handled state still forages
                ants[i].state = .searching
                moveSearchingAnt(index: i, density: density, populationPressure: pressure)
            }

            finishMove(index: i, oldX: oldX, oldY: oldY)
        }

        removeDeadAnts()
    }

    private func moveSearchingAnt(
        index: Int,
        density: Double,
        populationPressure: Double
    ) {
        let ant = ants[index]
        let exploration = max(0.08, ant.explorationBias * (1.0 - populationPressure * 0.65))
        let trailWeight = ant.pheromoneSensitivity * (0.8 + populationPressure * 1.6)

        var vx = 0.0
        var vy = 0.0

        let food = foodDirection(for: ant)
        vx += food.x * 3.0
        vy += food.y * 3.0

        let pheromone = pheromoneDirection(for: ant)
        vx += pheromone.x * trailWeight
        vy += pheromone.y * trailWeight

        if let mx = ant.rememberedFoodX, let my = ant.rememberedFoodY {
            let dx = mx - ant.x
            let dy = my - ant.y
            let distSq = dx * dx + dy * dy
            if distSq > 0.25 && distSq < 1225 {
                let inv = 1.0 / sqrt(distSq)
                vx += dx * inv * 0.35
                vy += dy * inv * 0.35
            }
        }

        let nestDistSq = distanceFromNestSquared(x: ant.x, y: ant.y)
        if nestDistSq < 81 {
            let dx = ant.x - Double(nestCenterX)
            let dy = ant.y - Double(nestCenterY)
            let inv = 1.0 / max(0.001, sqrt(nestDistSq))
            vx += dx * inv * 0.6
            vy += dy * inv * 0.6
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
        let speed = max(0.18, 0.48 - density * 0.025)

        // THIS is what was missing — actually move the ant
        _ = moveAntSafely(
            index: index,
            directionX: direction.x,
            directionY: direction.y,
            speed: speed
        )

        ants[index].state = Double.random(in: 0...1) < 0.003 ? .exploring : .searching
    }
    @inline(__always)
    private func localCrowdingFast(atX cx: Int, atY cy: Int) -> Double {
        var count = 0
        for dy in -2...2 {
            for dx in -2...2 {
                let nx = cx + dx, ny = cy + dy
                guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                count += cells[indexFor(nx, ny)].antCount
            }
        }
        return min(3, Double(count) / 12)
    }

   
   
    private func removeDeadAnts() {
        let before = ants.count
        ants.removeAll { $0.energy <= 0 || $0.age > 6000 }
        let removed = before - ants.count
        deaths += removed
        if removed > 0 {
            rebuildCellOccupancy()
        }
    }
    private func foodDirection(for ant: Ant) -> (x: Double, y: Double) {
        if let mx = ant.rememberedFoodX, let my = ant.rememberedFoodY {
            let dx = mx - ant.x
            let dy = my - ant.y
            let distSq = dx * dx + dy * dy
            if distSq > 0.25 && distSq < 1225 {
                let inv = 1.0 / sqrt(distSq)
                return (dx * inv, dy * inv)
            }
        }

        let cx = Int(ant.x.rounded())
        let cy = Int(ant.y.rounded())
        let r = foodSenseRadius
        let rSq = Double(r * r)
        var vx = 0.0, vy = 0.0

        for dy in -r...r {
            for dx in -r...r {
                guard let fi = foodIndexAt(x: cx + dx, y: cy + dy) else { continue }
                guard foodSources.indices.contains(fi), !foodSources[fi].depleted else { continue }

                let s = foodSources[fi]
                let fdx = Double(s.x) - ant.x
                let fdy = Double(s.y) - ant.y
                let distSq = fdx * fdx + fdy * fdy
                guard distSq > 0.0001, distSq <= rSq else { continue }

                let d = sqrt(distSq)
                let w = s.type.attraction * min(3, max(0.2, s.amount / 20)) / max(d, 1)
                vx += (fdx / d) * w
                vy += (fdy / d) * w
            }
        }
        return normalized(x: vx, y: vy)
    }
 

    private func moveReturningAnt(index: Int) {
        let ant = ants[index]
        let dx = Double(nestCenterX) - ant.x
        let dy = Double(nestCenterY) - ant.y
        let inv = 1.0 / max(0.001, sqrt(dx * dx + dy * dy))
        let trail = nestDirection(for: ant)
        let direction = normalized(
            x: dx * inv * 0.75 + trail.x * 0.25,
            y: dy * inv * 0.75 + trail.y * 0.25
        )
        _ = moveAntSafely(index: index, directionX: direction.x, directionY: direction.y, speed: 0.60)
        depositReturningPheromone(ant: ants[index])
        if isInsideNest(x: ants[index].x, y: ants[index].y) {
            deliverFood(antIndex: index)
        }
    }
    private func crowdingDirectionFast(cx: Int, cy: Int) -> (x: Double, y: Double) {
        var vx = 0.0, vy = 0.0
        for dy in -2...2 {
            for dx in -2...2 {
                if dx == 0 && dy == 0 { continue }
                let nx = cx + dx, ny = cy + dy
                guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                let c = cells[indexFor(nx, ny)].antCount
                guard c > 0 else { continue }
                let inv = 1.0 / sqrt(Double(dx * dx + dy * dy))
                vx -= Double(dx) * inv * Double(c)
                vy -= Double(dy) * inv * Double(c)
            }
        }
        return normalized(x: vx, y: vy)
    }

    private func moveAntToNestForFood(index: Int) {
        guard ants.indices.contains(index) else { return }
        let ant = ants[index]
        let dx = Double(nestCenterX) - ant.x
        let dy = Double(nestCenterY) - ant.y
        let inv = 1.0 / max(0.001, sqrt(dx * dx + dy * dy))
        let trail = nestDirection(for: ant)
        let direction = normalized(
            x: dx * inv * 0.85 + trail.x * 0.15,
            y: dy * inv * 0.85 + trail.y * 0.15
        )
        moveAntSafely(index: index, directionX: direction.x, directionY: direction.y, speed: 0.55)
        if isInsideNest(x: ants[index].x, y: ants[index].y) {
            ants[index].state = .resting
        }
    }

    private func feedAntFromStoredFood(index: Int) {
        guard ants.indices.contains(index) else { return }
        guard isInsideNest(x: ants[index].x, y: ants[index].y) else { return }
        guard ants[index].energy < recoveredEnergyThreshold, storedFood > 0 else { return }
        let foodConsumed = min(
            maximumFoodPerRecoveryStep,
            (recoveredEnergyThreshold - ants[index].energy) / personalEnergyPerFoodUnit,
            storedFood
        )
        guard foodConsumed > 0 else { return }
        storedFood -= foodConsumed
        ants[index].energy = min(100, ants[index].energy + foodConsumed * personalEnergyPerFoodUnit)
    }


    private func shouldConstruct(ant: Ant) -> Bool {
        guard !ant.hasFood else { return false }
        let required = Double(ants.count) * 0.20
        let current = Double(nestCellCount)
        let foodRatio = min(1.0, storedFood / max(storageCapacity, 1.0))
        let growth = min(1.0, currentReproductionRate / 0.113)
        if current < required * (1.0 + growth * 0.6) {
            return Double.random(in: 0...1) < (0.035 + growth * 0.045)
        }
        if foodRatio > 0.40 {
            return Double.random(in: 0...1) < (0.010 + (foodRatio - 0.40) * 0.045)
        }
        return Double.random(in: 0...1) < (0.004 * max(0.25, foodRatio))
    }

    private func moveConstructionAnt(index: Int) {
        guard let target = nearestConstructionSite(from: ants[index]) else {
            ants[index].state = .searching
            return
        }
        let dx = target.x - ants[index].x
        let dy = target.y - ants[index].y
        let distSq = dx * dx + dy * dy
        let inv = 1.0 / max(0.001, sqrt(distSq))
        _ = moveAntSafely(index: index, directionX: dx * inv, directionY: dy * inv, speed: 0.30)
        if distSq < 3.24 {
            buildAt(x: target.x, y: target.y)
            ants[index].state = .resting
        }
    }

    private func nearestConstructionSite(from ant: Ant) -> (x: Double, y: Double)? {
        var best: (x: Double, y: Double)?
        var bestDistance = Double.infinity
        let r = 18
        let cx = Int(ant.x.rounded()), cy = Int(ant.y.rounded())
        let minX = max(1, cx - r), maxX = min(width - 2, cx + r)
        let minY = max(1, cy - r), maxY = min(height - 2, cy + r)
        guard minX <= maxX, minY <= maxY else { return nil }
        for y in minY...maxY {
            for x in minX...maxX {
                let index = indexFor(x, y)
                guard cells[index].terrain == .empty else { continue }
                guard numberOfBuiltNeighbors(x: x, y: y) >= 2 else { continue }
                let dx = Double(x) - ant.x, dy = Double(y) - ant.y
                let d = dx * dx + dy * dy
                if d < bestDistance {
                    bestDistance = d
                    best = (Double(x), Double(y))
                }
            }
        }
        return best
    }

    private func buildAt(x: Double, y: Double) {
        let ix = Int(x.rounded()), iy = Int(y.rounded())
        guard ix >= 1, ix < width - 1, iy >= 1, iy < height - 1 else { return }
        let index = indexFor(ix, iy)
        guard cells[index].terrain == .empty else { return }
        guard numberOfBuiltNeighbors(x: ix, y: iy) >= 2 else { return }
        let storageDemand = storedFood / max(storageCapacity, 1)
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
    }

    private func performColonyConstruction() {
        constructionCandidates.removeAll(keepingCapacity: true)
        let desired = max(2, Int(3 + cachedPopulationPressure * 8))
        for _ in 0..<desired {
            let x = Int.random(in: 2..<(width - 2))
            let y = Int.random(in: 2..<(height - 2))
            let index = indexFor(x, y)
            guard cells[index].terrain == .empty else { continue }
            if numberOfBuiltNeighbors(x: x, y: y) >= 2 {
                constructionCandidates.insert(index)
            }
        }
    }

    private func numberOfBuiltNeighbors(x: Int, y: Int) -> Int {
        let index = indexFor(x, y)
        guard neighborCache.indices.contains(index) else { return 0 }
        var count = 0
        for n in neighborCache[index] {
            let t = cells[n].terrain
            if t == .nest || t == .tunnel || t == .storage { count += 1 }
        }
        return count
    }

    // MARK: Collect / deliver

    private func foodAt(x: Double, y: Double, radius: Double) -> Int? {
        let cx = Int(x.rounded()), cy = Int(y.rounded())
        let r = max(1, Int(radius.rounded()))
        var best: Int?, bestDist = radius * radius
        for dy in -r...r {
            for dx in -r...r {
                guard let fi = foodIndexAt(x: cx + dx, y: cy + dy) else { continue }
                guard foodSources.indices.contains(fi), !foodSources[fi].depleted else { continue }
                let ddx = Double(foodSources[fi].x) - x
                let ddy = Double(foodSources[fi].y) - y
                let d = ddx * ddx + ddy * ddy
                if d <= bestDist { bestDist = d; best = fi }
            }
        }
        return best
    }

    private func collectFood(antIndex: Int, foodIndex: Int) {
        guard foodSources.indices.contains(foodIndex) else { return }
        let available = foodSources[foodIndex].amount
        guard available > 0 else { return }
        let type = foodSources[foodIndex].type
        let amount = min(4.0 / type.collectionDifficulty, available)
        foodSources[foodIndex].amount -= amount
        if foodSources[foodIndex].amount <= 0.01 {
            foodSources[foodIndex].amount = 0
            let ci = indexFor(foodSources[foodIndex].x, foodSources[foodIndex].y)
            if foodCellLookup.indices.contains(ci) { foodCellLookup[ci] = -1 }
        }
        ants[antIndex].carriedFood += amount
        ants[antIndex].carriedFoodType = type
        ants[antIndex].state = .returning
        ants[antIndex].rememberedFoodX = Double(foodSources[foodIndex].x)
        ants[antIndex].rememberedFoodY = Double(foodSources[foodIndex].y)
        let cellIndex = indexFor(foodSources[foodIndex].x, foodSources[foodIndex].y)
        cells[cellIndex].foodPheromone = min(25, cells[cellIndex].foodPheromone + 3.0 * type.attraction)
    }

    private func deliverFood(antIndex: Int) {
        guard ants[antIndex].hasFood else {
            ants[antIndex].state = .resting
            return
        }
        let amount = ants[antIndex].carriedFood
        let type = ants[antIndex].carriedFoodType ?? .seed
        let selfFeed = min(amount, 2.0)
        let selfEnergy = selfFeed * type.energyPerUnit
        ants[antIndex].energy = min(100, ants[antIndex].energy + selfEnergy)
        colonyEnergy += selfEnergy * 0.35
        let remaining = amount - selfFeed
        let stored = min(remaining, max(0, storageCapacity - storedFood))
        storedFood += stored
        depositIntoStorageChambers(nearX: ants[antIndex].x, nearY: ants[antIndex].y, amount: stored)
        foodCollected += stored
        colonyEnergy += max(0, remaining - stored) * type.energyPerUnit * 0.75
        ants[antIndex].carriedFood = 0
        ants[antIndex].carriedFoodType = nil
        ants[antIndex].state = .resting
        let x = Int(ants[antIndex].x.rounded())
        let y = Int(ants[antIndex].y.rounded())
        if x >= 0, x < width, y >= 0, y < height {
            cells[indexFor(x, y)].nestPheromone = min(25, cells[indexFor(x, y)].nestPheromone + 2)
        }
    }



    // MARK: Energy / population

    private func convertStoredFoodToEnergy() {
        guard storedFood > 0 else { return }
        let foodRatio = storedFood / max(storageCapacity, 1.0)
        let reserve: Double
        switch foodRatio {
        case ..<0.20: reserve = storedFood * 0.85
        case 0.20..<0.50: reserve = storageCapacity * 0.12
        default: reserve = storageCapacity * 0.20
        }
        let available = max(0, storedFood - reserve)
        guard available > 0 else { return }
        let rate = min(available, storedFood * 0.02, Double(ants.count) * 0.005)
        storedFood = max(0, storedFood - rate)
        withdrawFromStorageChambers(amount: rate)
        colonyEnergy = min(100_000, colonyEnergy + rate * 7.0)
    }

    private func populationDynamics() {
        guard generation % reproductionInterval == 0 else { return }
        guard ants.count < maximumPopulation else { currentReproductionRate = 0; return }
        guard storedFood >= 4.0 else { currentReproductionRate = 0; return }
        let foodRatio = min(1.0, storedFood / max(storageCapacity, 1.0))
        let energyPerAnt = colonyEnergy / Double(max(ants.count, 1))
        guard energyPerAnt >= 1.5 else { currentReproductionRate = 0; return }

        let brood: Double
        switch foodRatio {
        case ..<0.15: brood = 0
        case 0.15..<0.45: brood = 0.25 + ((foodRatio - 0.15) / 0.30) * 0.35
        case 0.45..<0.75: brood = 0.60 + ((foodRatio - 0.45) / 0.30) * 0.30
        default: brood = 1.0
        }
        let rate = min(0.113, 0.016 + brood * 0.105)
        currentReproductionRate = rate
        let requested = max(1, Int((Double(ants.count) * rate).rounded(.down)))
        let birthCount = min(requested, maximumPopulation - ants.count)
        guard birthCount > 0 else { return }
        let cost: Double
        switch foodRatio {
        case ..<0.25: cost = 8
        case 0.25..<0.50: cost = 6.5
        case 0.50..<0.75: cost = 5
        default: cost = 4
        }
        let affordable = min(birthCount, Int(storedFood / cost))
        guard affordable > 0 else { return }
        let totalCost = Double(affordable) * cost
        storedFood = max(0, storedFood - totalCost)
        withdrawFromStorageChambers(amount: totalCost)
        colonyEnergy = max(0, colonyEnergy - Double(affordable) * 1.5)
        for _ in 0..<affordable {
            let angle = Double.random(in: 0...(Double.pi * 2))
            let radius = Double.random(in: 1...5)
            let child = Ant(
                x: Double(nestCenterX) + cos(angle) * radius,
                y: Double(nestCenterY) + sin(angle) * radius,
                state: .resting,
                energy: Double.random(in: 78...96),
                pheromoneSensitivity: Double.random(in: 0.8...1.2),
                explorationBias: Double.random(in: 0.8...1.2)
            )
            ants.append(child)
            let cx = Int(child.x.rounded()), cy = Int(child.y.rounded())
            if cx >= 0, cx < width, cy >= 0, cy < height {
                cells[indexFor(cx, cy)].antCount += 1
            }
        }
        births += affordable
    }

  

    private func movementCost(state: AntState, density: Double, populationPressure: Double) -> Double {
        let base: Double
        switch state {
        case .searching: base = 0.32
        case .exploring: base = 0.42
        case .returning: base = 0.28
        case .returningForFood: base = 0.24
        case .resting: base = 0.05
        case .building: base = 0.36
        case .defending: base = 0.48
        }
        return base * (1.0 + density * 0.10 + populationPressure * 0.15)
    }

    private func consumeColonyEnergy() {
        var active = 0
        for a in ants where a.state != .resting { active += 1 }
        colonyEnergy = max(0, colonyEnergy - (Double(ants.count) * 0.055 + Double(active) * 0.025))
    }

    // MARK: Pheromone / direction

    private func depositReturningPheromone(ant: Ant) {
        let x = Int(ant.x.rounded()), y = Int(ant.y.rounded())
        guard x >= 0, x < width, y >= 0, y < height else { return }
        let i = indexFor(x, y)
        cells[i].foodPheromone = min(25, cells[i].foodPheromone + 0.18)
        cells[i].nestPheromone = min(25, cells[i].nestPheromone + 0.10)
    }

    private func evaporatePheromones() {
        for i in cells.indices {
            if cells[i].foodPheromone > 0.0005 {
                cells[i].foodPheromone *= 0.992
                if cells[i].foodPheromone < 0.001 { cells[i].foodPheromone = 0 }
            }
            if cells[i].nestPheromone > 0.0005 {
                cells[i].nestPheromone *= 0.995
                if cells[i].nestPheromone < 0.001 { cells[i].nestPheromone = 0 }
            }
        }
    }

    private func pheromoneDirection(for ant: Ant) -> (x: Double, y: Double) {
        let cx = Int(ant.x.rounded()), cy = Int(ant.y.rounded())
        var best = 0.0, bx = 0, by = 0
        for dy in -2...2 {
            for dx in -2...2 {
                if dx == 0 && dy == 0 { continue }
                let x = cx + dx, y = cy + dy
                guard x >= 0, x < width, y >= 0, y < height else { continue }
                let v = cells[indexFor(x, y)].foodPheromone
                if v > best { best = v; bx = dx; by = dy }
            }
        }
        return normalized(x: Double(bx), y: Double(by))
    }

    private func nestDirection(for ant: Ant) -> (x: Double, y: Double) {
        let cx = Int(ant.x.rounded()), cy = Int(ant.y.rounded())
        var vx = 0.0, vy = 0.0
        for dy in -2...2 {
            for dx in -2...2 {
                if dx == 0 && dy == 0 { continue }
                let x = cx + dx, y = cy + dy
                guard x >= 0, x < width, y >= 0, y < height else { continue }
                let v = cells[indexFor(x, y)].nestPheromone
                guard v > 0 else { continue }
                let inv = 1.0 / sqrt(Double(dx * dx + dy * dy))
                vx += Double(dx) * inv * v
                vy += Double(dy) * inv * v
            }
        }
        return normalized(x: vx, y: vy)
    }


    private func moveAntSafely(index: Int, directionX: Double, directionY: Double, speed: Double) -> Bool {
        let ox = ants[index].x, oy = ants[index].y
        let cx = ox + directionX * speed, cy = oy + directionY * speed
        if isWalkable(x: cx, y: cy) {
            ants[index].x = cx; ants[index].y = cy
            ants[index].directionX = directionX; ants[index].directionY = directionY
            return true
        }
        for alt in [(-directionY, directionX), (directionY, -directionX), (-directionX, -directionY)] {
            let nx = ox + alt.0 * speed, ny = oy + alt.1 * speed
            if isWalkable(x: nx, y: ny) {
                ants[index].x = nx; ants[index].y = ny
                ants[index].directionX = alt.0; ants[index].directionY = alt.1
                return true
            }
        }
        return false
    }

    private func isWalkable(x: Double, y: Double) -> Bool {
        guard x >= 1, x < Double(width - 1), y >= 1, y < Double(height - 1) else { return false }
        return cells[indexFor(Int(x.rounded()), Int(y.rounded()))].terrain != .obstacle
    }

    private func removeDepletedFood() {
        var removed = false
        for s in foodSources where s.depleted {
            let i = indexFor(s.x, s.y)
            if cells[i].terrain == .food { cells[i].terrain = .empty }
            if foodCellLookup.indices.contains(i) { foodCellLookup[i] = -1 }
            removed = true
        }
        if removed {
            foodSources.removeAll { $0.depleted }
            rebuildFoodLookup()
        }
    }

    private func evaluateColony() {
        if ants.isEmpty { colonyAlive = false; return }
        let avg = ants.reduce(0.0) { $0 + $1.energy } / Double(ants.count)
        if colonyEnergy <= 0 && storedFood <= 0 && avg < 5 { colonyAlive = false }
    }

    // MARK: Public

    var manualFoodDropCeiling: Int { maximumFoodSources + 15 }
    var canAddFoodNow: Bool { foodSources.count < manualFoodDropCeiling }

    func addFoodNow() {
        guard canAddFoodNow else { return }
        for _ in 0..<max(1, min(5, ants.count / 250)) { createFoodSource() }
    }

    func alertAllHands() {
        guard !ants.isEmpty else { return }
        guard let t = invaders.max(by: { $0.threatLevel < $1.threatLevel }) else { return }
        defensiveAlarm = max(defensiveAlarm, 1.0)
        for i in ants.indices where ants[i].energy > 0 {
            ants[i].defending = true
            ants[i].defenseTargetID = t.id
        }
    }

    func allHandsOnDeck() {
        let active = invaders.filter { $0.alive && $0.health > 0 }
        guard !active.isEmpty else { return }
        initializeDefenseSystem()
        defensiveAlarm = min(1.0, max(defensiveAlarm, 0.85))
        for i in defenseCells.indices {
            defenseCells[i].alarm = min(1.0, defenseCells[i].alarm + 0.6)
            defenseCells[i].defenderSignal = 1.0
        }
        for i in ants.indices {
            guard !ants[i].hasFood else { continue }
            var nearest: ColonyInvader?, best = Double.infinity
            for inv in active {
                let d = distance(x1: ants[i].x, y1: ants[i].y, x2: inv.x, y2: inv.y)
                if d < best { best = d; nearest = inv }
            }
            guard let t = nearest else { continue }
            ants[i].defending = true
            ants[i].defenseTargetID = t.id
            ants[i].state = .defending
        }
    }

    // MARK: Stats

    var averageAntEnergy: Double {
        guard !ants.isEmpty else { return 0 }
        return ants.reduce(0.0) { $0 + $1.energy } / Double(ants.count)
    }
    var totalFoodRemaining: Double { foodSources.reduce(0.0) { $0 + $1.amount } }
    var nestCellCount: Int {
        cells.reduce(into: 0) {
            if $1.terrain == .nest || $1.terrain == .tunnel || $1.terrain == .storage { $0 += 1 }
        }
    }
    var storageCellCount: Int { storageCellTotal }
    var tunnelCellCount: Int { cells.reduce(into: 0) { if $1.terrain == .tunnel { $0 += 1 } } }
    var searchingCount: Int { ants.reduce(into: 0) { if $1.state == .searching { $0 += 1 } } }
    var returningCount: Int { ants.reduce(into: 0) { if $1.state == .returning { $0 += 1 } } }
    var restingCount: Int { ants.reduce(into: 0) { if $1.state == .resting { $0 += 1 } } }
    var exploringCount: Int { ants.reduce(into: 0) { if $1.state == .exploring { $0 += 1 } } }
    var buildingCount: Int { ants.reduce(into: 0) { if $1.state == .building { $0 += 1 } } }
    var populationProgress: Double { Double(ants.count) / Double(maximumPopulation) }

    // MARK: Helpers

    @inline(__always) private func indexFor(_ x: Int, _ y: Int) -> Int { y * width + x }
    private func distanceFromNestSquared(x: Double, y: Double) -> Double {
        let dx = x - Double(nestCenterX), dy = y - Double(nestCenterY)
        return dx * dx + dy * dy
    }
    private func isInsideNest(x: Double, y: Double) -> Bool { distanceFromNestSquared(x: x, y: y) <= 36 }
    private func normalized(x: Double, y: Double) -> (x: Double, y: Double) {
        let m = sqrt(x * x + y * y)
        guard m > 0.0001 else { return (0, 0) }
        return (x / m, y / m)
    }
    private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, v)) }
    private func distance(x1: Double, y1: Double, x2: Double, y2: Double) -> Double {
        let dx = x2 - x1, dy = y2 - y1
        return sqrt(dx * dx + dy * dy)
    }
}

// MARK: - Defense System

@MainActor
extension AntColonySimulation {

    func initializeDefenseSystem() {
        guard !defenseInitialized else { return }
        defenseCells = Array(repeating: DefenseCell(), count: width * height)
        defenseInitialized = true
    }

    func stepDefenseSystem() {
        initializeDefenseSystem()
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
    }

    @inline(__always)
    private func updateOccupancy(fromOldX oldX: Int, oldY: Int, toNewX newX: Int, newY: Int) {
        if oldX == newX && oldY == newY { return }
        if oldX >= 0, oldX < width, oldY >= 0, oldY < height {
            let i = indexFor(oldX, oldY)
            cells[i].antCount = max(0, cells[i].antCount - 1)
        }
        if newX >= 0, newX < width, newY >= 0, newY < height {
            cells[indexFor(newX, newY)].antCount += 1
        }
    }

 
    private func randomInvaderType() -> InvaderType {
        let types: [(InvaderType, Double)] = [
            (.rivalAnt, InvaderType.rivalAnt.spawnWeight),
            (.worm, InvaderType.worm.spawnWeight),
            (.cockroach, InvaderType.cockroach.spawnWeight),
            (.spider, InvaderType.spider.spawnWeight),
            (.mouse, InvaderType.mouse.spawnWeight)
        ]
        let totalWeight = types.reduce(0.0) { $0 + $1.1 }
        guard totalWeight > 0 else { return .rivalAnt }
        var value = Double.random(in: 0..<totalWeight)
        for (type, weight) in types {
            value -= weight
            if value <= 0 { return type }
        }
        return .rivalAnt
    }

    private func spawnInvadersIfNeeded() {
        guard invaders.count < maximumInvaders else { return }
        let colonyPressure = cachedPopulationPressure
        let baseChance = 0.02 + colonyPressure * 0.02
        guard Double.random(in: 0...1) < baseChance else {
            nextInvaderGeneration = defenseGeneration + Int.random(in: 15...35)
            return
        }
        let count = defenseGeneration < 150 ? 1 : Int.random(in: 1...2)
        for _ in 0..<count {
            guard let location = randomInvaderEntry() else { continue }
            invaders.append(
                ColonyInvader(type: randomInvaderType(), x: location.x, y: location.y)
            )
        }
        nextInvaderGeneration = defenseGeneration + Int.random(in: 18...40)
    }

    private func randomInvaderEntry() -> (x: Double, y: Double)? {
        for _ in 0..<100 {
            let edge = Int.random(in: 0..<4)
            var x = 0, y = 0
            switch edge {
            case 0:
                x = Int.random(in: 2..<(width - 2)); y = 2
            case 1:
                x = Int.random(in: 2..<(width - 2)); y = height - 3
            case 2:
                x = 2; y = Int.random(in: 2..<(height - 2))
            default:
                x = width - 3; y = Int.random(in: 2..<(height - 2))
            }
            let dx = Double(x - nestCenterX)
            let dy = Double(y - nestCenterY)
            guard dx * dx + dy * dy > 169 else { continue }
            guard cells[indexFor(x, y)].terrain != .obstacle else { continue }
            return (Double(x), Double(y))
        }
        return nil
    }

    private func updateInvaderOccupancy() {
        guard defenseCells.count == cells.count else { return }
        for index in defenseCells.indices {
            defenseCells[index].occupiedByInvader = false
        }
        for invader in invaders where invader.alive && invader.health > 0 {
            let x = Int(clamp(invader.x.rounded(), 0, Double(width - 1)))
            let y = Int(clamp(invader.y.rounded(), 0, Double(height - 1)))
            let index = indexFor(x, y)
            guard defenseCells.indices.contains(index) else { continue }
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
        for invader in invaders {
            let radius = threatRadius(for: invader.type)
            let centerX = Int(invader.x.rounded())
            let centerY = Int(invader.y.rounded())
            for dy in -radius...radius {
                for dx in -radius...radius {
                    let x = centerX + dx
                    let y = centerY + dy
                    guard x >= 0, x < width, y >= 0, y < height else { continue }
                    let distSq = Double(dx * dx + dy * dy)
                    guard distSq <= Double(radius * radius) else { continue }
                    let distance = sqrt(distSq)
                    let falloff = 1.0 - distance / Double(radius + 1)
                    let index = indexFor(x, y)
                    defenseCells[index].threat = min(
                        1.0,
                        defenseCells[index].threat + invader.type.threat * falloff * 0.18
                    )
                }
            }
        }
    }

    private func threatRadius(for type: InvaderType) -> Int {
        switch type {
        case .rivalAnt: return 5
        case .cockroach: return 6
        case .mouse: return 9
        case .worm: return 4
        case .spider: return 7
        }
    }

    private func updateDefensiveSignals() {
        var totalAlarm = 0.0
        for y in 0..<height {
            for x in 0..<width {
                let index = indexFor(x, y)
                let localThreat = min(1.0, max(0.0, defenseCells[index].threat))
                var neighboringAlarm = 0.0
                if neighborCache.indices.contains(index) {
                    for neighbor in neighborCache[index] {
                        neighboringAlarm += defenseCells[neighbor].alarm
                    }
                }
                let alarm = min(1.0, localThreat * 0.65 + min(0.35, neighboringAlarm * 0.045))
                defenseCells[index].alarm = alarm
                totalAlarm += alarm
            }
        }
        defensiveAlarm = min(
            1.0,
            totalAlarm / Double(max(1, cells.count)) * 8.0 + colonyAlarm * 0.50
        )
    }

    private func calculateColonyThreat() {
        var totalThreat = 0.0
        var threatenedCells = 0
        for cell in defenseCells {
            let threat = min(1.0, max(0.0, cell.threat))
            guard threat > 0.01 else { continue }
            totalThreat += threat
            threatenedCells += 1
        }
        colonyAlarm = threatenedCells > 0
            ? min(1.0, totalThreat / Double(threatenedCells))
            : 0.0
    }

    private func recruitDefenders() {
        guard !invaders.isEmpty else { return }
        for antIndex in ants.indices {
            if ants[antIndex].defending, let targetID = ants[antIndex].defenseTargetID {
                let alive = invaders.contains {
                    $0.id == targetID && $0.alive && $0.health > 0
                }
                if alive { continue }
                ants[antIndex].defending = false
                ants[antIndex].defenseTargetID = nil
                if ants[antIndex].state == .defending {
                    ants[antIndex].state = .exploring
                }
            }

            let antX = ants[antIndex].x
            let antY = ants[antIndex].y
            var selected: ColonyInvader?
            var selectedDistance = Double.infinity

            for invader in invaders where invader.alive && invader.health > 0 {
                let d = distance(x1: antX, y1: antY, x2: invader.x, y2: invader.y)
                guard d <= recruitmentRadius else { continue }
                let ix = Int(clamp(invader.x.rounded(), 0, Double(width - 1)))
                let iy = Int(clamp(invader.y.rounded(), 0, Double(height - 1)))
                let defenseIndex = indexFor(ix, iy)
                guard defenseCells.indices.contains(defenseIndex) else { continue }
                let cell = defenseCells[defenseIndex]
                guard cell.threat > 0 || cell.alarm > 0 || cell.defenderSignal > 0 else { continue }
                if d < selectedDistance {
                    selectedDistance = d
                    selected = invader
                }
            }

            guard let target = selected else { continue }
            ants[antIndex].defending = true
            ants[antIndex].defenseTargetID = target.id
            ants[antIndex].state = .defending
        }
    }

    private func moveDefendingAnts() {
        for antIndex in ants.indices {
            guard ants[antIndex].defending,
                  let targetID = ants[antIndex].defenseTargetID else { continue }

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
            let distSq = dx * dx + dy * dy

            if distSq > 1.0 {
                moveTowardDefense(ant: &ants[antIndex], targetX: invader.x, targetY: invader.y)
                ants[antIndex].energy = max(0, ants[antIndex].energy - movementEnergyCost)
            } else {
                resolveAntDefensiveContact(antIndex: antIndex, targetID: targetID)
            }

            let newX = Int(ants[antIndex].x.rounded())
            let newY = Int(ants[antIndex].y.rounded())
            updateOccupancy(fromOldX: oldX, oldY: oldY, toNewX: newX, newY: newY)
        }
    }

    private func moveTowardDefense(ant: inout Ant, targetX: Double, targetY: Double) {
        let dx = targetX - ant.x
        let dy = targetY - ant.y
        guard abs(dx) > 0.0001 || abs(dy) > 0.0001 else {
            ant.directionX = 0
            ant.directionY = 0
            return
        }
        if abs(dx) > abs(dy) {
            ant.directionX = dx > 0 ? 1 : -1
            ant.directionY = 0
        } else {
            ant.directionX = 0
            ant.directionY = dy > 0 ? 1 : -1
        }
        let newX = ant.x + ant.directionX
        let newY = ant.y + ant.directionY
        guard newX >= 0, newX < Double(width), newY >= 0, newY < Double(height) else { return }
        let index = indexFor(Int(newX.rounded()), Int(newY.rounded()))
        guard cells.indices.contains(index), cells[index].terrain != .obstacle else { return }
        ant.x = newX
        ant.y = newY
    }

    private func moveInvaders() {
        for index in invaders.indices {
            guard invaders[index].alive else { continue }
            invaders[index].age += 1

            let dx = Double(nestCenterX) - invaders[index].x
            let dy = Double(nestCenterY) - invaders[index].y
            let inv = 1.0 / max(0.001, sqrt(dx * dx + dy * dy))
            let directionX = dx * inv
            let directionY = dy * inv

            invaders[index].directionX = directionX
            invaders[index].directionY = directionY

            let spawnRamp = min(1.0, Double(invaders[index].age) / 18.0)
            let speed = invaders[index].type.speed * (0.40 + 0.60 * spawnRamp)
            let newX = invaders[index].x + directionX * speed
            let newY = invaders[index].y + directionY * speed

            if isDefenseWalkable(x: newX, y: newY) {
                invaders[index].x = newX
                invaders[index].y = newY
            } else {
                invaders[index].directionX = -directionY
                invaders[index].directionY = directionX
            }
        }
    }

    private func resolveDefensiveContacts() {
        guard !ants.isEmpty, !invaders.isEmpty, !defenseCells.isEmpty else { return }

        for antIndex in ants.indices {
            guard ants[antIndex].defending,
                  let targetID = ants[antIndex].defenseTargetID else { continue }

            guard let invaderIndex = invaders.firstIndex(where: {
                $0.id == targetID && $0.health > 0
            }) else {
                ants[antIndex].defending = false
                ants[antIndex].defenseTargetID = nil
                ants[antIndex].state = .searching
                continue
            }

            let dx = invaders[invaderIndex].x - ants[antIndex].x
            let dy = invaders[invaderIndex].y - ants[antIndex].y
            guard dx * dx + dy * dy <= 1.0 else { continue }

            let gx = Int(clamp(invaders[invaderIndex].x.rounded(), 0, Double(width - 1)))
            let gy = Int(clamp(invaders[invaderIndex].y.rounded(), 0, Double(height - 1)))
            let defenseIndex = indexFor(gx, gy)
            let defenseStrength = defenseCells.indices.contains(defenseIndex)
                ? max(0, defenseCells[defenseIndex].defenseStrength)
                : 0.0

            let damage = 2.5 * (1.0 + defenseStrength)
            invaders[invaderIndex].health = max(0, invaders[invaderIndex].health - damage)
            ants[antIndex].energy = max(0, ants[antIndex].energy - 0.5)

            if invaders[invaderIndex].health <= 0 {
                invadersDefeated += 1
                ants[antIndex].defending = false
                ants[antIndex].defenseTargetID = nil
                ants[antIndex].state = .searching
            }
        }
    }

    private func resolveAntDefensiveContact(antIndex: Int, targetID: UUID) {
        guard ants.indices.contains(antIndex) else { return }
        guard let invaderIndex = invaders.firstIndex(where: {
            $0.id == targetID && $0.alive && $0.health > 0
        }) else {
            ants[antIndex].defending = false
            ants[antIndex].defenseTargetID = nil
            ants[antIndex].state = .searching
            return
        }

        let dx = invaders[invaderIndex].x - ants[antIndex].x
        let dy = invaders[invaderIndex].y - ants[antIndex].y
        guard dx * dx + dy * dy <= 1.0 else { return }

        let x = Int(clamp(invaders[invaderIndex].x.rounded(), 0, Double(width - 1)))
        let y = Int(clamp(invaders[invaderIndex].y.rounded(), 0, Double(height - 1)))
        let defenseIndex = indexFor(x, y)
        let defenseStrength = defenseCells.indices.contains(defenseIndex)
            ? defenseCells[defenseIndex].defenseStrength
            : 0.0

        let damage = 2.5 * (1.0 + defenseStrength)
        invaders[invaderIndex].health = max(0, invaders[invaderIndex].health - damage)
        ants[antIndex].energy = max(0, ants[antIndex].energy - 0.5)

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
                let localBuilt = isColonyCell(x: x, y: y)

                if localBuilt {
                    defenseCells[index].defenseStrength = min(
                        1.0,
                        defenseCells[index].defenseStrength + alarm * 0.16
                    )
                }
                defenseCells[index].defenderSignal = min(1.0, threat * 0.7 + alarm * 0.3)
                if alarm > defenseCriticalThreshold && localBuilt {
                    defenseCells[index].blocked = min(1.0, defenseCells[index].blocked + 0.05)
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
        let before = invaders.count
        invaders.removeAll { !$0.alive }
        let defeated = before - invaders.count
        if defeated > 0 {
            defensiveAlarm = max(0, defensiveAlarm - Double(defeated) * 0.04)
        }
    }

    private func calculateDefensiveAlarm() {
        var breachCount = 0
        let breachSq = breachRadius * breachRadius
        for invader in invaders where invader.alive && invader.health > 0 {
            let dx = invader.x - Double(nestCenterX)
            let dy = invader.y - Double(nestCenterY)
            if dx * dx + dy * dy < breachSq {
                breachCount += 1
            }
        }
        invaderBreaches = breachCount
    }

    private func isDefenseWalkable(x: Double, y: Double) -> Bool {
        guard x >= 1, x < Double(width - 1), y >= 1, y < Double(height - 1) else { return false }
        let ix = Int(x.rounded())
        let iy = Int(y.rounded())
        guard ix >= 0, ix < width, iy >= 0, iy < height else { return false }
        return cells[indexFor(ix, iy)].terrain != .obstacle
    }

    private func isColonyCell(x: Int, y: Int) -> Bool {
        guard x >= 0, x < width, y >= 0, y < height else { return false }
        let terrain = cells[indexFor(x, y)].terrain
        return terrain == .nest || terrain == .tunnel || terrain == .storage
    }

    func addInvader(type: InvaderType) {
        guard invaders.count < maximumInvaders else { return }
        guard let location = randomInvaderEntry() else { return }
        invaders.append(ColonyInvader(type: type, x: location.x, y: location.y))
    }

    var activeInvaderCount: Int { invaders.count }

    var criticalDefenseCells: Int {
        defenseCells.reduce(into: 0) {
            if $1.alarm > defenseCriticalThreshold { $0 += 1 }
        }
    }

    var averageDefenseStrength: Double {
        guard !defenseCells.isEmpty else { return 0 }
        return defenseCells.reduce(0.0) { $0 + $1.defenseStrength } / Double(defenseCells.count)
    }

    var defenseStatus: String {
        if invaders.isEmpty { return "SECURE" }
        if defensiveAlarm > defenseCriticalThreshold { return "CRITICAL" }
        if defensiveAlarm > defenseActivationThreshold { return "DEFENDING" }
        return "ALERT"
    }
}
