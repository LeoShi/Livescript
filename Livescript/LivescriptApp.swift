//
//  LivescriptApp.swift
//  Livescript
//
//  Created by Lei S on 2026/5/5.
//

import SwiftUI

@main
struct LivescriptApp: App {
    @StateObject private var viewModel = TranscriptionViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
    }
}
