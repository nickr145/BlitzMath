//
//  LevelSessionController.swift
//  BlitzMath
//
//  Control layer for one drill session. Resolves a module from the bundled
//  curriculum, sequences questions, runs the Blitz clock, awards a medal, and
//  hands the result to persistence (SRS FR-SES, state machine 10.1).
//
//  Dependencies are injected as protocols so the controller runs in previews
//  and tests against doubles with no bundle and no store.
//

import Foundation
import Observation

// MARK: - Feedback port

/// Haptics are supplementary and never the only signal (SRS FR-FBK-002, AS-04).
protocol SessionFeedbackDelivering: Sendable {
    func correctAnswer()
    func incorrectAnswer()
    func medalAwarded(_ medal: MedalTier)
}

struct SilentFeedback: SessionFeedbackDelivering {
    func correctAnswer() {}
    func incorrectAnswer() {}
    func medalAwarded(_ medal: MedalTier) {}
}

// MARK: - Controller

@MainActor
@Observable
final class LevelSessionController {

    // MARK: State machine

    enum Phase: Equatable {
        case idle
        case running
        case paused
        case grading
        case summary
        case abandoned
        case failed(String)
    }

    struct Summary: Equatable {
        let module: CurriculumModule
        let outcome: SessionOutcome
        let medal: MedalTier
        let previousBest: MedalTier
        let rationale: String
        let newlyUnlockedLevelIDs: [String]
        let saveFailed: Bool

        var isNewBest: Bool { medal.rank > previousBest.rank }
    }

    // MARK: Observable state

    private(set) var phase: Phase = .idle
    private(set) var module: CurriculumModule?
    private(set) var questions: [Question] = []
    private(set) var currentIndex: Int = 0
    private(set) var lastAnswerWasIncorrect = false
    private(set) var revealedHint: String?
    private(set) var summary: Summary?
    private(set) var saveNotice: String?

    let clock: BlitzClock

    // MARK: Counters

    private var correctFirstTryCount = 0
    private var incorrectAttemptCount = 0
    private var hintsUsed = 0
    private var currentQuestionHadMistake = false
    private var startedAt: Date?

    // MARK: Dependencies

    private let curriculum: CurriculumProviding
    private let store: ProgressPersisting
    private let feedback: SessionFeedbackDelivering
    private let seedProvider: () -> UInt64

    init(curriculum: CurriculumProviding,
         store: ProgressPersisting,
         clock: BlitzClock = BlitzClock(),
         feedback: SessionFeedbackDelivering = SilentFeedback(),
         seedProvider: @escaping () -> UInt64 = { UInt64.random(in: 1...UInt64.max) }) {
        self.curriculum = curriculum
        self.store = store
        self.clock = clock
        self.feedback = feedback
        self.seedProvider = seedProvider
    }

    // MARK: Derived values for the view

    var currentQuestion: Question? {
        questions.indices.contains(currentIndex) ? questions[currentIndex] : nil
    }

    var answeredCount: Int { currentIndex }
    var totalCount: Int { questions.count }

    var progressFraction: Double {
        totalCount > 0 ? Double(answeredCount) / Double(totalCount) : 0
    }

    var sctFraction: Double {
        clock.sctFraction(target: module?.targetSCT ?? 0)
    }

    var pace: BlitzClock.Pace {
        clock.pace(target: module?.targetSCT ?? 0)
    }

    var elapsedText: String {
        let value = clock.elapsed
        return String(format: "%d:%04.1f", Int(value) / 60, value.truncatingRemainder(dividingBy: 60))
    }

    var targetText: String {
        guard let module else { return "" }
        return String(format: "%d:%02d", module.targetSCTSeconds / 60, module.targetSCTSeconds % 60)
    }

    var isRunning: Bool { phase == .running }

    // MARK: - Start

