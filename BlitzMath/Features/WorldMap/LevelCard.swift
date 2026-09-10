//
//  LevelCard.swift
//  BlitzMath
//
//  Small level indicator cards for the world map, with lock state and completion indicators.
//  State machine: locked (X), active (level ID with pulse), completed (checkmark).
//

import SwiftUI

struct WorldLevelCard: View {
    let row: WorldMapViewModel.LevelRow
    let worldID: String
    let onTap: (String) -> Void

    @State private var isPulsing = false
    @State private var isPressed = false

    var body: some View {
        ZStack {
            // Card background based on state
            RoundedRectangle(cornerRadius: BlitzTheme.Layout.levelCardRadius)
                .fill(cardFill)
                .stroke(cardStroke, lineWidth: BlitzTheme.Layout.levelCardStrokeWidth)

            // State-dependent interior
            stateContent
        }
        .frame(width: BlitzTheme.Layout.levelCardSize, height: BlitzTheme.Layout.levelCardSize)
        .onTapGesture { if row.isUnlocked { onTap(row.level.levelID) } }
        .scaleEffect(isPressed && row.isUnlocked ? BlitzTheme.Motion.tapScale : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .onLongPressGesture(minimumDuration: 0.001) {
            if row.isUnlocked { isPressed = true }
        } onPressingChanged: { isPressing in
            if !isPressing { isPressed = false }
        }
        .onAppear {
            if row.isUnlocked && !row.isCompleted { startPulsing() }
        }
        .accessibilityLabel(accessibilityText)
    }

    private var cardFill: Color {
        let palette = BlitzTheme.WorldPalette
        let worldColor: Color

        switch worldID.uppercased() {
        case "A": worldColor = palette.a.fill
        case "B": worldColor = palette.b.fill
        case "C": worldColor = palette.c.fill
        case "D": worldColor = palette.d.fill
        case "E": worldColor = palette.e.fill
        case "F": worldColor = palette.f.fill
        default: worldColor = palette.a.fill
        }

        if !row.isUnlocked { return worldColor.opacity(0.1) }
        if row.isCompleted { return worldColor.opacity(0.85) }
        return worldColor
    }

    private var cardStroke: Color {
        let palette = BlitzTheme.WorldPalette
        let worldColor: Color

        switch worldID.uppercased() {
        case "A": worldColor = palette.a.outline
        case "B": worldColor = palette.b.outline
        case "C": worldColor = palette.c.outline
        case "D": worldColor = palette.d.outline
        case "E": worldColor = palette.e.outline
        case "F": worldColor = palette.f.outline
        default: worldColor = palette.a.outline
        }

        if !row.isUnlocked { return worldColor.opacity(0.5) }
        return worldColor
    }

    @ViewBuilder
    private var stateContent: some View {
        if !row.isUnlocked {
            // Crossed lines for locked state (X)
            Canvas { context in
                var path = Path()
                let inset = BlitzTheme.Layout.levelCardSize * 0.2
                path.move(to: CGPoint(x: inset, y: inset))
                path.addLine(to: CGPoint(x: BlitzTheme.Layout.levelCardSize - inset,
                                        y: BlitzTheme.Layout.levelCardSize - inset))
                path.move(to: CGPoint(x: BlitzTheme.Layout.levelCardSize - inset, y: inset))
                path.addLine(to: CGPoint(x: inset,
                                        y: BlitzTheme.Layout.levelCardSize - inset))
                context.stroke(path, with: .color(cardStroke.opacity(0.4)), lineWidth: 1.5)
            }
        } else if row.isCompleted {
            // Checkmark for completed
            Image(systemName: "checkmark")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(cardStroke.opacity(0.8))
        } else {
            // Level number for active/in-progress
            Text(row.level.levelID)
                .font(BlitzTheme.Typography.body)
                .fontWeight(.semibold)
                .foregroundStyle(BlitzTheme.Palette.ink)
        }
    }

    private var accessibilityText: String {
        let state = !row.isUnlocked ? "locked" : (row.isCompleted ? "completed" : "open")
        return "\(row.level.levelID), \(state)"
    }

    private func startPulsing() {
        let animation = Animation.easeInOut(duration: BlitzTheme.Motion.pulseDuration).repeatForever(autoreverses: false)
        withAnimation(animation) {
            isPulsing = true
        }
    }
}
