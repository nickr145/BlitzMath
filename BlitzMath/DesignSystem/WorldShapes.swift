import SwiftUI

// MARK: - Planetoid Dispatcher
func PlanetoidShape(worldID: String) -> AnyShape {
    switch worldID.uppercased() {
    case "A": return AnyShape(WorldAShape())
    case "B": return AnyShape(WorldBShape())
    case "C": return AnyShape(WorldCShape())
    case "D": return AnyShape(WorldDShape())
    case "E": return AnyShape(WorldEShape())
    case "F": return AnyShape(WorldFShape())
    default: return AnyShape(WorldAShape())
    }
}

// MARK: - World A: Sprouting Garden (Teardrop)
struct WorldAShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        // The silhouette spans radius above the centre and 1.3 * radius below
        // it, so 2.3 * radius must fit the height and 2 * radius the width.
        let radius = min(rect.width / 2, rect.height / 2.3) * 0.95
        let bodyHeight = radius * 2.3
        let center = CGPoint(x: rect.midX, y: rect.midY - bodyHeight / 2 + radius)

        // Rounded top. SwiftUI's y axis grows downward, so a sweep from 200
        // degrees to -20 degrees travels over the top of the circle.
        path.addArc(center: center, radius: radius,
                    startAngle: .degrees(200), endAngle: .degrees(-20),
                    clockwise: false)

        // Taper to a point below the body.
        let tipY = center.y + radius * 1.3
        path.addLine(to: CGPoint(x: center.x, y: tipY))
        path.closeSubpath()

        return path
    }
}

// MARK: - World B: Stacked Towers (Sphere with flat top)
struct WorldBShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width / 2

        // Flat-top sphere: flat line across top, rounded below
        let flatTopY = center.y - radius * 0.3
        path.move(to: CGPoint(x: center.x - radius, y: flatTopY))
        path.addLine(to: CGPoint(x: center.x + radius, y: flatTopY))

        // Rounded bottom (3/4 circle)
        path.addArc(center: center, radius: radius,
                   startAngle: .degrees(0), endAngle: .degrees(180),
                   clockwise: false)

        return path
    }
}

// MARK: - World C: Array Fields (Rounded rectangle)
struct WorldCShape: Shape {
    func path(in rect: CGRect) -> Path {
        return Path(roundedRect: rect, cornerRadius: rect.width * 0.15)
    }
}

// MARK: - World D: Fractured Lands (Segmented sphere)
///
/// The segment lines are zero-area subpaths, so they contribute nothing to a
/// `.fill()`. They render only when the shape is also stroked, which
/// `PlanetoidContainer` does.
struct WorldDShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2

        // Draw full circle
        path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                  width: radius * 2, height: radius * 2))

        // Segment lines radiating from centre (division and fraction motif)
        let segmentAngles: [Double] = [20, 100, 190, 260]
        for angle in segmentAngles {
            let radians = angle * .pi / 180
            let endPoint = CGPoint(x: center.x + radius * cos(radians),
                                   y: center.y + radius * sin(radians))
            path.move(to: center)
            path.addLine(to: endPoint)
        }

        return path
    }
}

// MARK: - World E: Layered Chambers (Stacked circles/domes)
struct WorldEShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Three horizontal bands, one ellipse centred in each. The bands tile
        // rect.height exactly and each ellipse is shorter than its band, so the
        // whole stack stays inside rect at any size.
        let bandHeight = rect.height / 3
        let ellipseHeight = bandHeight * 0.9
        let ellipseWidth = rect.width * 0.85
        let ellipseX = rect.midX - ellipseWidth / 2

        for band in 0..<3 {
            let bandY = rect.minY + CGFloat(band) * bandHeight
            let ellipseY = bandY + (bandHeight - ellipseHeight) / 2
            path.addEllipse(in: CGRect(x: ellipseX, y: ellipseY,
                                       width: ellipseWidth, height: ellipseHeight))
        }

        return path
    }
}

// MARK: - World F: Geometric Nexus (Rotated square/diamond)
struct WorldFShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        // Matches the visual weight of the other planetoids, which fill or
        // nearly fill their rect.
        let size = min(rect.width, rect.height) * 0.85

        var path = Path()
        path.move(to: CGPoint(x: center.x, y: center.y - size / 2)) // Top
        path.addLine(to: CGPoint(x: center.x + size / 2, y: center.y)) // Right
        path.addLine(to: CGPoint(x: center.x, y: center.y + size / 2)) // Bottom
        path.addLine(to: CGPoint(x: center.x - size / 2, y: center.y)) // Left
        path.closeSubpath()

        return path
    }
}
