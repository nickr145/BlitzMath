//
//  PlayerModels.swift
//  BlitzMath
//
//  SwiftData model layer for local player state (SRS 4.3).
//  Enumerations are stored as raw strings and surfaced through computed
//  properties, so adding a case never forces a store migration.
//

import Foundation
import SwiftData

// MARK: - Player profile

@Model
final class PlayerProfile {


    @Attribute(.unique) var id: UUID = UUID()
    var displayName: String = "Player"
    var createdAt: Date = Date()
    var lastActiveAt: Date = Date()

    var currentStreakDays: Int = 0
    var longestStreakDays: Int = 0
    var lastCompletionDay: Date?

    var reducedMotionOverride: Bool = false
    var hapticsEnabled: Bool = true

    /// Onboarding is settled once the player takes the placement test, declines
    /// it, or arrives with existing progress (Addendum FR-ONB-001).
    var hasCompletedOnboarding: Bool = false
    /// Null when the test was declined or never taken.
    var placementEntryLevelID: String?

    @Relationship(deleteRule: .cascade, inverse: \LevelProgressRecord.profile)
    var levelProgress: [LevelProgressRecord] = []

    @Relationship(deleteRule: .cascade, inverse: \SessionRecord.profile)
    var sessions: [SessionRecord] = []

    init(displayName: String = "Player") {
        self.id = UUID()
        self.displayName = displayName
        self.createdAt = Date()
        self.lastActiveAt = Date()
    }

    /// Streak update on a completed session. Calendar-day granularity.
    func registerCompletion(on date: Date, calendar: Calendar = .current) {
        defer { lastCompletionDay = calendar.startOfDay(for: date) }
        let today = calendar.startOfDay(for: date)

        guard let previous = lastCompletionDay else {
            currentStreakDays = 1
            longestStreakDays = max(longestStreakDays, 1)
            return
        }
        let dayDelta = calendar.dateComponents([.day], from: previous, to: today).day ?? 0
        switch dayDelta {
        case 0: break                       // already counted today
        case 1: currentStreakDays += 1
        default: currentStreakDays = 1      // streak broken
        }
        longestStreakDays = max(longestStreakDays, currentStreakDays)
    }
}

// MARK: - Level progress

@Model
final class LevelProgressRecord {

    var levelID: String = ""
    var stateRaw: String = LevelLockState.locked.rawValue
    var unlockedAt: Date?
    var completedAt: Date?
    /// Distinguishes a level opened by placement from one opened by earning
    /// medals (Addendum FR-PLA-009). No medals are implied either way.
    var unlockedByPlacement: Bool = false

    var profile: PlayerProfile?

    @Relationship(deleteRule: .cascade, inverse: \ModuleProgressRecord.level)
    var moduleProgress: [ModuleProgressRecord] = []

    var state: LevelLockState {
        get { LevelLockState(rawValue: stateRaw) ?? .locked }
        set { stateRaw = newValue.rawValue }
    }

    init(levelID: String, state: LevelLockState = .locked) {
        self.levelID = levelID
        self.stateRaw = state.rawValue
        if state != .locked { self.unlockedAt = Date() }
    }

    /// A level never returns to locked (SRS IV-04).
    func unlock(at date: Date = Date()) {
        guard state == .locked else { return }
        state = .unlocked
        unlockedAt = date
    }

    /// Opened by the placement test rather than by medals. Never relocks a
    /// level and never overwrites an earned unlock.
    func unlockByPlacement(at date: Date = Date()) {
        guard state == .locked else { return }
        state = .unlocked
        unlockedAt = date
        unlockedByPlacement = true
    }

    func markCompleted(at date: Date = Date()) {
        guard state != .completed else { return }
        if unlockedAt == nil { unlockedAt = date }
        state = .completed
        completedAt = date
    }
}

// MARK: - Module progress

@Model
final class ModuleProgressRecord {

    var moduleID: String = ""
    /// Denormalised so medal aggregation for a gate needs no join (SRS 4.3.3).
    var levelID: String = ""

    var bestMedalRaw: String = MedalTier.none.rawValue
    var bestTimeSeconds: Double?
    var lastTimeSeconds: Double?
    var bestAccuracy: Double = 0

    var attemptCount: Int = 0
    var completionCount: Int = 0
    var firstCompletedAt: Date?
    var lastAttemptAt: Date?

    var level: LevelProgressRecord?

    var bestMedal: MedalTier {
        get { MedalTier.fromStored(bestMedalRaw) }
        set { bestMedalRaw = newValue.rawValue }
    }

    init(moduleID: String, levelID: String) {
        self.moduleID = moduleID
        self.levelID = levelID
    }

