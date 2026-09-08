import SwiftUI

/// The winding "Din rutt genom A1" route from the home screen.
///
/// Geometry is authored in the design's 340 × 92 coordinate space and scaled to
/// fit. Node 0 is the first lesson; the solid purple stretch is trimmed to the
/// learner's current position, so the drawing follows real progress.
struct JourneyRoute: View {
    /// Index of the lesson the learner is on, 0-based.
    let currentIndex: Int
    let totalStops: Int

    private static let designSize = CGSize(width: 340, height: 98)

    private static let stops: [CGPoint] = [
        CGPoint(x: 14, y: 66),
        CGPoint(x: 70, y: 40),
        CGPoint(x: 106, y: 60),
        CGPoint(x: 140, y: 44),
        CGPoint(x: 200, y: 24),
        CGPoint(x: 262, y: 52),
        CGPoint(x: 300, y: 66),
        CGPoint(x: 326, y: 34)
    ]

    private static var routePath: Path {
        var path = Path()
        path.move(to: CGPoint(x: 14, y: 66))
        path.addCurve(
            to: CGPoint(x: 140, y: 44),
            control1: CGPoint(x: 60, y: 20),
            control2: CGPoint(x: 100, y: 78)
        )
        path.addCurve(
            to: CGPoint(x: 262, y: 52),
            control1: CGPoint(x: 180, y: 10),
            control2: CGPoint(x: 220, y: 12)
        )
        path.addCurve(
            to: CGPoint(x: 326, y: 34),
            control1: CGPoint(x: 304, y: 92),
            control2: CGPoint(x: 310, y: 74)
        )
        return path
    }

    /// Where along the route the current stop sits, as a 0…1 fraction.
    private var travelled: CGFloat {
        let last = max(Self.stops.count - 1, 1)
        let clamped = min(max(currentIndex, 0), last)
        return CGFloat(clamped) / CGFloat(last)
    }

    private var visibleStops: [CGPoint] {
        Array(Self.stops.prefix(totalStops == 0 ? Self.stops.count : min(totalStops, Self.stops.count)))
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / Self.designSize.width
            let transform = CGAffineTransform(scaleX: scale, y: scale)
            let route = Self.routePath.applying(transform)

            ZStack {
                route.stroke(
                    Color.black.opacity(0.10),
                    style: StrokeStyle(
                        lineWidth: 8 * scale,
                        lineCap: .round,
                        dash: [1 * scale, 14 * scale]
                    )
                )

                route
                    .trimmedPath(from: 0, to: travelled)
                    .stroke(
                        ItaLearn.purple,
                        style: StrokeStyle(lineWidth: 4 * scale, lineCap: .round)
                    )

                ForEach(Array(visibleStops.enumerated()), id: \.offset) { index, point in
                    stopMarker(for: index)
                        .position(x: point.x * scale, y: point.y * scale)
                }

                if currentIndex < visibleStops.count {
                    // Keep the caption inside the card even when the current
                    // stop sits at either end of the route.
                    let labelInset: CGFloat = 42 * scale
                    let markerX = visibleStops[currentIndex].x * scale

                    Text("DU ÄR HÄR")
                        .font(.system(size: 10 * scale, weight: .semibold))
                        .foregroundStyle(ItaLearn.magenta)
                        .fixedSize()
                        .position(
                            x: min(max(markerX, labelInset), proxy.size.width - labelInset),
                            y: 84 * scale
                        )
                }
            }
            .frame(width: proxy.size.width, height: Self.designSize.height * scale)
        }
        .aspectRatio(Self.designSize.width / Self.designSize.height, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Din rutt")
        .accessibilityValue("Lektion \(currentIndex + 1) av \(visibleStops.count)")
    }

    @ViewBuilder
    private func stopMarker(for index: Int) -> some View {
        if index < currentIndex {
            Circle()
                .fill(ItaLearn.purple)
                .frame(width: 14, height: 14)
        } else if index == currentIndex {
            ZStack {
                Circle()
                    .strokeBorder(ItaLearn.magenta, lineWidth: 3)
                    .frame(width: 24, height: 24)
                Circle()
                    .fill(ItaLearn.magenta)
                    .frame(width: 14, height: 14)
            }
        } else {
            Circle()
                .fill(ItaLearn.card)
                .frame(width: 12, height: 12)
                .overlay {
                    Circle().strokeBorder(Color.black.opacity(0.18), lineWidth: 2)
                }
        }
    }
}

#Preview {
    JourneyRoute(currentIndex: 3, totalStops: 8)
        .padding()
        .background(ItaLearn.card)
}
