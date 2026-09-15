//
//  stopwatchApp.swift
//  stopwatch
//
//  Created by Vladimir Korolevskii on 7. 7. 2026..
//

import SwiftUI

@main
struct stopwatchApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
