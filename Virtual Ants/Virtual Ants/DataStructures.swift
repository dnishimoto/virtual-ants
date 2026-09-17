//
//  DataStructures.swift
//  Virtual Ants
//
//  Created by David Nishimoto on 9/17/26.
//

import Foundation

enum FoodType: CaseIterable {
    case seed
    case fruit
    case insect
    case nectar

    var displayName: String {
        switch self {
        case .seed:
            return "Seed"
        case .fruit:
            return "Fruit"
        case .insect:
            return "Insect"
        case .nectar:
            return "Nectar"
        }
    }

    var symbol: String {
        switch self {
        case .seed:
            return "S"
        case .fruit:
            return "F"
        case .insect:
            return "I"
        case .nectar:
            return "N"
        }
    }

    var energyPerUnit: Double {
        switch self {
        case .seed:
            return 5.0
        case .fruit:
            return 10.0
        case .insect:
            return 18.0
        case .nectar:
            return 7.0
        }
    }

    var attraction: Double {
        switch self {
        case .seed:
            return 0.8
        case .fruit:
            return 1.0
        case .insect:
            return 1.6
        case .nectar:
            return 1.1
        }
    }

    var collectionDifficulty: Double {
        switch self {
        case .seed:
            return 0.8
        case .fruit:
            return 1.0
        case .insect:
            return 1.4
        case .nectar:
            return 0.9
        }
    }
}

// MARK: - Terrain

enum Terrain {
    case empty
    case nest
    case tunnel
    case storage
    case food
    case obstacle
}

// MARK: - Ant State

enum AntState: String {
    case searching
    case returning
    case resting
    case exploring
    case building
}

// MARK: - Food Source

struct FoodSource: Identifiable {
    let id = UUID()

    var x: Int
    var y: Int

    var type: FoodType
    var amount: Double

    var depleted: Bool {
        amount <= 0.01
    }
}

// MARK: - Ant

struct Ant: Identifiable {
    let id = UUID()

    var x: Double
    var y: Double

    var state: AntState = .searching

    var energy: Double = 100.0

    var carriedFood: Double = 0.0
    var carriedFoodType: FoodType?

    var age: Int = 0

    var directionX: Double = 0.0
    var directionY: Double = 0.0

    // Local memory of a successful food source.
    var rememberedFoodX: Double?
    var rememberedFoodY: Double?

    // Individual behavioral variation.
    var pheromoneSensitivity: Double = 1.0
    var explorationBias: Double = 1.0

    var hasFood: Bool {
        carriedFood > 0.01
    }
}

// MARK: - Colony Cell

struct ColonyCell {

    var terrain: Terrain = .empty

    // Foraging pheromone.
    var foodPheromone: Double = 0.0

    // Nest-return pheromone.
    var nestPheromone: Double = 0.0

    // Construction progress.
    var construction: Double = 0.0

    // Structural strength.
    var nestStrength: Double = 0.0

    // Number of actual ants occupying the cell.
    var antCount: Int = 0

    // Environmental stress.
    var threat: Double = 0.0
    
    var storedFood: Double = 0.0
}
