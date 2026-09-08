//
//  DomainTests.swift
//  BlitzMathTests
//
//  Skeletons traced to the acceptance criteria in SRS section 11.
//

import Testing
import Foundation
@testable import BlitzMath

// MARK: - Medal evaluation (AC-02, AC-03)

@Suite("Medal evaluation")
struct MedalEvaluatorTests {

    private func outcome(elapsed: TimeInterval,
                         sct: Int = 240,
                         questions: Int = 20,
                         correct: Int = 20,
                         incorrect: Int = 0,
                         hints: Int = 0,
                         abandoned: Bool = false) -> SessionOutcome {
        SessionOutcome(elapsedSeconds: elapsed, sctSeconds: sct, questionCount: questions,
                       correctFirstTryCount: correct, incorrectAttemptCount: incorrect,
                       hintsUsed: hints, wasAbandoned: abandoned)
    }

    @Test("Flawless inside the SCT awards gold")
    func goldInsideSCT() {
        #expect(MedalEvaluator.award(for: outcome(elapsed: 239)) == .gold)
    }

    @Test("Flawless outside the SCT awards silver")
    func silverOutsideSCT() {
        #expect(MedalEvaluator.award(for: outcome(elapsed: 241)) == .silver)
    }

    @Test("Exactly on the SCT still awards gold")
    func goldOnBoundary() {
        #expect(MedalEvaluator.award(for: outcome(elapsed: 240)) == .gold)
    }

    @Test("Mistakes at 85 percent accuracy award bronze, which does not qualify")
    func bronzeIsNotQualifying() {
        let medal = MedalEvaluator.award(for: outcome(elapsed: 100, correct: 17, incorrect: 3))
        #expect(medal == .bronze)
        #expect(medal.isQualifying == false)
    }

    @Test("Accuracy below the threshold awards nothing")
    func noMedalBelowThreshold() {
        #expect(MedalEvaluator.award(for: outcome(elapsed: 100, correct: 12, incorrect: 8)) == .none)
    }

    @Test("A hint disqualifies gold")
    func hintBlocksGold() {
        #expect(MedalEvaluator.award(for: outcome(elapsed: 60, hints: 1)) == .bronze)
    }

    @Test("An abandoned session awards nothing")
    func abandonedAwardsNothing() {
        #expect(MedalEvaluator.award(for: outcome(elapsed: 10, correct: 20, abandoned: true)) == .none)
    }
}

// MARK: - Milestone gate (AC-04)

@Suite("Milestone gate")
struct ProgressionGateTests {

    private let requirement = UnlockRequirement(sourceLevelID: "D", requiredMedalCount: 4, requiredGoldCount: 1)

    private func snapshot(gold: Int, silver: Int) -> MedalSnapshot {
        var snapshot = MedalSnapshot()
        snapshot.set(LevelMedalCounts(gold: gold, silver: silver, moduleCount: 4), for: "D")
        return snapshot
    }

    @Test("A null requirement is an entry point")
    func entryPointIsOpen() {
        #expect(ProgressionGate.isUnlocked(requirement: nil, snapshot: MedalSnapshot()))
    }

    @Test("Three qualifying medals is not enough")
    func staysLockedBelowThreshold() {
        #expect(ProgressionGate.isUnlocked(requirement: requirement, snapshot: snapshot(gold: 1, silver: 2)) == false)
    }

    @Test("Four qualifying medals with one gold opens the level")
    func unlocksAtThreshold() {
        #expect(ProgressionGate.isUnlocked(requirement: requirement, snapshot: snapshot(gold: 1, silver: 3)))
    }

    @Test("Four silver medals without gold stays locked")
    func goldSubsetIsEnforced() {
        #expect(ProgressionGate.isUnlocked(requirement: requirement, snapshot: snapshot(gold: 0, silver: 4)) == false)
    }

    @Test("Remaining counts drive the locked message")
    func remainingCounts() {
        let outstanding = ProgressionGate.remaining(for: requirement, snapshot: snapshot(gold: 0, silver: 2))
        #expect(outstanding.medals == 2)
        #expect(outstanding.gold == 1)
    }
}

// MARK: - Clock (AC-06)

@Suite("Blitz clock")
@MainActor
struct BlitzClockTests {

    @Test("Paused intervals are excluded from elapsed time")
    func pauseExcludesTime() {
        let source = ManualTimeSource()
        let clock = BlitzClock(source: source, tickInterval: .seconds(60))

        clock.start()
        source.advance(by: 10)
        clock.pause()
        source.advance(by: 300)   // five minutes in the background
        clock.resume()
        source.advance(by: 5)

        #expect(abs(clock.stop() - 15) < 0.001)
    }