    /// Best-result upsert (SRS 9.3). Medals and best times are monotonic.
    func apply(outcome: SessionOutcome, medal: MedalTier, at date: Date = Date()) {
        attemptCount += 1
        lastAttemptAt = date

        guard !outcome.wasAbandoned else { return }

        completionCount += 1
        lastTimeSeconds = outcome.elapsedSeconds
        bestAccuracy = max(bestAccuracy, outcome.accuracy)

        if medal.rank > bestMedal.rank {
            bestMedal = medal
        }
        if outcome.isFlawless, bestTimeSeconds == nil || outcome.elapsedSeconds < (bestTimeSeconds ?? .infinity) {
            bestTimeSeconds = outcome.elapsedSeconds
        }
        if firstCompletedAt == nil {
            firstCompletedAt = date
        }
    }
}

// MARK: - Session history

@Model
final class SessionRecord {


    @Attribute(.unique) var id: UUID = UUID()
    var moduleID: String = ""
    var levelID: String = ""

    var startedAt: Date = Date()
    var endedAt: Date?
    var elapsedSeconds: Double = 0

    var questionCount: Int = 0
    var correctFirstTryCount: Int = 0
    var incorrectAttemptCount: Int = 0
    var hintsUsed: Int = 0

    var medalRaw: String = MedalTier.none.rawValue
    var wasAbandoned: Bool = false
    /// Retained so history survives SCT retuning (SRS DM-04).
    var sctSecondsAtRun: Int = 0

    var profile: PlayerProfile?

    var medal: MedalTier {
        get { MedalTier.fromStored(medalRaw) }
        set { medalRaw = newValue.rawValue }
    }

    var accuracy: Double {
        questionCount > 0 ? Double(correctFirstTryCount) / Double(questionCount) : 0
    }

    init(moduleID: String,
         levelID: String,
         startedAt: Date,
         endedAt: Date?,
         outcome: SessionOutcome,
         medal: MedalTier) {
        self.id = UUID()
        self.moduleID = moduleID
        self.levelID = levelID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.elapsedSeconds = outcome.elapsedSeconds
        self.questionCount = outcome.questionCount
        self.correctFirstTryCount = outcome.correctFirstTryCount
        self.incorrectAttemptCount = outcome.incorrectAttemptCount
        self.hintsUsed = outcome.hintsUsed
        self.wasAbandoned = outcome.wasAbandoned
        self.sctSecondsAtRun = outcome.sctSeconds
        self.medalRaw = medal.rawValue
    }
}

// MARK: - Placement history

/// Written once when the placement test finishes or is left partway.
/// Never mutated (Addendum A4.2).
@Model
final class PlacementResultRecord {


    @Attribute(.unique) var id: UUID = UUID()
    var takenAt: Date = Date()
    var wasCompleted: Bool = false

    /// What the scorer decided.
    var entryLevelID: String = "A"
    /// What the player actually started at, which may be lower by choice.
    var acceptedLevelID: String = "A"
    var totalSeconds: Double = 0

    var sectionSummaries: [PlacementSectionSummary] = []
    var bandSummaries: [PlacementBandSummary] = []

    var profile: PlayerProfile?

    init(result: PlacementResult, acceptedLevelID: String, takenAt: Date = Date()) {
        self.id = UUID()
        self.takenAt = takenAt
        self.wasCompleted = result.wasCompleted
        self.entryLevelID = result.entryLevelID
        self.acceptedLevelID = acceptedLevelID
        self.totalSeconds = result.totalSeconds
        self.sectionSummaries = result.sectionSummaries
        self.bandSummaries = result.bandSummaries
    }
}

// MARK: - Schema and migration

enum BlitzSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [PlayerProfile.self, LevelProgressRecord.self, ModuleProgressRecord.self,
         SessionRecord.self, PlacementResultRecord.self]
    }
}

/// Declared from the first release so later versions have a home (SRS DM-01).
enum BlitzMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [BlitzSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

// MARK: - Container

enum BlitzModelContainer {

    /// Local-only store. CloudKit is explicitly disabled (SRS FR-PER-004).
    static func make(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "BlitzMathStore",
            schema: Schema(BlitzSchemaV1.models),
            isStoredInMemoryOnly: inMemory,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: Schema(BlitzSchemaV1.models),
            migrationPlan: BlitzMigrationPlan.self,
            configurations: [configuration]
        )
    }

    /// Previews and unit tests.
    static func preview() -> ModelContainer {
        do { return try make(inMemory: true) }
        catch { fatalError("In-memory container failed to build: \(error)") }
    }
}
