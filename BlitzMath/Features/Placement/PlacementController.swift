//
//  PlacementController.swift
//  BlitzMath
//
//  Control layer for the first-run placement test (SRS Addendum 01, FR-PLC).
//  Unlike a drill session, a wrong answer advances. The test measures, it does
//  not teach, and nothing here writes a medal.
//

import Foundation
import Observation

@MainActor
@Observable
final class PlacementController {

    enum Phase: Equatable {
        case intro                  // section blurb, before its clock starts
        case running
        case paused
        case sectionComplete
        case results
        case leftEarly
        case failed(String)
    }

    // MARK: Observable state

    private(set) var phase: Phase = .intro
    private(set) var sectionIndex: Int = 0
    private(set) var questionIndex: Int = 0
    private(set) var questions: [PlacementQuestion] = []
    private(set) var result: PlacementResult?
    private(set) var placedOutLevelIDs: [String] = []
    private(set) var saveFailed = false

    let clock: BlitzClock

    // MARK: Accumulators

    private var log: [PlacementAnswerLog] = []
    private var sectionSummaries: [PlacementSectionSummary] = []
    private var sectionCorrect = 0
    private var sectionIncorrect = 0
    private var sectionSkipped = 0
    private var lastQuestionMark: TimeInterval = 0

    // MARK: Dependencies

    private let placement: PlacementProviding
    private let curriculum: CurriculumProviding
    private let store: ProgressPersisting
    private let feedback: SessionFeedbackDelivering
    private let seed: UInt64

    init(placement: PlacementProviding,
         curriculum: CurriculumProviding,
         store: ProgressPersisting,
         clock: BlitzClock = BlitzClock(),
         feedback: SessionFeedbackDelivering = SilentFeedback(),
         seed: UInt64 = UInt64.random(in: 1...UInt64.max)) {
        self.placement = placement
        self.curriculum = curriculum
        self.store = store
        self.clock = clock
        self.feedback = feedback
        self.seed = seed
    }

    // MARK: Derived values

    var sections: [PlacementSection] { placement.payload.sections }
    var currentSection: PlacementSection? {
        sections.indices.contains(sectionIndex) ? sections[sectionIndex] : nil
    }
    var currentQuestion: Question? {
        questions.indices.contains(questionIndex) ? questions[questionIndex].question : nil
    }
    var sectionPositionText: String {
        "Section \(min(sectionIndex + 1, sections.count)) of \(sections.count)"
    }
    var questionPositionText: String {
        "\(min(questionIndex + 1, questions.count)) of \(questions.count)"
    }
    var isLastSection: Bool { sectionIndex >= sections.count - 1 }

    // MARK: - Section lifecycle

    /// Builds every section's questions up front (FR-PLC-001).
    func beginTest() {
        guard !sections.isEmpty else {
            phase = .failed("The placement test is not available in this version.")
            return
        }
        sectionIndex = 0
        log = []
        sectionSummaries = []
        phase = .intro
        loadCurrentSection()
    }

    private func loadCurrentSection() {
        guard let section = currentSection else { return }
        questions = placement.questions(forSection: section.sectionID,
                                        seed: seed &+ UInt64(sectionIndex &* 104_729))
        questionIndex = 0
        sectionCorrect = 0
        sectionIncorrect = 0
        sectionSkipped = 0
    }

    /// Each section is timed independently (FR-PLC-002).
    func startSection() {
        guard phase == .intro, !questions.isEmpty else { return }
        clock.reset()
        clock.start()
        lastQuestionMark = 0
        phase = .running
    }

    // MARK: - Answering

    /// A wrong answer advances. Nothing is held (FR-PLC-004).
    func submit(_ input: AnswerInput) {
        guard phase == .running, let banded = current else { return }

        let correct = banded.question.isCorrect(input)
        correct ? feedback.correctAnswer() : feedback.incorrectAnswer()
        correct ? (sectionCorrect += 1) : (sectionIncorrect += 1)

        record(banded: banded, correct: correct, skipped: false)
        advance()
    }

    /// "I have not learned this yet." Scored as incorrect for the band (FR-PLC-005).
    func skipQuestion() {
        guard phase == .running, let banded = current else { return }
        sectionSkipped += 1
        record(banded: banded, correct: false, skipped: true)
        advance()
    }

