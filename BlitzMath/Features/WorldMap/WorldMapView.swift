//
//  WorldMapView.swift
//  BlitzMath
//
//  Skill tree across Levels A to F, with lock state and medal display
//  (SRS FR-NAV).
//

import SwiftUI

@MainActor
@Observable
final class WorldMapViewModel {

    struct LevelRow: Identifiable, Equatable {
        let level: CurriculumLevel
        let isUnlocked: Bool
        let isCompleted: Bool
        let requirementText: String?
        let summaries: [String: ModuleSummary]

        var id: String { level.levelID }
        func summary(for moduleID: String) -> ModuleSummary? { summaries[moduleID] }
    }

    private(set) var rows: [LevelRow] = []
    private(set) var loadError: String?

    private let curriculum: CurriculumProviding
    private let store: ProgressPersisting

    init(curriculum: CurriculumProviding, store: ProgressPersisting) {
        self.curriculum = curriculum
        self.store = store
    }

    /// Rebuilt on appear and whenever a summary is dismissed (SRS FR-NAV-007).
    func refresh() {
        do {
            _ = try store.synchroniseLockStates(with: curriculum.payload.orderedLevels)
            let snapshot = try store.medalSnapshot()
            let levelsByID = Dictionary(uniqueKeysWithValues:
                curriculum.payload.orderedLevels.map { ($0.levelID, $0) })

            rows = try curriculum.payload.orderedLevels.map { level in
                let unlocked = ProgressionGate.isUnlocked(requirement: level.unlockRequirement,
                                                          snapshot: snapshot)
                let summaries = try store.moduleSummaries(levelID: level.levelID)
                var requirementText: String?
                if !unlocked, let requirement = level.unlockRequirement {
                    let sourceName = levelsByID[requirement.sourceLevelID]?.levelName ?? requirement.sourceLevelID
                    requirementText = ProgressionGate.requirementText(for: requirement,
                                                                      sourceLevelName: sourceName,
                                                                      snapshot: snapshot)
                }
                return LevelRow(
                    level: level,
                    isUnlocked: unlocked,
                    isCompleted: ProgressionGate.isCompleted(level: level, snapshot: snapshot),
                    requirementText: requirementText,
                    summaries: Dictionary(uniqueKeysWithValues: summaries.map { ($0.id, $0) })
                )
            }
            loadError = nil
        } catch {
            loadError = "Progress could not be read. Close the app and open it again."
        }
    }
}

// MARK: - View

struct WorldMapView: View {

    @State private var model: WorldMapViewModel
    private let makeSessionController: () -> LevelSessionController

    @State private var activeModuleID: String?
    @State private var currentWorldIndex = 0
    /// Requirement text for a locked level the player just tapped (FR-NAV-003).
    /// Presented as a toast-style alert; non-nil drives its visibility.
    @State private var lockedMessageText: String?

    init(model: WorldMapViewModel, makeSessionController: @escaping () -> LevelSessionController) {
        _model = State(initialValue: model)
        self.makeSessionController = makeSessionController
    }

    var body: some View {
        NavigationStack {
            ZStack {
                background

                VStack(spacing: 0) {
                    header

                    ScrollViewReader { scrollProxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: BlitzTheme.Layout.worldSpacing) {
                                ForEach(model.rows) { row in
                                    PlanetoidContainer(row: row, scrollProxy: scrollProxy) { moduleID in
                                        guard row.isUnlocked else { return }
                                        activeModuleID = moduleID
                                    } onLockedTap: {
                                        lockedMessageText = row.requirementText
                                            ?? "Complete the previous level first."
                                    }
                                }
                            }
                            .padding(BlitzTheme.Layout.gutter)
                        }
                        .frame(height: BlitzTheme.Layout.worldDiameter + 100)
                    }

                    Spacer()
                    paginationDots
                }
            }
            .task { model.refresh() }
            .fullScreenCover(item: $activeModuleID) { moduleID in
                LevelSessionView(moduleID: moduleID, controller: makeSessionController())
                    .onDisappear { model.refresh() }
            }
            .alert(
                "Locked",
                isPresented: Binding(
                    get: { lockedMessageText != nil },
                    set: { isPresented in
                        if !isPresented { lockedMessageText = nil }
                    }
                ),
                actions: {
                    Button("OK") { lockedMessageText = nil }
                },
                message: {
                    Text(lockedMessageText ?? "")
                }
            )
        }
    }

    private var background: some View {
        GraphPaperGrid().ignoresSafeArea()
    }

    private var header: some View {
        Text("Choose your world")
            .font(BlitzTheme.Typography.title)
            .foregroundStyle(BlitzTheme.Palette.ink)
            .padding(.vertical, BlitzTheme.Layout.stackGap)
    }

    private var paginationDots: some View {
        HStack(spacing: BlitzTheme.Layout.tightGap) {
            ForEach(0..<model.rows.count, id: \.self) { index in
                Circle()
                    .fill(index == currentWorldIndex ? BlitzTheme.Palette.velocity : BlitzTheme.Palette.rule)
                    .frame(width: BlitzTheme.Layout.paginationDotSize, height: BlitzTheme.Layout.paginationDotSize)
            }
        }
        .padding(.bottom, BlitzTheme.Layout.gutter)
    }
}

