//
//  BlitzTheme.swift
//  BlitzMath
//
//  Single source of colour, type, spacing, and motion tokens (SRS UI-05).
//
//  Direction: graph paper and a stopwatch. The visual heritage of the
//  curriculum is a printed worksheet, so the surface reads as paper with a
//  faint grid rule, and the only loud element is the timing ring. Everything
//  else stays quiet.
//

import SwiftUI

enum BlitzTheme {

    // MARK: Colour

    enum Palette {
        /// Worksheet paper.
        static let surface = Color(red: 0.984, green: 0.980, blue: 0.965)
        /// Ink for numerals and prose.
        static let ink = Color(red: 0.078, green: 0.102, blue: 0.180)
        static let inkSecondary = Color(red: 0.353, green: 0.388, blue: 0.478)
        /// Grid rule on the paper.
        static let rule = Color(red: 0.851, green: 0.867, blue: 0.898)
        /// Primary action and the comfortable pace ring.
        static let velocity = Color(red: 0.231, green: 0.180, blue: 0.878)
        /// Ring state at 75 percent of the SCT.
        static let tightening = Color(red: 0.941, green: 0.635, blue: 0.008)
        /// Ring state past the SCT, and incorrect feedback.
        static let overTarget = Color(red: 0.878, green: 0.251, blue: 0.231)
        static let correct = Color(red: 0.043, green: 0.549, blue: 0.412)
        static let locked = Color(red: 0.612, green: 0.639, blue: 0.694)

        static let gold = Color(red: 0.855, green: 0.663, blue: 0.212)
        static let silver = Color(red: 0.639, green: 0.667, blue: 0.702)
        static let bronze = Color(red: 0.722, green: 0.494, blue: 0.310)
    }

    // MARK: World palette

    struct WorldPalette {
        struct World {
            let fill: Color
            let outline: Color
            let accent: Color
        }

        static let a = World(fill: Color(red: 0.961, green: 0.902, blue: 0.827), // #F5E6D3
                             outline: Color(red: 0.545, green: 0.451, blue: 0.325), // #8B7355
                             accent: Color(red: 0.420, green: 0.365, blue: 0.259)) // #6B5D42

        static let b = World(fill: Color(red: 0.659, green: 0.847, blue: 0.910), // #A8D8E8
                             outline: Color(red: 0.169, green: 0.373, blue: 0.498), // #2B5F7F
                             accent: Color(red: 0.102, green: 0.247, blue: 0.361)) // #1A3F5C

        static let c = World(fill: Color(red: 0.722, green: 0.902, blue: 0.659), // #B8E6A8
                             outline: Color(red: 0.290, green: 0.486, blue: 0.306), // #4A7C4E
                             accent: Color(red: 0.176, green: 0.353, blue: 0.192)) // #2D5A31

        static let d = World(fill: Color(red: 0.961, green: 0.776, blue: 0.580), // #F5C694
                             outline: Color(red: 0.788, green: 0.482, blue: 0.310), // #C97B4F
                             accent: Color(red: 0.659, green: 0.388, blue: 0.255)) // #A86341

        static let e = World(fill: Color(red: 0.831, green: 0.647, blue: 0.851), // #D4A5D9
                             outline: Color(red: 0.420, green: 0.298, blue: 0.478), // #6B4C7A
                             accent: Color(red: 0.302, green: 0.212, blue: 0.349)) // #4D3659

        static let f = World(fill: Color(red: 0.102, green: 0.227, blue: 0.322), // #1A3A52
                             outline: Color(red: 0.0, green: 0.831, blue: 1.0), // #00D4FF
                             accent: Color(red: 0.290, green: 0.498, blue: 1.0)) // #4A7FFF
    }

    // MARK: Type

    enum Typography {
        /// Question numerals. Rounded reads clearly for early readers.
        static let question = Font.system(size: 44, weight: .semibold, design: .rounded)
        static let questionCompact = Font.system(size: 32, weight: .semibold, design: .rounded)
        /// Monospaced digits keep the timer from shifting the layout (UI-04).
        static let timer = Font.system(size: 22, weight: .medium, design: .monospaced)
        static let title = Font.system(size: 24, weight: .semibold, design: .rounded)
        static let body = Font.system(size: 17, weight: .regular)
        static let caption = Font.system(size: 14, weight: .regular)
        static let padDigit = Font.system(size: 28, weight: .medium, design: .rounded)
    }

