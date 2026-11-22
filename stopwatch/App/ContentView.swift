import Combine
import Foundation
import SwiftUI
import UIKit

struct ContentView: View {
    @State private var selectedTab: Int
    @State private var showPhotoExport = false
    @State private var isAppTabBarVisible = true
    @State private var provisioningTimeRemaining = ProvisioningCountdown.text()
    @State private var detailedProvisioningTimeRemaining = ProvisioningCountdown.text(
        includesMinutes: true
    )

    private let provisioningRefreshTimer = Timer.publish(
        every: 60,
        on: .main,
        in: .common
    ).autoconnect()

    init() {
        _selectedTab = State(
            initialValue: PersistentAppState.load(Int.self, forKey: "selected-tab") ?? 2
        )
    }

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

            SportTrackerView(provisioningTimeRemaining: detailedProvisioningTimeRemaining)
                .tag(2)
                .tabItem {
                    Text("Sport plan 1")
                }

            Insta360RecorderScreen()
                .tag(3)
                .tabItem {
                    Text("Insta\n360")
                }

            RecorderScreen()
                .tag(4)
                .tabItem {
                    Text("Recorder")
                }

            VideoPlayerView(isAppTabBarVisible: $isAppTabBarVisible)
                .tag(5)
                .tabItem {
                    Text("Video player")
                }
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isAppTabBarVisible {
                AppTabBar(
                    selection: $selectedTab,
                    showPhotoExport: $showPhotoExport,
                    cellSevenTime: detailedProvisioningTimeRemaining
                )
            }
        }
        .onReceive(provisioningRefreshTimer) { date in
            provisioningTimeRemaining = ProvisioningCountdown.text(at: date)
            detailedProvisioningTimeRemaining = ProvisioningCountdown.text(
                at: date,
                includesMinutes: true
            )
        }
        .onAppear {
            updateSupportedOrientations(for: selectedTab)
        }
        .onChange(of: selectedTab) { _, newValue in
            PersistentAppState.save(newValue, forKey: "selected-tab")
            updateSupportedOrientations(for: newValue)
        }
        .sheet(isPresented: $showPhotoExport) { PhotoExportView() }
    }

    private func updateSupportedOrientations(for tab: Int) {
        let applicationScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.session.role == .windowApplication }
        let windowScene = applicationScenes.first { $0.activationState == .foregroundActive }
            ?? applicationScenes.first

        AppOrientationLock.setSportTrackerPortraitLocked(tab == 2, in: windowScene)
    }
}

private struct AppTabBar: View {
    private static let rowHeight: CGFloat = 32

    @Binding var selection: Int
    @Binding var showPhotoExport: Bool
    let cellSevenTime: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                stopwatchButton
                    .frame(maxWidth: .infinity)
                    .tabButtonOutline()
                tabButton(title: "Eye\nBreak", tag: 1)
                    .frame(maxWidth: .infinity)
                    .tabButtonOutline()
                tabButton(title: "Sport plan\n1", tag: 2)
                    .frame(maxWidth: .infinity)
                    .tabButtonOutline()
                tabButton(title: "Insta\n360", tag: 3)
                    .frame(maxWidth: .infinity)
                    .tabButtonOutline()
            }

            HStack(spacing: 0) {
                tabButton(title: "Recorder", tag: 4)
                    .frame(maxWidth: .infinity)
                    .tabButtonOutline()
                tabButton(title: "Video\nplayer", tag: 5)
                    .frame(maxWidth: .infinity)
                    .tabButtonOutline()
                Button { showPhotoExport = true } label: {
                    Text("Photos to\nmac")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: Self.rowHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .tabButtonOutline()
                Button {} label: {
                    Text(cellSevenTime)
                        .font(.caption.monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(Color(red: 1.0, green: 0.65, blue: 0.82))
                        .frame(maxWidth: .infinity, minHeight: Self.rowHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .tabButtonOutline()
                .accessibilityLabel("App time remaining, \(cellSevenTime)")
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 70)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var stopwatchButton: some View {
        Button {
            selection = 0
        } label: {
            Text("Stopwatch")
            .font(.caption)
            .multilineTextAlignment(.center)
            .fontWeight(selection == 0 ? .semibold : .regular)
            .foregroundStyle(selection == 0 ? Color.accentColor : .secondary)
            .frame(maxWidth: .infinity, minHeight: Self.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stopwatch")
    }

    private func tabButton(title: String, tag: Int) -> some View {
        Button {
            selection = tag
        } label: {
            Text(title)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .font(.caption)
                .foregroundStyle(selection == tag ? Color.accentColor : .secondary)
                .frame(maxWidth: .infinity, minHeight: Self.rowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private extension View {
    func tabButtonOutline() -> some View {
        overlay {
            Rectangle()
                .stroke(Color.yellow, lineWidth: 1)
        }
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

    static func text(at date: Date = .now, includesMinutes: Bool = false) -> String {
        guard let expirationDate else {
            return includesMinutes ? "--:--:--" : "--.--.--"
        }

        let displayedSeconds = abs(Int(expirationDate.timeIntervalSince(date)))
        let days = displayedSeconds / 86_400
        let hours = (displayedSeconds % 86_400) / 3_600
        if includesMinutes {
            let minutes = (displayedSeconds % 3_600) / 60
            return String(format: "%d:%02d:%02d", days, hours, minutes)
        }
        let minutes = (displayedSeconds % 3_600) / 60
        return String(format: "%d.%02d.%02d", days, hours, minutes)
    }
}
