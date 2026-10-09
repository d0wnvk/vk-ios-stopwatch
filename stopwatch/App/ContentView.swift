import Combine
import Foundation
import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 2
    @State private var showPhotoExport = false
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
                    Text("Eye Break")
                }

            SportTrackerView()
                .tag(2)
                .tabItem {
                    Text("Sport plan 1")
                }

            Insta360RecorderScreen()
                .tag(3)
                .tabItem {
                    Text("Insta 360")
                }

            RecorderScreen()
                .tag(4)
                .tabItem {
                    Text("Recorder")
                }

            VideoPlayerView()
                .tag(5)
                .tabItem {
                    Text("Video player")
                }
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AppTabBar(
                selection: $selectedTab,
                showPhotoExport: $showPhotoExport,
                provisioningTimeRemaining: provisioningTimeRemaining
            )
        }
        .onReceive(provisioningRefreshTimer) { date in
            provisioningTimeRemaining = ProvisioningCountdown.text(at: date)
        }
        .sheet(isPresented: $showPhotoExport) { PhotoExportView() }
    }
}

private struct AppTabBar: View {
    @Binding var selection: Int
    @Binding var showPhotoExport: Bool
    let provisioningTimeRemaining: String

    var body: some View {
        HStack(spacing: 0) {
            stopwatchButton
            tabButton(title: "Eye Break", tag: 1)
            tabButton(title: "Sport plan 1", tag: 2)
            tabButton(title: "Insta 360", tag: 3)
            tabButton(title: "Recorder", tag: 4)
            tabButton(title: "Video player", tag: 5)
            Button { showPhotoExport = true } label: {
                Text("Photos to mac")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 54)
            }
            .buttonStyle(.plain)
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
            .font(.caption)
            .multilineTextAlignment(.center)
            .fontWeight(selection == 0 ? .semibold : .regular)
            .foregroundStyle(selection == 0 ? Color.accentColor : .secondary)
            .frame(maxWidth: .infinity, minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stopwatch, \(provisioningTimeRemaining) remaining")
    }

    private func tabButton(title: String, tag: Int) -> some View {
        Button {
            selection = tag
        } label: {
            Text(title)
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .font(.caption)
                .foregroundStyle(selection == tag ? Color.accentColor : .secondary)
                .frame(maxWidth: .infinity, minHeight: 54)
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
