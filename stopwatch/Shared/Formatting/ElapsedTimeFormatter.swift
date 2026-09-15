import Foundation

enum ElapsedTimeFormatter {
    static func centiseconds(_ interval: TimeInterval) -> String {
        let totalCentiseconds = max(0, Int(interval * 100))
        let minutes = totalCentiseconds / 6_000
        let seconds = (totalCentiseconds / 100) % 60
        let centiseconds = totalCentiseconds % 100

        return String(format: "%02d:%02d.%02d", minutes, seconds, centiseconds)
    }
}
