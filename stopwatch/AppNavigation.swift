//
//  AppNavigation.swift
//  stopwatch
//
//  Created by Codex on 9. 7. 2026..
//

import Foundation
import Combine

enum AppTab: Hashable {
    case stopwatch
    case second
}

@MainActor
final class AppNavigation: ObservableObject {
    @Published var selectedTab: AppTab = .stopwatch
    @Published private(set) var secondScreenLaunchToken: UUID?

    func handle(url: URL) {
        guard url.scheme == "stopwatch" else { return }

        switch url.host {
        case "second":
            selectedTab = .second

            let shouldAutostart = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .contains(where: { $0.name == "autostart" && $0.value == "1" }) == true

            if shouldAutostart {
                secondScreenLaunchToken = UUID()
            }
        default:
            selectedTab = .stopwatch
        }
    }
}
