//
//  ProgressionGate.swift
//  BlitzMath
//
//  Pure Milestone Gate evaluation (SRS FR-GATE, algorithm 9.2).
//

import Foundation

// MARK: - Snapshot

/// Medal counts for one Level, derived from persisted best-medal rows.
struct LevelMedalCounts: Sendable, Equatable {
    var gold = 0
    var silver = 0
    var bronze = 0
    var moduleCount = 0

    var qualifying: Int { gold + silver }

    init(gold: Int = 0, silver: Int = 0, bronze: Int = 0, moduleCount: Int = 0) {
        self.gold = gold
        self.silver = silver
        self.bronze = bronze
        self.moduleCount = moduleCount
    }

    init(medals: [MedalTier], moduleCount: Int) {
        self.moduleCount = moduleCount
        for medal in medals {
            switch medal {
            case .gold: gold += 1
            case .silver: silver += 1
            case .bronze: bronze += 1
            case .none: break
            }
        }
    }
}

/// The persisted view of progress that gate evaluation reads (SRS FR-GATE-003).
struct MedalSnapshot: Sendable, Equatable {
    private var countsByLevel: [String: LevelMedalCounts]

    init(countsByLevel: [String: LevelMedalCounts] = [:]) {
        self.countsByLevel = countsByLevel
    }

    func counts(for levelID: String) -> LevelMedalCounts {
        countsByLevel[levelID] ?? LevelMedalCounts()
    }

    mutating func set(_ counts: LevelMedalCounts, for levelID: String) {
        countsByLevel[levelID] = counts
    }
}

// MARK: - Lock state

enum LevelLockState: String, Codable, Sendable {
    case locked
    case unlocked
    case completed
}

// MARK: - Gate

enum ProgressionGate {

    /// Whether the requirement is satisfied by persisted progress.
    static func isUnlocked(requirement: UnlockRequirement?, snapshot: MedalSnapshot) -> Bool {
        guard let requirement else { return true }   // entry point, FR-GATE-001
        let counts = snapshot.counts(for: requirement.sourceLevelID)
        return counts.qualifying >= requirement.requiredMedalCount
            && counts.gold >= requirement.resolvedGoldCount
    }

    /// How far the player still has to go, for the locked-level message (FR-NAV-003).
    static func remaining(for requirement: UnlockRequirement, snapshot: MedalSnapshot) -> (medals: Int, gold: Int) {
        let counts = snapshot.counts(for: requirement.sourceLevelID)
        return (
            medals: max(0, requirement.requiredMedalCount - counts.qualifying),
            gold: max(0, requirement.resolvedGoldCount - counts.gold)
        )
    }

    /// Player-facing requirement text. Written for a young reader, no jargon.
    static func requirementText(for requirement: UnlockRequirement,
                                sourceLevelName: String,
                                snapshot: MedalSnapshot) -> String {
        let outstanding = remaining(for: requirement, snapshot: snapshot)
        if outstanding.medals == 0 && outstanding.gold == 0 { return "Ready to open." }

        var parts: [String] = []
        if outstanding.medals > 0 {
            parts.append("\(outstanding.medals) more \(outstanding.medals == 1 ? "medal" : "medals")")
        }
        if outstanding.gold > 0 {
            parts.append("\(outstanding.gold) more gold")
        }
        return "Earn \(parts.joined(separator: " and ")) in \(sourceLevelName) to open this world."
    }

    /// Levels that become unlocked under the new snapshot but were locked before.
    /// An unlocked level never reverts (SRS FR-GATE-006, IV-04).
    static func newlyUnlocked(levels: [CurriculumLevel],
                              previouslyUnlocked: Set<String>,
                              snapshot: MedalSnapshot) -> [CurriculumLevel] {
        levels.filter { level in
            !previouslyUnlocked.contains(level.levelID)
            && isUnlocked(requirement: level.unlockRequirement, snapshot: snapshot)
        }
    }

    /// A level is complete when every module holds a qualifying medal.
    static func isCompleted(level: CurriculumLevel, snapshot: MedalSnapshot) -> Bool {
        let counts = snapshot.counts(for: level.levelID)
        return counts.qualifying >= level.modules.count && !level.modules.isEmpty
    }
}
