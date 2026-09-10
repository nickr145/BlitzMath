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
        .animation(.easeInOut(duration: BlitzTheme.Motion.pressAnimationDuration), value: isPressed)
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
        let worldColor: Color

        switch worldID.uppercased() {
        case "A": worldColor = BlitzTheme.WorldPalette.a.fill
        case "B": worldColor = BlitzTheme.WorldPalette.b.fill
        case "C": worldColor = BlitzTheme.WorldPalette.c.fill
        case "D": worldColor = BlitzTheme.WorldPalette.d.fill
        case "E": worldColor = BlitzTheme.WorldPalette.e.fill
        case "F": worldColor = BlitzTheme.WorldPalette.f.fill
        default: worldColor = BlitzTheme.WorldPalette.a.fill
        }

        if !row.isUnlocked { return worldColor.opacity(BlitzTheme.LevelCardOpacity.locked) }
        if row.isCompleted { return worldColor.opacity(BlitzTheme.LevelCardOpacity.completed) }
        return worldColor
    }

    private var cardStroke: Color {
        let worldColor: Color

        switch worldID.uppercased() {
        case "A": worldColor = BlitzTheme.WorldPalette.a.outline
        case "B": worldColor = BlitzTheme.WorldPalette.b.outline
        case "C": worldColor = BlitzTheme.WorldPalette.c.outline
        case "D": worldColor = BlitzTheme.WorldPalette.d.outline
        case "E": worldColor = BlitzTheme.WorldPalette.e.outline
        case "F": worldColor = BlitzTheme.WorldPalette.f.outline
        default: worldColor = BlitzTheme.WorldPalette.a.outline
        }

        if !row.isUnlocked { return worldColor.opacity(BlitzTheme.LevelCardOpacity.lockedStroke) }
        return worldColor
    }

    @ViewBuilder
    private var stateContent: some View {
        if !row.isUnlocked {
            // Crossed lines for locked state (X)
            Canvas { context, size in
                var path = Path()
                let inset = BlitzTheme.Layout.levelCardSize * BlitzTheme.Layout.levelCardLockCrossInsetRatio
                path.move(to: CGPoint(x: inset, y: inset))
                path.addLine(to: CGPoint(x: BlitzTheme.Layout.levelCardSize - inset,
                                        y: BlitzTheme.Layout.levelCardSize - inset))
                path.move(to: CGPoint(x: BlitzTheme.Layout.levelCardSize - inset, y: inset))
                path.addLine(to: CGPoint(x: inset,
                                        y: BlitzTheme.Layout.levelCardSize - inset))
                context.stroke(path, with: .color(cardStroke.opacity(BlitzTheme.LevelCardOpacity.lockedX)), lineWidth: BlitzTheme.Layout.levelCardStrokeWidth)
            }
        } else if row.isCompleted {
            // Medal badge for completed
            MedalBadge()
                .stroke(BlitzTheme.colour(for: bestMedalInLevel()), lineWidth: BlitzTheme.Layout.levelCardStrokeWidth)
        } else {
            // Level number for active/in-progress
            Text(row.level.levelID)
                .font(BlitzTheme.Typography.body)
                .fontWeight(.semibold)
                .foregroundStyle(BlitzTheme.Palette.ink)
                .scaleEffect(isPulsing ? BlitzTheme.Motion.pulseMagnitude : 1.0)
        }
    }

    private var accessibilityText: String {
        let state = !row.isUnlocked ? "locked" : (row.isCompleted ? "completed" : "open")
        return "\(row.level.levelID), \(state)"
    }

    /// Compute the best medal across all modules in this level (gold > silver > bronze > none).
    private func bestMedalInLevel() -> MedalTier {
        let allMedals = row.summaries.values.compactMap { $0.bestMedal }
        if allMedals.contains(.gold) { return .gold }
        if allMedals.contains(.silver) { return .silver }
        if allMedals.contains(.bronze) { return .bronze }
        return .none
    }

    private func startPulsing() {
        let animation = Animation.easeInOut(duration: BlitzTheme.Motion.pulseDuration).repeatForever(autoreverses: false)
        withAnimation(animation) {
            isPulsing = true
        }
    }
}
