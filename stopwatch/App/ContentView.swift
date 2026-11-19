import Combine
import Foundation
import SwiftUI
import UIKit

struct ContentView: View {
    @State private var selectedTab: Int
    @State private var showPhotoExport = false
    @State private var isAppTabBarVisible = true
    @State private var provisioningTimeRemaining = ProvisioningCountdown.text()

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

            SportTrackerView()
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
                    provisioningTimeRemaining: provisioningTimeRemaining
                )
            }
        }
        .onReceive(provisioningRefreshTimer) { date in
            provisioningTimeRemaining = ProvisioningCountdown.text(at: date)
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
    private static let buttonCount: CGFloat = 7

    @Binding var selection: Int
    @Binding var showPhotoExport: Bool
    let provisioningTimeRemaining: String

    var body: some View {
        GeometryReader { geometry in
            let buttonWidth = geometry.size.width / Self.buttonCount

            HStack(spacing: 0) {
                stopwatchButton
                    .frame(width: buttonWidth)
                    .tabButtonOutline()
                tabButton(title: "Eye Break", tag: 1)
                    .frame(width: buttonWidth)
                    .tabButtonOutline()
                tabButton(title: "Sport plan 1", tag: 2)
                    .frame(width: buttonWidth)
                    .tabButtonOutline()
                tabButton(title: "Insta\n360", tag: 3)
                    .frame(width: buttonWidth)
                    .tabButtonOutline()
                tabButton(title: "Recorder", tag: 4)
                    .frame(width: buttonWidth)
                    .tabButtonOutline()
                tabButton(title: "Video player", tag: 5)
                    .frame(width: buttonWidth)
                    .tabButtonOutline()
                Button { showPhotoExport = true } label: {
                    Text("Photos to mac")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.plain)
                .frame(width: buttonWidth)
                .tabButtonOutline()
            }
            .padding(.top, 7)
            .padding(.bottom, 4)
            .background(.bar)
            .overlay(alignment: .top) {
                Divider()
            }
        }
        .frame(height: 65)
        .background(.bar)
    }

    private var stopwatchButton: some View {
        Button {
            selection = 0
        } label: {
            VStack(spacing: 2) {
                Text("Stopwatch")
                Text(provisioningTimeRemaining)
                    .monospacedDigit()
                    .foregroundStyle(Color(red: 0.45, green: 0.9, blue: 1.0))
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
