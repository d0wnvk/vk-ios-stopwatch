import SwiftUI

struct CellRippleEffect: View {
    let trigger: UUID?

    @State private var progress: CGFloat = 1

    var body: some View {
        Circle()
            .stroke(Color(red: 0.45, green: 0.9, blue: 1.0), lineWidth: 2)
            .scaleEffect(0.15 + progress * 1.35)
            .opacity(1 - progress)
            .onChange(of: trigger) { newTrigger in
                guard newTrigger != nil else { return }

                progress = 0
                withAnimation(.easeOut(duration: 0.45)) {
                    progress = 1
                }
            }
    }
}

/// Color Fill: fills a cell from bottom to top with light cyan after
/// an accepted tap, then fades the fill out.
struct CellColorFillEffect: View {
    let trigger: UUID?

    @State private var progress: CGFloat = 0
    @State private var fillOpacity = 0.0

    var body: some View {
        Rectangle()
            .fill(Color(red: 0.45, green: 0.9, blue: 1.0).opacity(0.35))
            .scaleEffect(x: 1, y: progress, anchor: .bottom)
            .opacity(fillOpacity)
            .onChange(of: trigger) { newTrigger in
                guard newTrigger != nil else { return }

                progress = 0
                fillOpacity = 1
                withAnimation(.easeOut(duration: 0.22)) {
                    progress = 1
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        fillOpacity = 0
                    }
                }
            }
    }
}

/// Particle Burst: emits ten cyan particles outward from the center
/// of a cell after an accepted tap.
struct CellParticleBurstEffect: View {
    let trigger: UUID?

    @State private var progress: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            let distance = min(geometry.size.width, geometry.size.height) * 0.42

            ZStack {
                ForEach(0..<10, id: \.self) { particle in
                    let angle = Double(particle) / 10 * Double.pi * 2

                    Circle()
                        .fill(Color(red: 0.45, green: 0.9, blue: 1.0))
                        .frame(width: 5, height: 5)
                        .scaleEffect(1 - progress * 0.6)
                        .offset(
                            x: CGFloat(cos(angle)) * distance * progress,
                            y: CGFloat(sin(angle)) * distance * progress
                        )
                        .opacity(1 - progress)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: trigger) { newTrigger in
            guard newTrigger != nil else { return }

            progress = 0
            withAnimation(.easeOut(duration: 0.5)) {
                progress = 1
            }
        }
    }
}

/// Progress Ring: displays a cyan ring that empties over one second
/// to show when the cell's tap cooldown will finish.
struct CellCooldownRingEffect: View {
    let trigger: UUID?

    @State private var progress: CGFloat = 1

    var body: some View {
        Circle()
            .trim(from: progress, to: 1)
            .stroke(
                Color(red: 0.45, green: 0.9, blue: 1.0).opacity(0.9),
                style: StrokeStyle(lineWidth: 3, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
            .padding(6)
            .onChange(of: trigger) { newTrigger in
                guard newTrigger != nil else { return }

                progress = 0
                withAnimation(.linear(duration: 1)) {
                    progress = 1
                }
            }
    }
}
