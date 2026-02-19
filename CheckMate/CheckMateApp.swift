//
//  CheckMateApp.swift
//  CheckMate
//
//  Created by Syam Shukla on 2/18/26.
//

import SwiftUI
import SwiftData

@main
struct CheckMateApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Receipt.self,
            LineItem.self,
            Person.self,
            Split.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Schema changed (e.g. relationship migration) — reset the local store.
            // Safe during development; no production data is lost.
            print("⚠️ ModelContainer error: \(error)\nResetting store…")
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                      in: .userDomainMask).first!
            let storeFiles = (try? FileManager.default.contentsOfDirectory(
                at: appSupport,
                includingPropertiesForKeys: nil
            )) ?? []
            for file in storeFiles where file.lastPathComponent.hasPrefix("default") {
                try? FileManager.default.removeItem(at: file)
            }
            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("Could not create ModelContainer after reset: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .modelContainer(sharedModelContainer)
    }
}
