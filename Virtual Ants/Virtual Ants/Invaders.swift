
//

import Foundation
import SwiftUI
import Combine
import SceneKit


enum InvaderType: String, CaseIterable, Identifiable {

    case rivalAnt = "Other Ant"
    case cockroach = "Cockroach"
    case mouse = "Mouse"
    case worm = "Worm"
    case spider = "Spider"

    var id: String {
        rawValue
    }

    // -------------------------------------------------
    // HOW OFTEN THIS INVADER IS ALLOWED TO SPAWN
    // -------------------------------------------------

    var spawnWeight: Double {

        switch self {

        case .rivalAnt:
            return 45.0

        case .cockroach:
            return 15.0

        case .mouse:
            return 2.0

        case .worm:
            return 30.0

        case .spider:
            return 8.0
        }
    }

    // -------------------------------------------------
    // CONTRIBUTION TO COLONY THREAT / ALARM
    // -------------------------------------------------

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

    // -------------------------------------------------
    // MOVEMENT SPEED
    // -------------------------------------------------

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

    // -------------------------------------------------
    // HEALTH / DAMAGE REQUIRED TO DEFEAT
    // -------------------------------------------------

    var health: Double {

        switch self {

        case .rivalAnt:
            return 10.0

        case .cockroach:
            return 18.0

        case .mouse:
            return 45.0

        case .worm:
            return 12.0

        case .spider:
            return 25.0
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

    var alive: Bool

    var directionX: Double
    var directionY: Double

    var targetX: Double?
    var targetY: Double?
    
    var threatLevel: Double = 0.0

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

        self.alive = true

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


