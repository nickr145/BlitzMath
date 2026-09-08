//
//  MedalEvaluator.swift
//  BlitzMath
//
//  Pure medal award logic. No SwiftUI, no SwiftData, no clock access (SRS FR-MED-007).
//

import Foundation

// MARK: - Medal tier

enum MedalTier: String, Codable, Sendable, CaseIterable, Comparable {
    case none
    case bronze
    case silver
    case gold

    /// Ordering used for the monotonic best-medal rule (SRS IV-01).
    var rank: Int {
        switch self {
        case .none: 0
        case .bronze: 1
        case .silver: 2
        case .gold: 3
        }
    }

    /// Only gold and silver advance a Milestone Gate (SRS FR-MED-003).
    var isQualifying: Bool { self == .gold || self == .silver }

    var displayName: String {
        switch self {
        case .none: "No medal"
        case .bronze: "Bronze"
        case .silver: "Silver"
        case .gold: "Gold"
        }
    }

    static func < (lhs: MedalTier, rhs: MedalTier) -> Bool { lhs.rank < rhs.rank }

    static func fromStored(_ raw: String) -> MedalTier { MedalTier(rawValue: raw) ?? .none }
}

// MARK: - Session outcome

/// Everything the evaluator needs, and nothing else.
struct SessionOutcome: Sendable, Equatable {
    let elapsedSeconds: TimeInterval
    let sctSeconds: Int
    let questionCount: Int
    let correctFirstTryCount: Int
    let incorrectAttemptCount: Int
    let hintsUsed: Int
    let wasAbandoned: Bool

    var accuracy: Double {
        guard questionCount > 0 else { return 0 }
        return Double(correctFirstTryCount) / Double(questionCount)
    }

    /// SRS FR-MED-005.
    var isFlawless: Bool { incorrectAttemptCount == 0 && hintsUsed == 0 }

    var isInsideSCT: Bool { elapsedSeconds <= TimeInterval(sctSeconds) }

    /// Signed seconds against the target. Negative is faster than the SCT.
    var sctDelta: TimeInterval { elapsedSeconds - TimeInterval(sctSeconds) }
}

// MARK: - Evaluator

enum MedalEvaluator {

    /// Minimum accuracy for a bronze completion marker.
    static let bronzeAccuracyThreshold = 0.80

    /// Total, pure, side effect free.
    static func award(for outcome: SessionOutcome) -> MedalTier {
        guard !outcome.wasAbandoned else { return .none }

        if outcome.isFlawless {
            return outcome.isInsideSCT ? .gold : .silver
        }
        if outcome.accuracy >= bronzeAccuracyThreshold {
            return .bronze
        }
        return .none
    }

    /// Plain-language reason shown on the summary screen.
    static func rationale(for outcome: SessionOutcome, medal: MedalTier) -> String {
        switch medal {
        case .gold:
            "Perfect run, finished with \(Self.format(-outcome.sctDelta)) to spare."
        case .silver:
            "Perfect run, \(Self.format(outcome.sctDelta)) over the target time."
        case .bronze:
            "Finished at \(Int(outcome.accuracy * 100)) percent accuracy. A clean run earns silver or gold."
        case .none:
            outcome.wasAbandoned
                ? "Left before the last question."
                : "Accuracy was \(Int(outcome.accuracy * 100)) percent. Reach 80 percent to finish the module."
        }
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let value = max(0, seconds)
        return value < 60
            ? String(format: "%.1f s", value)
            : String(format: "%d min %02d s", Int(value) / 60, Int(value) % 60)
    }
}
