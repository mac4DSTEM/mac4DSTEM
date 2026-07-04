//
//  FourDSTEMApp.swift
//  Role: Application entry point. Creates the shared AppState, injects it into
//        the SwiftUI environment, and configures the main window. Dark mode is
//        the default (per the design spec); remove `.preferredColorScheme(.dark)`
//        to follow the system appearance instead.
//

import SwiftUI

@main
struct FourDSTEMApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(app)
                .frame(minWidth: 1000, minHeight: 640)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            // Replace the default "New" with nothing useful yet; keep standard
            // menus. A real "Open…" command can be wired to the importer later.
            CommandGroup(replacing: .newItem) { }
        }
    }
}
