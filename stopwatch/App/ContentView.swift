import Combine
import Foundation
import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 2
    @State private var provisioningTimeRemaining = ProvisioningCountdown.text()

    private let provisioningRefreshTimer = Timer.publish(
        every: 60,
        on: .main,
        in: .common
    ).autoconnect()

    var body: some View {
        TabView(selection: $selectedTab) {
            StopwatchView()
                .tag(0)
                .tabItem {
                    Text("Stopwatch\n\(provisioningTimeRemaining)")
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }

            EyeBreakView()
                .tag(1)
                .tabItem {
                    Label("Eye Break", systemImage: "eye")
                }

            SportTrackerView()
                .tag(2)
                .tabItem {
                    Label("Sport tracker", systemImage: "terminal")
                }

            Insta360RecorderScreen()
                .tag(3)
                .tabItem {
                    Label("Insta", systemImage: "video.fill")
                }

            VideoPlayerView()
                .tag(4)
                .tabItem {
                    Label("Video player", systemImage: "play.rectangle.fill")
                }
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AppTabBar(
                selection: $selectedTab,
                provisioningTimeRemaining: provisioningTimeRemaining
            )
        }
        .onReceive(provisioningRefreshTimer) { date in
            provisioningTimeRemaining = ProvisioningCountdown.text(at: date)
        }
    }
}

private struct AppTabBar: View {
    @Binding var selection: Int
    let provisioningTimeRemaining: String

    var body: some View {
        HStack(spacing: 0) {
            stopwatchButton
            tabButton(title: "Eye Break", systemImage: "eye", tag: 1)
            tabButton(title: "Sport tracker", systemImage: "terminal", tag: 2)
            tabButton(title: "Insta", systemImage: "video.fill", tag: 3)
            tabButton(title: "Video player", systemImage: "play.rectangle.fill", tag: 4)
        }
        .padding(.top, 7)
        .padding(.bottom, 4)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var stopwatchButton: some View {
        Button {
            selection = 0
        } label: {
            VStack(spacing: 2) {
                Text("Stopwatch")
                Text(provisioningTimeRemaining)
                    .monospacedDigit()
            }
            .font(.caption2)
            .fontWeight(selection == 0 ? .semibold : .regular)
            .foregroundStyle(selection == 0 ? Color.accentColor : .secondary)
            .frame(maxWidth: .infinity, minHeight: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stopwatch, \(provisioningTimeRemaining) remaining")
    }

    private func tabButton(title: String, systemImage: String, tag: Int) -> some View {
        Button {
            selection = tag
        } label: {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: 17))
                Text(title)
                    .lineLimit(1)
            }
            .font(.caption2)
            .foregroundStyle(selection == tag ? Color.accentColor : .secondary)
            .frame(maxWidth: .infinity, minHeight: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private enum ProvisioningCountdown {
    private static let expirationDate: Date? = {
        guard
            let profileURL = Bundle.main.url(
                forResource: "embedded",
                withExtension: "mobileprovision"
            ),
            let profileData = try? Data(contentsOf: profileURL),
            let profile = String(data: profileData, encoding: .isoLatin1),
            let keyRange = profile.range(of: "<key>ExpirationDate</key>"),
            let dateStartRange = profile.range(
                of: "<date>",
                range: keyRange.upperBound..<profile.endIndex
            ),
            let dateEndRange = profile.range(
                of: "</date>",
                range: dateStartRange.upperBound..<profile.endIndex
            )
        else {
            return nil
        }

        let dateString = String(profile[dateStartRange.upperBound..<dateEndRange.lowerBound])
        return ISO8601DateFormatter().date(from: dateString)
    }()

    static func text(at date: Date = .now) -> String {
        guard let expirationDate else {
            return "--d:--h"
        }

        let remainingSeconds = max(0, Int(expirationDate.timeIntervalSince(date)))
        let days = remainingSeconds / 86_400
        let hours = (remainingSeconds % 86_400) / 3_600
        return String(format: "%dd:%02dh", days, hours)
    }
}