    /// Resolves the module, builds the question set, then starts the clock.
    /// Generation cost is never charged to the player (SRS FR-SES-002).
    func start(moduleID: String) {
        guard phase == .idle || phase == .summary || phase == .abandoned else { return }

        guard let resolved = curriculum.module(id: moduleID) else {
            phase = .failed("That module is not in this version of the app.")
            return
        }

        module = resolved
        questions = QuestionFactory.build(module: resolved, seed: seedProvider())

        guard !questions.isEmpty else {
            phase = .failed("That module has no questions to play.")
            return
        }

        currentIndex = 0
        correctFirstTryCount = 0
        incorrectAttemptCount = 0
        hintsUsed = 0
        currentQuestionHadMistake = false
        lastAnswerWasIncorrect = false
        revealedHint = nil
        summary = nil
        saveNotice = nil

        startedAt = Date()
        clock.reset()
        clock.start()
        phase = .running
    }

    // MARK: - Answering

    /// Validates one submission. A wrong answer keeps the question active
    /// (SRS FR-SES-005, FR-SES-006).
    func submit(_ input: AnswerInput) {
        guard phase == .running, let question = currentQuestion else { return }

        if question.isCorrect(input) {
            if !currentQuestionHadMistake { correctFirstTryCount += 1 }
            lastAnswerWasIncorrect = false
            revealedHint = nil
            feedback.correctAnswer()
            advance()
        } else {
            incorrectAttemptCount += 1
            currentQuestionHadMistake = true
            lastAnswerWasIncorrect = true
            feedback.incorrectAnswer()
        }
    }

    func revealHint() {
        guard phase == .running, let hint = currentQuestion?.hint, revealedHint == nil else { return }
        hintsUsed += 1
        revealedHint = hint
    }

    private func advance() {
        currentQuestionHadMistake = false
        let next = currentIndex + 1

        if next >= questions.count {
            currentIndex = questions.count
            finish(abandoned: false)
        } else {
            currentIndex = next
        }
    }

    // MARK: - Pause and resume

    func pause() {
        guard phase == .running else { return }
        clock.pause()
        phase = .paused
    }

    /// Called from scene phase changes. The clock never resumes on its own
    /// (SRS FR-SES-008, FR-SES-009).
    func handleBackgrounding() {
        pause()
    }

    func resume() {
        guard phase == .paused else { return }
        clock.resume()
        phase = .running
    }

    func abandon() {
        guard phase == .running || phase == .paused else { return }
        finish(abandoned: true)
    }

    func dismissSummary() {
        summary = nil
        saveNotice = nil
        module = nil
        questions = []
        currentIndex = 0
        clock.reset()
        phase = .idle
    }

    // MARK: - Completion

    private func finish(abandoned: Bool) {
        guard let module, let startedAt else { return }

        // Clock stops before grading, so validation latency is not charged (FR-BLZ-008).
        let elapsed = clock.stop()
        phase = .grading

        let outcome = SessionOutcome(
            elapsedSeconds: elapsed,
            sctSeconds: module.targetSCTSeconds,
            questionCount: questions.count,
            correctFirstTryCount: correctFirstTryCount,
            incorrectAttemptCount: incorrectAttemptCount,
            hintsUsed: hintsUsed,
            wasAbandoned: abandoned
        )

        let medal = MedalEvaluator.award(for: outcome)
        let endedAt = Date()

        var previousBest = MedalTier.none
        var unlocked: [String] = []
        var saveFailed = false

        do {
            previousBest = try store.bestMedal(forModule: module.id)
            try store.record(outcome: outcome,
                             module: module,
                             startedAt: startedAt,
                             endedAt: endedAt,
                             medal: medal)
            unlocked = try store.synchroniseLockStates(with: curriculum.payload.orderedLevels)
        } catch {
            // Non-blocking notice, result stays in memory for a retry (FR-PER-003).
            saveFailed = true
            saveNotice = "This run could not be saved. Your medal is shown here, and the app will try again."
        }

        if medal != .none { feedback.medalAwarded(medal) }

        summary = Summary(module: module,
                          outcome: outcome,
                          medal: medal,
                          previousBest: previousBest,
                          rationale: MedalEvaluator.rationale(for: outcome, medal: medal),
                          newlyUnlockedLevelIDs: unlocked,
                          saveFailed: saveFailed)

        phase = abandoned ? .abandoned : .summary
    }