    @Test("Pace crosses at 0.75 and 1.0 of the target")
    func paceThresholds() {
        let source = ManualTimeSource()
        let clock = BlitzClock(source: source, tickInterval: .seconds(60))

        clock.start()
        source.advance(by: 100)
        clock.pause()
        #expect(clock.pace(target: 200) == .comfortable)

        clock.resume()
        source.advance(by: 60)
        clock.pause()
        #expect(clock.pace(target: 200) == .tightening)

        clock.resume()
        source.advance(by: 60)
        #expect(clock.stop() > 200)
        #expect(clock.pace(target: 200) == .overTarget)
    }
}

// MARK: - Curriculum ingestion (AC-08)

@Suite("Curriculum repository")
struct CurriculumRepositoryTests {

    @Test("A valid payload indexes every module")
    func indexesModules() throws {
        let repository = try CurriculumRepository(payload: .sample)
        #expect(repository.module(id: "A_01")?.targetSCTSeconds == 120)
        #expect(repository.module(id: "E_02")?.resolvedQuestionCount == 20)
        #expect(repository.module(id: "Z_99") == nil)
    }

    @Test("An SCT outside the permitted band drops the module")
    func rejectsOutOfBandSCT() throws {
        let payload = CurriculumPayload(
            appName: "BlitzMath", version: "1.0.0", schemaVersion: "1.1",
            curriculum: [
                CurriculumLevel(levelID: "A", levelName: "Test", levelOrder: 1, unlockRequirement: nil,
                                modules: [
                                    CurriculumModule(id: "A_01", name: "Valid", targetSCTSeconds: 120,
                                                     questionCount: 20, generator: nil),
                                    CurriculumModule(id: "A_02", name: "Too long", targetSCTSeconds: 5_000,
                                                     questionCount: 20, generator: nil)
                                ])
            ])
        let repository = try CurriculumRepository(payload: payload)
        #expect(repository.module(id: "A_02") == nil)
        #expect(repository.diagnostics.contains { $0.ruleID == "DV-04" })
    }
}

// MARK: - Session controller (AC-01, AC-05)

@Suite("Level session controller")
@MainActor
struct LevelSessionControllerTests {

    private func makeController(store: MockProgressStore = MockProgressStore())
    -> (LevelSessionController, MockProgressStore, ManualTimeSource) {
        let source = ManualTimeSource()
        let controller = LevelSessionController(
            curriculum: MockCurriculumProvider(),
            store: store,
            clock: BlitzClock(source: source, tickInterval: .seconds(60)),
            seedProvider: { 1 }
        )
        return (controller, store, source)
    }

    @Test("An unknown module never starts a session")
    func unknownModuleFails() {
        let (controller, _, _) = makeController()
        controller.start(moduleID: "Z_01")
        #expect(controller.phase == .failed("That module is not in this version of the app."))
        #expect(controller.questions.isEmpty)
    }

    @Test("A flawless run inside the SCT records gold")
    func flawlessRunRecordsGold() {
        let (controller, store, _) = makeController()
        controller.start(moduleID: "A_01")

        while let question = controller.currentQuestion {
            controller.submit(correctInput(for: question))
        }

        #expect(controller.phase == .summary)
        #expect(store.recordedOutcomes.last?.medal == .gold)
    }

    @Test("A wrong answer keeps the question active and counts against flawless")
    func wrongAnswerHoldsTheQuestion() {
        let (controller, _, _) = makeController()
        controller.start(moduleID: "A_01")

        let question = try? #require(controller.currentQuestion)
        controller.submit(.integer(-9_999))

        #expect(controller.currentQuestion == question)
        #expect(controller.lastAnswerWasIncorrect)
    }

    @Test("Abandoning writes an attempt with no medal")
    func abandonWritesNoMedal() {
        let (controller, store, _) = makeController()
        controller.start(moduleID: "A_01")
        controller.abandon()

        #expect(controller.phase == .abandoned)
        #expect(store.recordedOutcomes.last?.medal == MedalTier.none)
    }

    @Test("A failed save surfaces a notice and keeps the result in memory")
    func failedSaveIsNonBlocking() {
        let store = MockProgressStore()
        store.shouldFailSaves = true
        let (controller, _, _) = makeController(store: store)

        controller.start(moduleID: "A_01")
        controller.abandon()

        #expect(controller.summary?.saveFailed == true)
        #expect(controller.saveNotice != nil)
    }

    /// Derives the correct input from the question's own answer form.
    private func correctInput(for question: Question) -> AnswerInput {
        switch question.answer {
        case .integer(let value): .integer(value)
        case .decimal(let value): .decimal(value)
        case .choice(let index): .choice(index: index)
        case .fraction(let n, let d): .fraction(numerator: n, denominator: d)
        case .quotientRemainder(let q, let r): .quotientRemainder(quotient: q, remainder: r)
        case .mixedFraction(let w, let n, let d): .mixedFraction(whole: w, numerator: n, denominator: d)
        }
    }
}
