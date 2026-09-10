//
//  LevelDetailView.swift
//  BlitzMath
//
//  Module list for one World, reached from an unlocked level card on the
//  Skill Tree. Lists the World's modules with target SCT and best medal,
//  and hands off to a drill session (SRS FR-NAV).
//

import SwiftUI

struct LevelDetailView: View {
    let row: WorldMapViewModel.LevelRow
    private let makeSessionController: () -> LevelSessionController

    @State private var activeModuleID: String?
    @Environment(\.dismiss) private var dismiss

    init(row: WorldMapViewModel.LevelRow, makeSessionController: @escaping () -> LevelSessionController) {
        self.row = row
        self.makeSessionController = makeSessionController
    }

    var body: some View {
        VStack(spacing: BlitzTheme.Layout.stackGap) {
            HStack {
                Text("World \(row.level.levelID)")
                    .font(BlitzTheme.Typography.title)
                    .foregroundStyle(BlitzTheme.Palette.ink)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(BlitzTheme.Typography.closeIcon)
                        .foregroundStyle(BlitzTheme.Palette.inkSecondary)
                }
                .frame(minWidth: BlitzTheme.Layout.minimumTarget, minHeight: BlitzTheme.Layout.minimumTarget)
                .accessibilityLabel("Close")
            }
            .padding(BlitzTheme.Layout.gutter)

            Text(row.level.levelName)
                .font(BlitzTheme.Typography.body)
                .foregroundStyle(BlitzTheme.Palette.inkSecondary)
                .padding(.horizontal, BlitzTheme.Layout.gutter)

            Divider()
                .background(BlitzTheme.Palette.rule)

            ScrollView {
                VStack(spacing: BlitzTheme.Layout.stackGap) {
                    ForEach(row.level.modules) { module in
                        ModuleDetailRow(module: module, summary: row.summary(for: module.id)) {
                            activeModuleID = module.id
                        }
                    }
                }
                .padding(BlitzTheme.Layout.gutter)
            }

            Spacer()
        }
        .background(GraphPaperGrid().ignoresSafeArea())
        .fullScreenCover(item: $activeModuleID) { moduleID in
            LevelSessionView(moduleID: moduleID, controller: makeSessionController())
        }
    }
}

struct ModuleDetailRow: View {
    let module: CurriculumModule
    let summary: ModuleSummary?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: BlitzTheme.Layout.tightGap) {
                HStack {
                    Text(module.name)
                        .font(BlitzTheme.Typography.body)
                        .foregroundStyle(BlitzTheme.Palette.ink)
                    Spacer()
                    if let medal = summary?.bestMedal, medal != .none {
                        MedalBadge()
                            .stroke(BlitzTheme.colour(for: medal),
                                    lineWidth: BlitzTheme.Layout.moduleMedalStrokeWidth)
                            .frame(width: BlitzTheme.Layout.moduleMedalWidth,
                                   height: BlitzTheme.Layout.moduleMedalHeight)
                            .accessibilityLabel("\(medal.displayName) medal")
                    }
                }

                Text(detailText)
                    .font(BlitzTheme.Typography.caption)
                    .foregroundStyle(BlitzTheme.Palette.inkSecondary)
            }
            .padding(BlitzTheme.Layout.gutter)
            .background(RoundedRectangle(cornerRadius: BlitzTheme.Layout.cardRadius)
                .fill(BlitzTheme.Palette.surface))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minHeight: BlitzTheme.Layout.minimumTarget)
    }

    /// Target SCT plus an explicit empty state rather than a zeroed statistic
    /// (SRS FR-NAV-005, FR-NAV-006).
    private var detailText: String {
        let target = "Target \(module.targetSCTSeconds / 60):"
            + String(format: "%02d", module.targetSCTSeconds % 60)
        guard let summary, summary.hasAttempt else { return "\(target). Not played yet." }
        guard let best = summary.bestTimeSeconds else {
            return "\(target). Played \(summary.attemptCount) times."
        }
        return "\(target). Best \(String(format: "%.1f", best)) s."
    }
}

// MARK: - Preview

#Preview {
    let curriculum = MockCurriculumProvider()
    let store = MockProgressStore()
    let model = WorldMapViewModel(curriculum: curriculum, store: store)
    model.refresh()

    return Group {
        if let row = model.rows.first {
            LevelDetailView(row: row, makeSessionController: {
                LevelSessionController(curriculum: curriculum, store: store)
            })
        } else {
            EmptyView()
        }
    }
}