    /// One retry for a failed save, triggered from the summary sheet.
    func retrySave() {
        guard let summary, summary.saveFailed, let module, let startedAt else { return }
        do {
            try store.record(outcome: summary.outcome,
                             module: module,
                             startedAt: startedAt,
                             endedAt: Date(),
                             medal: summary.medal)
            let unlocked = try store.synchroniseLockStates(with: curriculum.payload.orderedLevels)
            self.summary = Summary(module: module,
                                   outcome: summary.outcome,
                                   medal: summary.medal,
                                   previousBest: summary.previousBest,
                                   rationale: summary.rationale,
                                   newlyUnlockedLevelIDs: unlocked,
                                   saveFailed: false)
            saveNotice = nil
        } catch {
            saveNotice = "Saving failed again. Your progress for this run is not stored."
        }
    }
}

// MARK: - Preview doubles

/// In-memory curriculum for previews, seeded from the same schema as the bundle.
struct MockCurriculumProvider: CurriculumProviding {
    let payload: CurriculumPayload
    let diagnostics: [CurriculumDiagnostic] = []

    init(payload: CurriculumPayload = .sample) { self.payload = payload }

    func level(id: String) -> CurriculumLevel? { payload.curriculum.first { $0.levelID == id } }
    func module(id: String) -> CurriculumModule? { payload.curriculum.flatMap(\.modules).first { $0.id == id } }
    func modules(inLevel levelID: String) -> [CurriculumModule] { level(id: levelID)?.modules ?? [] }
}

extension CurriculumPayload {
    static let sample = CurriculumPayload(
        appName: "BlitzMath",
        version: "1.0.0",
        schemaVersion: "1.1",
        curriculum: [
            CurriculumLevel(
                levelID: "A", levelName: "Basic Arithmetic Foundations", levelOrder: 1,
                unlockRequirement: nil,
                modules: [
                    CurriculumModule(id: "A_01", name: "Review of 2A Operations", targetSCTSeconds: 120,
                                     questionCount: 20,
                                     generator: GeneratorSpec(kind: "addition_within_10", params: ["max": 10]))
                ]
            ),
            CurriculumLevel(
                levelID: "E", levelName: "Fraction Operations", levelOrder: 5,
                unlockRequirement: UnlockRequirement(sourceLevelID: "D", requiredMedalCount: 4, requiredGoldCount: 1),
                modules: [
                    CurriculumModule(id: "E_02", name: "Addition of Fractions (Like Denominators)",
                                     targetSCTSeconds: 240, questionCount: 20,
                                     generator: GeneratorSpec(kind: "fraction_add_like", params: ["max_denominator": 12]))
                ]
            )
        ]
    )
}

/// Records writes without SwiftData, for previews and controller tests.
@MainActor
final class MockProgressStore: ProgressPersisting {
    var snapshot = MedalSnapshot()
    var medals: [String: MedalTier] = [:]
    var recordedOutcomes: [(module: String, medal: MedalTier)] = []
    var shouldFailSaves = false

    private let backingProfile = PlayerProfile()

    func profile() throws -> PlayerProfile { backingProfile }
    func medalSnapshot() throws -> MedalSnapshot { snapshot }
    func bestMedal(forModule moduleID: String) throws -> MedalTier { medals[moduleID] ?? .none }
    func moduleSummaries(levelID: String) throws -> [ModuleSummary] { [] }
    func unlockedLevelIDs() throws -> Set<String> { ["A"] }

