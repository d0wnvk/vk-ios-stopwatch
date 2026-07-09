//
//  stopwatchApp.swift
//  stopwatch
//
//  Created by Vladimir Korolevskii on 7. 7. 2026..
//

import SwiftUI
import UIKit

@main
struct stopwatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var navigation = AppNavigation()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(navigation)
                .preferredColorScheme(.dark)
                .onAppear {
                    UIApplication.shared.isIdleTimerDisabled = true
                }
                .onOpenURL { url in
                    navigation.handle(url: url)
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            UIApplication.shared.isIdleTimerDisabled = newPhase == .active
        }
    }
}
