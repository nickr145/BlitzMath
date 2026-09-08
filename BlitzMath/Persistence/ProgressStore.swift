//
//  ProgressStore.swift
//  BlitzMath
//
//  The only component that talks to SwiftData. Presentation code never
//  touches a model context directly (SRS 3.2, FR-PER).
//

import Foundation
import SwiftData

// MARK: - Protocol

/// Abstracted so the session controller can be driven by an in-memory double.
@MainActor
protocol ProgressPersisting {
    func profile() throws -> PlayerProfile
    func medalSnapshot() throws -> MedalSnapshot
    func bestMedal(forModule moduleID: String) throws -> MedalTier
    func moduleSummaries(levelID: String) throws -> [ModuleSummary]
    func unlockedLevelIDs() throws -> Set<String>

    @discardableResult
    func record(outcome: SessionOutcome,
                module: CurriculumModule,
                startedAt: Date,
                endedAt: Date,
                medal: MedalTier) throws -> SessionRecord

    func synchroniseLockStates(with levels: [CurriculumLevel]) throws -> [String]
    func resetAllProgress() throws

    // Onboarding and placement (SRS Addendum 01)

    /// True when the player has any history at all, so the placement test is
    /// never offered twice (FR-ONB-001).
    func hasAnyProgress() throws -> Bool
    func markOnboardingComplete(entryLevelID: String?) throws
    func openLevelA(in levels: [CurriculumLevel]) throws

    @discardableResult
    func applyPlacement(_ result: PlacementResult,
                        acceptedLevelID: String,
                        levels: [CurriculumLevel]) throws -> [String]
    func latestPlacementResult() throws -> PlacementResultRecord?
}

/// Flattened row for the skill tree, so views never hold model objects.
struct ModuleSummary: Sendable, Equatable, Identifiable {
    let id: String              // moduleID
    let levelID: String
    let bestMedal: MedalTier
    let bestTimeSeconds: Double?
    let attemptCount: Int
    let completionCount: Int

    var hasAttempt: Bool { attemptCount > 0 }
}

// MARK: - Store

@MainActor
final class ProgressStore: ProgressPersisting {

    private let context: ModelContext
    private var cachedProfile: PlayerProfile?

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: Profile

