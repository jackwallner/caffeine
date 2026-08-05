import SwiftUI

struct ProgressRing: View {
    /// 0.0 to 1.0+. Values above 1 overshoot rather than clamp, so the caller
    /// can decide what "over target" should look like.
    let progress: Double
    let gradient: LinearGradient
    let glowColor: Color
    let lineWidth: CGFloat
    let size: CGFloat

    init(
        progress: Double,
        gradient: LinearGradient,
        glowColor: Color,
        lineWidth: CGFloat = 16,
        size: CGFloat = 200
    ) {
        self.progress = progress
        self.gradient = gradient
        self.glowColor = glowColor
        self.lineWidth = lineWidth
        self.size = size
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    Theme.ringTrack,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )

            Circle()
                .trim(from: 0, to: min(progress, 1.0))
                .stroke(
                    gradient,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: glowColor, radius: 8, x: 0, y: 0)

            // Past the target the arc laps once in a lighter weight, so an
            // overshoot is visible as an overshoot instead of a full ring that
            // looks identical to exactly hitting the number.
            if progress > 1 {
                Circle()
                    .trim(from: 0, to: min(progress - 1, 1.0))
                    .stroke(
                        Theme.positive,
                        style: StrokeStyle(lineWidth: lineWidth * 0.4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
