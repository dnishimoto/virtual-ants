
//

import Foundation
import SwiftUI
import Combine
import SceneKit

// MARK: - Invader Type

enum InvaderType: String, CaseIterable, Identifiable {
    case rivalAnt = "Other Ant"
    case cockroach = "Cockroach"
    case mouse = "Mouse"
    case worm = "Worm"
    case spider = "Spider"

    var id: String { rawValue }

    var threat: Double {
        switch self {
        case .rivalAnt:
            return 0.45
        case .cockroach:
            return 0.65
        case .mouse:
            return 1.00
        case .worm:
            return 0.35
        case .spider:
            return 0.80
        }
    }

    var speed: Double {
        switch self {
        case .rivalAnt:
            return 0.38
        case .cockroach:
            return 0.52
        case .mouse:
            return 0.24
        case .worm:
            return 0.12
        case .spider:
            return 0.20
        }
    }

    var health: Double {
        switch self {
        case .rivalAnt:
            return 10
        case .cockroach:
            return 18
        case .mouse:
            return 45
        case .worm:
            return 12
        case .spider:
            return 25
        }
    }

    var displayName: String {
        rawValue
    }
}

// MARK: - Invader

struct ColonyInvader: Identifiable {
    let id: UUID

    var type: InvaderType

    var x: Double
    var y: Double

    var health: Double
    var age: Int

    var directionX: Double
    var directionY: Double

    var targetX: Double?
    var targetY: Double?

    init(
        type: InvaderType,
        x: Double,
        y: Double
    ) {
        self.id = UUID()
        self.type = type
        self.x = x
        self.y = y
        self.health = type.health
        self.age = 0
        self.directionX = 0
        self.directionY = 0
        self.targetX = nil
        self.targetY = nil
    }

    var alive: Bool {
        health > 0
    }
}

// MARK: - Defensive Cell

struct DefenseCell {

    var threat: Double = 0.0

    var alarm: Double = 0.0

    var defenderSignal: Double = 0.0

    var defenseStrength: Double = 0.0

    var blocked: Double = 0.0

    var occupiedByInvader: Bool = false
}