    // MARK: Spacing and shape

    enum Layout {
        static let gutter: CGFloat = 20
        static let stackGap: CGFloat = 16
        static let tightGap: CGFloat = 8
        /// Minimum touch target (SRS FR-ACC-004).
        static let minimumTarget: CGFloat = 44
        static let ringDiameter: CGFloat = 120
        static let ringWidth: CGFloat = 12
        static let cardRadius: CGFloat = 14
        static let padRadius: CGFloat = 10
        static let worldDiameter: CGFloat = 280
        static let worldSpacing: CGFloat = 16
        static let levelCardSize: CGFloat = 48
        static let levelCardRadius: CGFloat = 8
        static let levelCardStrokeWidth: CGFloat = 2
        /// Fraction of card size for lock cross padding (UI-05).
        static let levelCardLockCrossInsetRatio: CGFloat = 0.2
    }

    // MARK: Motion

    enum Motion {
        static let answerFeedback = Animation.spring(response: 0.28, dampingFraction: 0.72)
        static let ringTick = Animation.linear(duration: 0.1)
        /// The single orchestrated moment in the app: the medal reveal.
        static let medalReveal = Animation.spring(response: 0.55, dampingFraction: 0.62)
        static let pulseDuration: CGFloat = 2.0
        static let tapScale: CGFloat = 0.98
        /// Press animation duration for level card tap feedback (UI-05).
        static let pressAnimationDuration: CGFloat = 0.1
        /// Scale factor for active pulse on level card (UI-05).
        static let pulseMagnitude: CGFloat = 1.05

        /// Cross-fade substitute when Reduce Motion is on (SRS FR-FBK-003).
        static func respectingReduceMotion(_ animation: Animation, reduced: Bool) -> Animation {
            reduced ? .easeInOut(duration: 0.15) : animation
        }
    }

    // MARK: Level card opacity

    enum LevelCardOpacity {
        /// Opacity when level is locked (UI-05).
        static let locked: CGFloat = 0.1
        /// Opacity when level is completed (UI-05).
        static let completed: CGFloat = 0.85
        /// Opacity for stroke when locked (UI-05).
        static let lockedStroke: CGFloat = 0.5
        /// Opacity for X mark when locked (UI-05).
        static let lockedX: CGFloat = 0.4
    }

    // MARK: Medal mapping

    static func colour(for medal: MedalTier) -> Color {
        switch medal {
        case .gold: Palette.gold
        case .silver: Palette.silver
        case .bronze: Palette.bronze
        case .none: Palette.locked
        }
    }

    static func colour(for pace: BlitzClock.Pace) -> Color {
        switch pace {
        case .comfortable: Palette.velocity
        case .tightening: Palette.tightening
        case .overTarget: Palette.overTarget
        }
    }
}

// MARK: - Vector shapes

/// Timing ring bound to SCT consumption (SRS FR-BLZ-004).
struct SCTRing: Shape {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width, rect.height) / 2
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY),
                    radius: radius,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(-90 + 360 * min(1, max(0, fraction))),
                    clockwise: false)
        return path
    }
}

/// Medal outline drawn as vector, so no raster asset ships (SRS CN-03).
struct MedalBadge: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let centre = CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.08)
        let radius = min(rect.width, rect.height) * 0.34
        path.addEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius,
                                   width: radius * 2, height: radius * 2))
        path.move(to: CGPoint(x: rect.midX - radius * 0.7, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX - radius * 0.25, y: centre.y - radius * 0.9))
        path.move(to: CGPoint(x: rect.midX + radius * 0.7, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + radius * 0.25, y: centre.y - radius * 0.9))
        return path
    }
}

/// Faint worksheet grid used as the app background.
struct GraphPaperGrid: View {
    var spacing: CGFloat = 28

    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }
            context.stroke(path, with: .color(BlitzTheme.Palette.rule.opacity(0.5)), lineWidth: 0.5)
        }
        .background(BlitzTheme.Palette.surface)
        .accessibilityHidden(true)
    }
}