    /// Marks every remaining question in this section as skipped (FR-PLC-006).
    func skipSection() {
        guard phase == .running || phase == .paused else { return }
        if phase == .paused { clock.resume() }

        while questionIndex < questions.count {
            let banded = questions[questionIndex]
            sectionSkipped += 1
            record(banded: banded, correct: false, skipped: true)
            questionIndex += 1
        }
        closeSection()
    }

    private var current: PlacementQuestion? {
        questions.indices.contains(questionIndex) ? questions[questionIndex] : nil
    }

    /// Per-question seconds come from the difference between clock marks (FR-PLC-003).
    private func record(banded: PlacementQuestion, correct: Bool, skipped: Bool) {
        let mark = clock.elapsed
        let seconds = max(0, mark - lastQuestionMark)
        lastQuestionMark = mark

        log.append(PlacementAnswerLog(band: banded.band,
                                      sectionID: banded.sectionID,
                                      wasCorrect: correct,
                                      wasSkipped: skipped,
                                      seconds: seconds))
    }

    private func advance() {
        let next = questionIndex + 1
        if next >= questions.count {
            questionIndex = questions.count
            closeSection()
        } else {
            questionIndex = next
        }
    }

    private func closeSection() {
        guard let section = currentSection else { return }
        let elapsed = clock.stop()

        sectionSummaries.append(PlacementSectionSummary(
            sectionID: section.sectionID,
            title: section.title,
            elapsedSeconds: elapsed,
            askedCount: questions.count,
            correctCount: sectionCorrect,
            incorrectCount: sectionIncorrect,
            skippedCount: sectionSkipped
        ))

        phase = .sectionComplete
    }

    func continueToNextSection() {
        guard phase == .sectionComplete else { return }
        if isLastSection {
            finish(completed: true)
        } else {
            sectionIndex += 1
            loadCurrentSection()
            phase = .intro
        }
    }

    // MARK: - Pause and leave

    func pause() {
        guard phase == .running else { return }
        clock.pause()
        phase = .paused
    }

    func handleBackgrounding() { pause() }

    func resume() {
        guard phase == .paused else { return }
        clock.resume()
        phase = .running
    }

    /// FR-PLC-009. Writes an incomplete record and places nobody.
    func leaveTest() {
        guard phase != .results else { return }
        if clock.state == .running { clock.stop() }
        finish(completed: false)
        phase = .leftEarly
    }

    // MARK: - Scoring

    private func finish(completed: Bool) {
        let scored = PlacementScorer.score(log: log,
                                           sections: sectionSummaries,
                                           rules: placement.payload.bands,
                                           wasCompleted: completed)
        result = scored

        if completed {
            phase = .results
        }

        // An incomplete test is recorded for history but never applied.
        if !completed {
            do {
                _ = try store.applyPlacement(scored,
                                             acceptedLevelID: "A",
                                             levels: curriculum.payload.orderedLevels)
            } catch {
                saveFailed = true
            }
        }
    }

    // MARK: - Accepting the result

    /// Accepts the scorer's placement.
    func acceptPlacement() {
        guard let result else { return }
        apply(result: result, acceptedLevelID: result.entryLevelID)
    }

    /// FR-PLA-013. Starting lower by choice. Placed-out levels stay open.
    func startFromLevelAInstead() {
        guard let result else { return }
        apply(result: result, acceptedLevelID: "A")
    }

    private func apply(result: PlacementResult, acceptedLevelID: String) {
        do {
            placedOutLevelIDs = try store.applyPlacement(result,
                                                         acceptedLevelID: acceptedLevelID,
                                                         levels: curriculum.payload.orderedLevels)
            saveFailed = false
        } catch {
            saveFailed = true
        }
    }

    // MARK: - Presentation helpers

    var entryLevelName: String {
        guard let result, let level = curriculum.level(id: result.entryLevelID) else { return "" }
        return level.levelName
    }

    var explanation: String {
        guard let result else { return "" }
        return PlacementScorer.explanation(for: result, levelName: entryLevelName)
    }
}