    /// Exactly one profile per installation (SRS FR-PER-001).
    func profile() throws -> PlayerProfile {
        if let cachedProfile { return cachedProfile }

        var descriptor = FetchDescriptor<PlayerProfile>(sortBy: [SortDescriptor(\.createdAt)])
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            cachedProfile = existing
            return existing
        }
        let created = PlayerProfile()
        context.insert(created)
        try context.save()
        cachedProfile = created
        return created
    }

    // MARK: Queries

    func medalSnapshot() throws -> MedalSnapshot {
        let records = try context.fetch(FetchDescriptor<ModuleProgressRecord>())
        var grouped: [String: [MedalTier]] = [:]
        for record in records {
            grouped[record.levelID, default: []].append(record.bestMedal)
        }
        var snapshot = MedalSnapshot()
        for (levelID, medals) in grouped {
            snapshot.set(LevelMedalCounts(medals: medals, moduleCount: medals.count), for: levelID)
        }
        return snapshot
    }

    func bestMedal(forModule moduleID: String) throws -> MedalTier {
        try moduleRecord(moduleID)?.bestMedal ?? .none
    }

    func moduleSummaries(levelID: String) throws -> [ModuleSummary] {
        let predicate = #Predicate<ModuleProgressRecord> { $0.levelID == levelID }
        let records = try context.fetch(FetchDescriptor(predicate: predicate))
        return records.map {
            ModuleSummary(id: $0.moduleID,
                          levelID: $0.levelID,
                          bestMedal: $0.bestMedal,
                          bestTimeSeconds: $0.bestTimeSeconds,
                          attemptCount: $0.attemptCount,
                          completionCount: $0.completionCount)
        }
    }

    func unlockedLevelIDs() throws -> Set<String> {
        let locked = LevelLockState.locked.rawValue
        let predicate = #Predicate<LevelProgressRecord> { $0.stateRaw != locked }
        let records = try context.fetch(FetchDescriptor(predicate: predicate))
        return Set(records.map(\.levelID))
    }

    // MARK: Writes

    /// Session record and module upsert land in one save (SRS FR-PER-002).
    @discardableResult
    func record(outcome: SessionOutcome,
                module: CurriculumModule,
                startedAt: Date,
                endedAt: Date,
                medal: MedalTier) throws -> SessionRecord {

        let player = try profile()

        let session = SessionRecord(moduleID: module.id,
                                    levelID: module.levelID,
                                    startedAt: startedAt,
                                    endedAt: endedAt,
                                    outcome: outcome,
                                    medal: medal)
        session.profile = player
        context.insert(session)

        let moduleProgress: ModuleProgressRecord
        if let existing = try moduleRecord(module.id) {
            moduleProgress = existing
        } else {
            let created = ModuleProgressRecord(moduleID: module.id, levelID: module.levelID)
            created.level = try levelRecord(module.levelID, creatingWith: .unlocked)
            context.insert(created)
            moduleProgress = created
        }
        moduleProgress.apply(outcome: outcome, medal: medal, at: endedAt)

        if !outcome.wasAbandoned {
            player.registerCompletion(on: endedAt)
        }
        player.lastActiveAt = endedAt

        try context.save()
        return session
    }

    /// Applies gate results to stored lock state. Returns levels unlocked by this call.
    func synchroniseLockStates(with levels: [CurriculumLevel]) throws -> [String] {
        let snapshot = try medalSnapshot()
        let alreadyUnlocked = try unlockedLevelIDs()
        var newlyUnlocked: [String] = []

        for level in levels {
            let record = try levelRecord(level.levelID, creatingWith: .locked)

            if ProgressionGate.isUnlocked(requirement: level.unlockRequirement, snapshot: snapshot),
               record.state == .locked {
                record.unlock()
                if !alreadyUnlocked.contains(level.levelID) {
                    newlyUnlocked.append(level.levelID)
                }
            }
            if record.state == .unlocked,
               ProgressionGate.isCompleted(level: level, snapshot: snapshot) {
                record.markCompleted()
            }
        }
        try context.save()
        return newlyUnlocked
    }

    /// Destructive. Guarded by a naming confirmation in the UI (SRS FR-PER-006).
    func resetAllProgress() throws {
        try context.delete(model: SessionRecord.self)
        try context.delete(model: ModuleProgressRecord.self)
        try context.delete(model: LevelProgressRecord.self)
        try context.delete(model: PlacementResultRecord.self)
        try context.delete(model: PlayerProfile.self)
        cachedProfile = nil
        try context.save()
        _ = try profile()
    }

    // MARK: Onboarding and placement

    /// FR-ONB-001. Cheap counts rather than full fetches.
    func hasAnyProgress() throws -> Bool {
        if try profile().hasCompletedOnboarding { return true }
        if try context.fetchCount(FetchDescriptor<SessionRecord>()) > 0 { return true }
        if try context.fetchCount(FetchDescriptor<ModuleProgressRecord>()) > 0 { return true }
        return false
    }

    func markOnboardingComplete(entryLevelID: String?) throws {
        let player = try profile()
        player.hasCompletedOnboarding = true
        if let entryLevelID { player.placementEntryLevelID = entryLevelID }
        try context.save()
    }

    /// The declined path. Level A only, nothing else opened (FR-ONB-005).
    func openLevelA(in levels: [CurriculumLevel]) throws {
        guard let entry = levels.first(where: { $0.unlockRequirement == nil }) ?? levels.first else { return }
        try levelRecord(entry.levelID, creatingWith: .locked).unlock()
        try markOnboardingComplete(entryLevelID: nil)
    }

    /// Opens every level up to and including the entry level, awards nothing,
    /// and writes the result record (FR-PLA-009, FR-PLA-010).
    @discardableResult
    func applyPlacement(_ result: PlacementResult,
                        acceptedLevelID: String,
                        levels: [CurriculumLevel]) throws -> [String] {

        let player = try profile()

        let record = PlacementResultRecord(result: result, acceptedLevelID: acceptedLevelID)
        record.profile = player
        context.insert(record)

        var opened: [String] = []
        if result.wasCompleted {
            for levelID in result.placedOutLevelIDs(levels: levels) {
                let levelRecord = try levelRecord(levelID, creatingWith: .locked)
                if levelRecord.state == .locked {
                    levelRecord.unlockByPlacement()
                    opened.append(levelID)
                }
            }
            player.hasCompletedOnboarding = true
            player.placementEntryLevelID = result.entryLevelID
        }

        try context.save()
        return opened
    }

    func latestPlacementResult() throws -> PlacementResultRecord? {
        var descriptor = FetchDescriptor<PlacementResultRecord>(
            sortBy: [SortDescriptor(\.takenAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    // MARK: Internals

    private func moduleRecord(_ moduleID: String) throws -> ModuleProgressRecord? {
        let predicate = #Predicate<ModuleProgressRecord> { $0.moduleID == moduleID }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func levelRecord(_ levelID: String,
                             creatingWith state: LevelLockState) throws -> LevelProgressRecord {
        let predicate = #Predicate<LevelProgressRecord> { $0.levelID == levelID }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first { return existing }

        let created = LevelProgressRecord(levelID: levelID, state: state)
        created.profile = try profile()
        context.insert(created)
        return created
    }
}
