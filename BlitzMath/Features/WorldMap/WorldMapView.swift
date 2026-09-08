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

    init(model: WorldMapViewModel, makeSessionController: @escaping () -> LevelSessionController) {
        _model = State(initialValue: model)
        self.makeSessionController = makeSessionController
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: BlitzTheme.Layout.stackGap) {
                    ForEach(model.rows) { row in
                        LevelCard(row: row) { moduleID in
                            guard row.isUnlocked else { return }
                            activeModuleID = moduleID
                        }
                    }
                }
                .padding(BlitzTheme.Layout.gutter)
            }
            .background(GraphPaperGrid().ignoresSafeArea())
            .navigationTitle("BlitzMath")
            .task { model.refresh() }
            .fullScreenCover(item: $activeModuleID) { moduleID in
                LevelSessionView(moduleID: moduleID, controller: makeSessionController())
                    .onDisappear { model.refresh() }
            }
        }
    }
}

/// Lets a plain String drive `fullScreenCover(item:)`.
extension String: @retroactive Identifiable {
    public var id: String { self }
}

// MARK: - Level card

struct LevelCard: View {
    let row: WorldMapViewModel.LevelRow
    let onSelectModule: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BlitzTheme.Layout.tightGap) {
            header

            if let requirementText = row.requirementText {
                Text(requirementText)
                    .font(BlitzTheme.Typography.body)
                    .foregroundStyle(BlitzTheme.Palette.inkSecondary)
            } else {
                ForEach(row.level.modules) { module in
                    ModuleRow(module: module,
                              summary: row.summary(for: module.id),
                              isEnabled: row.isUnlocked) {
                        onSelectModule(module.id)
                    }
                }
            }
        }
        .padding(BlitzTheme.Layout.gutter)
        .background(
            RoundedRectangle(cornerRadius: BlitzTheme.Layout.cardRadius)
                .fill(BlitzTheme.Palette.surface.opacity(row.isUnlocked ? 1 : 0.7))
                .stroke(BlitzTheme.Palette.rule, lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("World \(row.level.levelID)")
                .font(BlitzTheme.Typography.caption)
                .foregroundStyle(BlitzTheme.Palette.inkSecondary)
            Text(row.level.levelName)
                .font(BlitzTheme.Typography.title)
                .foregroundStyle(row.isUnlocked ? BlitzTheme.Palette.ink : BlitzTheme.Palette.locked)
            Spacer()
            // Lock state carried by text and shape, not colour alone (FR-NAV-002).
            Label(stateText, systemImage: stateSymbol)
                .labelStyle(.iconOnly)
                .foregroundStyle(row.isUnlocked ? BlitzTheme.Palette.velocity : BlitzTheme.Palette.locked)
                .accessibilityLabel(stateText)
        }
    }

    private var stateText: String {
        if row.isCompleted { return "Finished" }
        return row.isUnlocked ? "Open" : "Locked"
    }

    private var stateSymbol: String {
        if row.isCompleted { return "checkmark.seal" }
        return row.isUnlocked ? "play.circle" : "lock"
    }
}

// MARK: - Module row

struct ModuleRow: View {
    let module: CurriculumModule
    let summary: ModuleSummary?
    let isEnabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: BlitzTheme.Layout.stackGap) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(module.name)
                        .font(BlitzTheme.Typography.body)
                        .foregroundStyle(BlitzTheme.Palette.ink)
                    Text(detailText)
                        .font(BlitzTheme.Typography.caption)
                        .foregroundStyle(BlitzTheme.Palette.inkSecondary)
                }
                Spacer()
                if let medal = summary?.bestMedal, medal != .none {
                    MedalBadge()
                        .stroke(BlitzTheme.colour(for: medal), lineWidth: 2)
                        .frame(width: 22, height: 26)
                        .accessibilityLabel("\(medal.displayName) medal")
                }
            }
            .frame(minHeight: BlitzTheme.Layout.minimumTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    /// Explicit empty state rather than a zeroed statistic (FR-NAV-006).
    private var detailText: String {
        let target = "Target \(module.targetSCTSeconds / 60):" + String(format: "%02d", module.targetSCTSeconds % 60)
        guard let summary, summary.hasAttempt else { return "\(target). Not played yet." }
        guard let best = summary.bestTimeSeconds else { return "\(target). Played \(summary.attemptCount) times." }
        return "\(target). Best \(String(format: "%.1f", best)) s."
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
