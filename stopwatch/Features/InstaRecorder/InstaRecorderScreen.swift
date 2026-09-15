import SwiftUI

struct Insta360RecorderScreen: View {
    @StateObject private var recorder = RecorderController()

    var body: some View {
        Insta360RecorderView()
            .environmentObject(recorder)
        .onDisappear {
            recorder.stop()
        }
    }
}
