//
//  ProgressReviewView.swift
//  BlitzMath
//
//  Read-only medal and progress summary across every World, reached from
//  the Skill Tree. Consumes ProgressStore only, no writes happen here
//  (SRS FR-NAV, layer rule: Presentation depends on Data Access only).
//

import SwiftUI

struct ProgressReviewView: View {
    let curriculum: CurriculumProviding
    let store: ProgressPersisting

    @State private var medalSnapshot: MedalSnapshot?
    @State private var moduleSummariesByWorld: [String: [ModuleSummary]] = [:]
    @State private var loadError: String?

    @Environment(\.dismiss) private var dismiss

    /// Worlds come from the bundled curriculum, in `level_order`, so a content
    /// change needs no Swift change (SRS FR-CUR-005, FR-NAV-001).
    private var worldIDs: [String] {
        curriculum.payload.orderedLevels.map(\.levelID)
    }

    var body: some View {
        VStack(spacing: BlitzTheme.Layout.stackGap) {
            HStack {
                Text("Progress")
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

            if let error = loadError {
                Text(error)
                    .font(BlitzTheme.Typography.body)
                    .foregroundStyle(BlitzTheme.Palette.overTarget)
                    .padding(BlitzTheme.Layout.gutter)
            } else if let snapshot = medalSnapshot {
                ScrollView {
                    VStack(spacing: BlitzTheme.Layout.stackGap) {
                        ForEach(worldIDs, id: \.self) { worldID in
                            WorldProgressRow(worldID: worldID,
                                             counts: snapshot.counts(for: worldID),
                                             summaries: moduleSummariesByWorld[worldID] ?? [])
                        }
                    }
                    .padding(BlitzTheme.Layout.gutter)
                }
            }

            Spacer()
        }
        .background(GraphPaperGrid().ignoresSafeArea())
        .task { loadProgress() }
    }

    private func loadProgress() {
        do {
            let snapshot = try store.medalSnapshot()
            var summaries: [String: [ModuleSummary]] = [:]
            for worldID in worldIDs {
                summaries[worldID] = try store.moduleSummaries(levelID: worldID)
            }
            medalSnapshot = snapshot
            moduleSummariesByWorld = summaries
        } catch {
            loadError = "Could not load progress"
        }
    }
}

/// One World's medal counts and module-attempt total.
private struct WorldProgressRow: View {
    let worldID: String
    let counts: LevelMedalCounts
    let summaries: [ModuleSummary]

    private var attemptedCount: Int { summaries.filter(\.hasAttempt).count }
    private var hasAnyMedal: Bool { counts.gold > 0 || counts.silver > 0 || counts.bronze > 0 }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: BlitzTheme.Layout.tightGap) {
                Text("World \(worldID)")
                    .font(BlitzTheme.Typography.body)
                    .foregroundStyle(BlitzTheme.Palette.ink)
                if !summaries.isEmpty {
                    Text("\(attemptedCount) of \(summaries.count) modules started")
                        .font(BlitzTheme.Typography.caption)
                        .foregroundStyle(BlitzTheme.Palette.inkSecondary)
                }
            }

            Spacer()

            if hasAnyMedal {
                HStack(spacing: BlitzTheme.Layout.tightGap) {
                    if counts.gold > 0 {
                        Label("\(counts.gold)", systemImage: "star.fill")
                            .font(BlitzTheme.Typography.caption)
                            .foregroundStyle(BlitzTheme.Palette.gold)
                    }
                    if counts.silver > 0 {
                        Label("\(counts.silver)", systemImage: "star.fill")
                            .font(BlitzTheme.Typography.caption)
                            .foregroundStyle(BlitzTheme.Palette.silver)
                    }
                    if counts.bronze > 0 {
                        Label("\(counts.bronze)", systemImage: "star.fill")
                            .font(BlitzTheme.Typography.caption)
                            .foregroundStyle(BlitzTheme.Palette.bronze)
                    }
                }
            } else {
                Text("No medals yet")
                    .font(BlitzTheme.Typography.caption)
                    .foregroundStyle(BlitzTheme.Palette.inkSecondary)
            }
        }
        .padding(BlitzTheme.Layout.gutter)
        .frame(minHeight: BlitzTheme.Layout.minimumTarget)
        .background(RoundedRectangle(cornerRadius: BlitzTheme.Layout.cardRadius)
            .fill(BlitzTheme.Palette.surface))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = ["World \(worldID)"]
        if counts.gold > 0 { parts.append("\(counts.gold) gold") }
        if counts.silver > 0 { parts.append("\(counts.silver) silver") }
        if counts.bronze > 0 { parts.append("\(counts.bronze) bronze") }
        if !hasAnyMedal { parts.append("no medals yet") }
        if !summaries.isEmpty {
            parts.append("\(attemptedCount) of \(summaries.count) modules started")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Preview

#Preview {
    ProgressReviewView(curriculum: MockCurriculumProvider(), store: MockProgressStore())
}
