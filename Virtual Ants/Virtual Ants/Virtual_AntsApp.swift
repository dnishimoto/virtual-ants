//
//  Virtual_AntsApp.swift
//  Virtual Ants
//
//  Created by David Nishimoto on 9/16/26.
//

import SwiftUI
import CoreData

@main
struct Virtual_AntsApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