/// Lets a plain String drive `fullScreenCover(item:)`.
extension String: @retroactive Identifiable {
    public var id: String { self }
}

// MARK: - Planetoid container

struct PlanetoidContainer: View {
    let row: WorldMapViewModel.LevelRow
    let scrollProxy: ScrollViewProxy
    let onSelectModule: (String) -> Void
    /// Fires when the level's card is tapped while locked (FR-NAV-003, FR-NAV-004).
    var onLockedTap: () -> Void = {}

    var body: some View {
        ZStack(alignment: .center) {
            // Planetoid shape
            PlanetoidShape(worldID: row.level.levelID)
                .fill(worldFill)
                .stroke(worldOutline, lineWidth: 2.5)

            // Decorative elements per world (placeholder for now)
            worldDecorations

            // Level cards overlay in positions
            levelCardsOverlay
        }
        .frame(width: BlitzTheme.Layout.worldDiameter, height: BlitzTheme.Layout.worldDiameter)
        .id(row.level.levelID)
    }

    private var worldFill: Color {
        switch row.level.levelID.uppercased() {
        case "A": return BlitzTheme.WorldPalette.a.fill
        case "B": return BlitzTheme.WorldPalette.b.fill
        case "C": return BlitzTheme.WorldPalette.c.fill
        case "D": return BlitzTheme.WorldPalette.d.fill
        case "E": return BlitzTheme.WorldPalette.e.fill
        case "F": return BlitzTheme.WorldPalette.f.fill
        default: return BlitzTheme.WorldPalette.a.fill
        }
    }

    private var worldOutline: Color {
        switch row.level.levelID.uppercased() {
        case "A": return BlitzTheme.WorldPalette.a.outline
        case "B": return BlitzTheme.WorldPalette.b.outline
        case "C": return BlitzTheme.WorldPalette.c.outline
        case "D": return BlitzTheme.WorldPalette.d.outline
        case "E": return BlitzTheme.WorldPalette.e.outline
        case "F": return BlitzTheme.WorldPalette.f.outline
        default: return BlitzTheme.WorldPalette.a.outline
        }
    }

    @ViewBuilder
    private var worldDecorations: some View {
        // Placeholder: decorations per design brief (triangles for A, blocks for B, arrays for C, etc.)
        // Will be implemented in Task 5 refinement if needed
        EmptyView()
    }

    private var levelCardsOverlay: some View {
        VStack(spacing: BlitzTheme.Layout.tightGap) {
            HStack(spacing: BlitzTheme.Layout.tightGap) {
                // TODO(Task 6): navigate to LevelDetailView on unlocked tap
                // instead of launching a session directly.
                WorldLevelCard(row: row, worldID: row.level.levelID) { moduleID in
                    onSelectModule(moduleID)
                } onLockedTap: {
                    onLockedTap()
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("World map") {
    let curriculum = MockCurriculumProvider()
    let store = MockProgressStore()
    return WorldMapView(
        model: WorldMapViewModel(curriculum: curriculum, store: store),
        makeSessionController: { LevelSessionController(curriculum: curriculum, store: store) }
    )
}