    @discardableResult
    func record(outcome: SessionOutcome, module: CurriculumModule, startedAt: Date,
                endedAt: Date, medal: MedalTier) throws -> SessionRecord {
        if shouldFailSaves { throw CocoaError(.fileWriteUnknown) }
        recordedOutcomes.append((module: module.id, medal: medal))
        if medal.rank > (medals[module.id]?.rank ?? 0) { medals[module.id] = medal }
        return SessionRecord(moduleID: module.id, levelID: module.levelID, startedAt: startedAt,
                             endedAt: endedAt, outcome: outcome, medal: medal)
    }

    func synchroniseLockStates(with levels: [CurriculumLevel]) throws -> [String] { [] }
    func resetAllProgress() throws { medals.removeAll(); recordedOutcomes.removeAll() }

    // Onboarding and placement

    var pretendHasProgress = false
    var onboardingComplete = false
    var appliedPlacements: [(entry: String, accepted: String)] = []
    var placementUnlocks: [String] = []

    func hasAnyProgress() throws -> Bool { pretendHasProgress || onboardingComplete }

    func markOnboardingComplete(entryLevelID: String?) throws {
        onboardingComplete = true
    }

    func openLevelA(in levels: [CurriculumLevel]) throws {
        onboardingComplete = true
        placementUnlocks = ["A"]
    }

    @discardableResult
    func applyPlacement(_ result: PlacementResult,
                        acceptedLevelID: String,
                        levels: [CurriculumLevel]) throws -> [String] {
        if shouldFailSaves { throw CocoaError(.fileWriteUnknown) }
        appliedPlacements.append((entry: result.entryLevelID, accepted: acceptedLevelID))
        guard result.wasCompleted else { return [] }
        onboardingComplete = true
        placementUnlocks = result.placedOutLevelIDs(levels: levels)
        return placementUnlocks
    }

    func latestPlacementResult() throws -> PlacementResultRecord? { nil }
}

/// In-memory placement payload for previews and controller tests.
struct MockPlacementProvider: PlacementProviding {
    let payload: PlacementPayload
    let diagnostics: [CurriculumDiagnostic] = []

    init(payload: PlacementPayload = .sample) { self.payload = payload }

    func questions(forSection sectionID: String, seed: UInt64) -> [PlacementQuestion] {
        guard let section = payload.sections.first(where: { $0.sectionID == sectionID }) else { return [] }
        var built: [PlacementQuestion] = []
        for (index, item) in section.items.enumerated() {
            let carrier = CurriculumModule(id: "\(item.band)_00", name: sectionID,
                                           targetSCTSeconds: 60, questionCount: item.count,
                                           generator: item.generator)
            for question in QuestionFactory.build(module: carrier, seed: seed &+ UInt64(index &* 7919)) {
                let identified = Question(id: built.count, prompt: question.prompt,
                                          presentation: question.presentation, answer: question.answer,
                                          choices: question.choices, hint: nil)
                built.append(PlacementQuestion(question: identified, band: item.band, sectionID: sectionID))
            }
        }
        return built
    }
}

extension PlacementPayload {
    static let sample = PlacementPayload(
        placementVersion: "1.0.0",
        bands: [
            PlacementBandRule(band: "A", entryLevelID: "A", paceSecondsPerQuestion: 7,
                              masteryAccuracy: 0.8, developingAccuracy: 0.6, minimumQuestions: 2),
            PlacementBandRule(band: "E", entryLevelID: "E", paceSecondsPerQuestion: 26,
                              masteryAccuracy: 0.75, developingAccuracy: 0.55, minimumQuestions: 2)
        ],
        sections: [
            PlacementSection(sectionID: "S1", title: "Adding and taking away",
                             blurb: "A few quick ones.",
                             items: [PlacementItem(band: "A", count: 2,
                                                   generator: GeneratorSpec(kind: "addition_within_24",
                                                                            params: ["max": 24]))]),
            PlacementSection(sectionID: "S2", title: "Fractions", blurb: nil,
                             items: [PlacementItem(band: "E", count: 2,
                                                   generator: GeneratorSpec(kind: "fraction_add_like",
                                                                            params: ["max_denominator": 12]))])
        ]
    )
}
