//
//  PlacementScorer.swift
//  BlitzMath
//
//  Pure placement scoring (SRS Addendum 01, FR-PLA, algorithm A7).
//  No clock, no store, no view dependency.
//

import Foundation

// MARK: - Answer log

/// One answered or skipped placement question.
struct PlacementAnswerLog: Codable, Sendable, Equatable {
    let band: String
    let sectionID: String
    let wasCorrect: Bool
    let wasSkipped: Bool
    let seconds: Double
}

// MARK: - Verdict

enum BandVerdict: String, Codable, Sendable {
    case mastered
    case developing
    case notReady

    /// Plain language for the result screen. No pass and fail wording (FR-PLA-014).
    var displayName: String {
        switch self {
        case .mastered: "Comfortable"
        case .developing: "Getting there"
        case .notReady: "Not started"
        }
    }
}

// MARK: - Summaries, persisted as Codable value types

struct PlacementBandSummary: Codable, Sendable, Equatable, Identifiable {
    let band: String
    let askedCount: Int
    let correctCount: Int
    let skippedCount: Int
    let totalSeconds: Double
    let verdictRaw: String

    var id: String { band }
    var verdict: BandVerdict { BandVerdict(rawValue: verdictRaw) ?? .notReady }
    var accuracy: Double { askedCount > 0 ? Double(correctCount) / Double(askedCount) : 0 }
    var secondsPerQuestion: Double { askedCount > 0 ? totalSeconds / Double(askedCount) : .infinity }
}

struct PlacementSectionSummary: Codable, Sendable, Equatable, Identifiable {
    let sectionID: String
    let title: String
    let elapsedSeconds: Double
    let askedCount: Int
    let correctCount: Int
    let incorrectCount: Int
    let skippedCount: Int

    var id: String { sectionID }
}

// MARK: - Result

struct PlacementResult: Sendable, Equatable {
    let entryLevelID: String
    let bandSummaries: [PlacementBandSummary]
    let sectionSummaries: [PlacementSectionSummary]
    let totalSeconds: Double
    let wasCompleted: Bool

    var masteredBands: [String] {
        bandSummaries.filter { $0.verdict == .mastered }.map(\.band)
    }

    /// Every level opened by this placement, including the entry level.
    func placedOutLevelIDs(levels: [CurriculumLevel]) -> [String] {
        guard let entry = levels.first(where: { $0.levelID == entryLevelID }) else { return [entryLevelID] }
        return levels.filter { $0.resolvedOrder <= entry.resolvedOrder }.map(\.levelID)
    }
}

// MARK: - Scorer

enum PlacementScorer {

    /// Walks bands in curriculum order and stops at the first that is not mastered.
    static func score(log: [PlacementAnswerLog],
                      sections: [PlacementSectionSummary],
                      rules: [PlacementBandRule],
                      wasCompleted: Bool = true) -> PlacementResult {

        let ordered = rules.sorted { $0.order < $1.order }
        let grouped = Dictionary(grouping: log, by: \.band)

        let summaries: [PlacementBandSummary] = ordered.map { rule in
            let entries = grouped[rule.band] ?? []
            let asked = entries.count
            let correct = entries.filter(\.wasCorrect).count
            let skipped = entries.filter(\.wasSkipped).count
            let seconds = entries.reduce(0) { $0 + $1.seconds }

            return PlacementBandSummary(
                band: rule.band,
                askedCount: asked,
                correctCount: correct,
                skippedCount: skipped,
                totalSeconds: seconds,
                verdictRaw: verdict(rule: rule, asked: asked, correct: correct, seconds: seconds).rawValue
            )
        }

        let entryLevelID = entryLevel(summaries: summaries, rules: ordered)

        return PlacementResult(
            entryLevelID: entryLevelID,
            bandSummaries: summaries,
            sectionSummaries: sections,
            totalSeconds: sections.reduce(0) { $0 + $1.elapsedSeconds },
            wasCompleted: wasCompleted
        )
    }

    /// FR-PLA-004 to FR-PLA-006.
    static func verdict(rule: PlacementBandRule, asked: Int, correct: Int, seconds: Double) -> BandVerdict {
        guard asked > 0 else { return .notReady }

        let accuracy = Double(correct) / Double(asked)
        let pace = seconds / Double(asked)

        if asked >= rule.resolvedMinimumQuestions,
           accuracy >= rule.resolvedMasteryAccuracy,
           pace <= rule.paceSecondsPerQuestion {
            return .mastered
        }
        if accuracy >= rule.resolvedDevelopingAccuracy {
            return .developing
        }
        return .notReady
    }

    /// FR-PLA-007 and FR-PLA-008.
    static func entryLevel(summaries: [PlacementBandSummary], rules: [PlacementBandRule]) -> String {
        let ordered = rules.sorted { $0.order < $1.order }
        let verdictsByBand = Dictionary(uniqueKeysWithValues: summaries.map { ($0.band, $0.verdict) })

        for rule in ordered where verdictsByBand[rule.band] != .mastered {
            return rule.entryLevelID
        }
        return ordered.last?.entryLevelID ?? "A"
    }

    /// One line for the result screen, written for the player rather than the scorer.
    static func explanation(for result: PlacementResult, levelName: String) -> String {
        let comfortable = result.masteredBands
        if comfortable.isEmpty {
            return "You are starting at the beginning, in \(levelName). That is where everything is built from."
        }
        let list = comfortable.count == 1
            ? "World \(comfortable[0])"
            : "Worlds \(comfortable.dropLast().joined(separator: ", ")) and \(comfortable.last ?? "")"
        return "\(list) looked comfortable, so you are starting at \(levelName). Everything before it stays open if you want to go back."
    }
}
