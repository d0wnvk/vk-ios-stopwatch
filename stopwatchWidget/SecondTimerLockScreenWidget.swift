//
//  SecondTimerLockScreenWidget.swift
//  stopwatchWidget
//
//  Created by Codex on 9. 7. 2026..
//

import SwiftUI
import WidgetKit

private struct SecondTimerEntry: TimelineEntry {
    let date: Date
}

private struct SecondTimerProvider: TimelineProvider {
    func placeholder(in context: Context) -> SecondTimerEntry {
        SecondTimerEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (SecondTimerEntry) -> Void) {
        completion(SecondTimerEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SecondTimerEntry>) -> Void) {
        let entry = SecondTimerEntry(date: .now)
        let timeline = Timeline(entries: [entry], policy: .never)
        completion(timeline)
    }
}

struct SecondTimerLockScreenWidget: Widget {
    private let kind = "SecondTimerLockScreenWidget"
    private let launchURL = URL(string: "stopwatch://second?autostart=1")!

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SecondTimerProvider()) { _ in
            SecondTimerWidgetView(launchURL: launchURL)
        }
        .configurationDisplayName("Second Timer")
        .description("Opens the app directly on the second screen and starts the timer.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
        ])
    }
}

private struct SecondTimerWidgetView: View {
    let launchURL: URL
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            Link(destination: launchURL) {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 18, weight: .bold))
                }
            }
        case .accessoryInline:
            Link(destination: launchURL) {
                Text("Run 30s timer")
            }
        default:
            Link(destination: launchURL) {
                HStack {
                    Image(systemName: "timer")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Second Timer")
                            .font(.headline)
                        Text("Open and start")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

