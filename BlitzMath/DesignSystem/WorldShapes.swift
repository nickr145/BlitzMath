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
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width / 2

        // Teardrop: wider at top (circle), tapered below
        // Top hemisphere (circle from center to top)
        path.addArc(center: center, radius: radius,
                   startAngle: .degrees(0), endAngle: .degrees(180),
                   clockwise: false)

        // Taper down to point at bottom
        let taperBottom = CGPoint(x: center.x, y: center.y + radius * 0.6)
        path.addLine(to: taperBottom)

        // Curve back up to complete
        path.addArc(center: center, radius: radius,
                   startAngle: .degrees(180), endAngle: .degrees(360),
                   clockwise: false)

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
struct WorldDShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width / 2

        // Draw full circle
        path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                  width: radius * 2, height: radius * 2))

        return path
    }
}

// MARK: - World E: Layered Chambers (Stacked circles/domes)
struct WorldEShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        let center = CGPoint(x: rect.midX, y: rect.midY)

        // Stack of 3 circles, taller than wide
        let circleRadius = width / 2

        // Top circle
        path.addEllipse(in: CGRect(x: center.x - circleRadius, y: center.y - height * 0.4,
                                  width: circleRadius * 2, height: circleRadius * 1.5))

        // Middle circle (offset)
        path.addEllipse(in: CGRect(x: center.x - circleRadius, y: center.y - height * 0.1,
                                  width: circleRadius * 2, height: circleRadius * 1.5))

        // Bottom circle
        path.addEllipse(in: CGRect(x: center.x - circleRadius, y: center.y + height * 0.2,
                                  width: circleRadius * 2, height: circleRadius * 1.5))

        return path
    }
}

// MARK: - World F: Geometric Nexus (Rotated square/diamond)
struct WorldFShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let size = rect.width * 0.7

        var path = Path()
        path.move(to: CGPoint(x: center.x, y: center.y - size / 2)) // Top
        path.addLine(to: CGPoint(x: center.x + size / 2, y: center.y)) // Right
        path.addLine(to: CGPoint(x: center.x, y: center.y + size / 2)) // Bottom
        path.addLine(to: CGPoint(x: center.x - size / 2, y: center.y)) // Left
        path.closeSubpath()

        return path
    }
}
