//
//  ContentView.swift
//  CheckMate
//
//  Created by Syam Shukla on 2/18/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        HomeView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Receipt.self, inMemory: true)
}
