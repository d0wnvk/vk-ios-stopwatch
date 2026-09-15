import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 2

    var body: some View {
        TabView(selection: $selectedTab) {
            StopwatchView()
                .tag(0)
                .tabItem {
                    Label("Stopwatch", systemImage: "stopwatch")
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
    }
}
