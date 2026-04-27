//
//  Did_I_Feed_The_Dog_App.swift
//  Did I Feed The Dog?
//
//  Created by Delon Sampaio on 4/27/26.
//

import SwiftUI
import SwiftData

@main
struct Did_I_Feed_The_Dog_App: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
