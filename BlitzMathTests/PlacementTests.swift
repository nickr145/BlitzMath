//
//  PlacementTests.swift
//  BlitzMathTests
//
//  Traced to the acceptance criteria in SRS Addendum 01, section A8.
//

import Testing
import Foundation
@testable import BlitzMath

// MARK: - Scoring (AC-A04 to AC-A07)

@Suite("Placement scoring")
struct PlacementScorerTests {

    private let rules: [PlacementBandRule] = [
        .init(band: "A", entryLevelID: "A", paceSecondsPerQuestion: 7,
              masteryAccuracy: 0.8, developingAccuracy: 0.6, minimumQuestions: 4),
        .init(band: "B", entryLevelID: "B", paceSecondsPerQuestion: 14,
              masteryAccuracy: 0.8, developingAccuracy: 0.6, minimumQuestions: 4),
        .init(band: "C", entryLevelID: "C", paceSecondsPerQuestion: 10,
              masteryAccuracy: 0.8, developingAccuracy: 0.6, minimumQuestions: 4)
    ]

    private func log(band: String, count: Int, correct: Int, seconds: Double,
                     skipped: Int = 0) -> [PlacementAnswerLog] {
        (0..<count).map { index in
            PlacementAnswerLog(band: band, sectionID: "S1",
                               wasCorrect: index < correct,
                               wasSkipped: index >= count - skipped,
                               seconds: seconds)
        }
    }

    private func score(_ entries: [PlacementAnswerLog]) -> PlacementResult {
        PlacementScorer.score(log: entries, sections: [], rules: rules)
    }

    @Test("Mastering A and B with nothing on C places at C")
    func placesAtFirstUnmasteredBand() {
        let entries = log(band: "A", count: 4, correct: 4, seconds: 4)
                    + log(band: "B", count: 4, correct: 4, seconds: 9)
        #expect(score(entries).entryLevelID == "C")
    }

    @Test("Full accuracy but slow on A still places at A")
    func paceGatesPlacement() {
        let entries = log(band: "A", count: 4, correct: 4, seconds: 30)
                    + log(band: "B", count: 4, correct: 4, seconds: 9)
        let result = score(entries)
        #expect(result.entryLevelID == "A")
        #expect(result.bandSummaries.first { $0.band == "A" }?.verdict == .developing)
    }

    @Test("Skipping everything places at A with no band mastered")
    func allSkippedPlacesAtA() {
        let entries = log(band: "A", count: 4, correct: 0, seconds: 1, skipped: 4)
        let result = score(entries)
        #expect(result.entryLevelID == "A")
        #expect(result.masteredBands.isEmpty)
    }

    @Test("Mastering every band places at the last band and no further")
    func neverPlacesPastTheLastLevel() {
        let entries = log(band: "A", count: 4, correct: 4, seconds: 3)
                    + log(band: "B", count: 4, correct: 4, seconds: 8)
                    + log(band: "C", count: 4, correct: 4, seconds: 6)
        #expect(score(entries).entryLevelID == "C")
    }

    @Test("A band sampled below its minimum is never mastered")
    func minimumSampleIsEnforced() {
        let entries = log(band: "A", count: 3, correct: 3, seconds: 2)
        let summary = score(entries).bandSummaries.first { $0.band == "A" }
        #expect(summary?.verdict != .mastered)
        #expect(score(entries).entryLevelID == "A")
    }

    @Test("Placed-out levels include every level up to the entry level")
    func placedOutLevelsAreCumulative() {
        let levels = CurriculumPayload.sample.orderedLevels   // A order 1, E order 5
        let result = PlacementResult(entryLevelID: "E", bandSummaries: [], sectionSummaries: [],
                                     totalSeconds: 0, wasCompleted: true)
        #expect(result.placedOutLevelIDs(levels: levels) == ["A", "E"])
    }
}

// MARK: - Controller (AC-A10, AC-A11)

@Suite("Placement controller")
@MainActor
struct PlacementControllerTests {

    private func makeController() -> (PlacementController, MockProgressStore, ManualTimeSource) {
        let source = ManualTimeSource()
        let store = MockProgressStore()
        let controller = PlacementController(
            placement: MockPlacementProvider(),
            curriculum: MockCurriculumProvider(),
            store: store,
            clock: BlitzClock(source: source, tickInterval: .seconds(60)),
            seed: 99
        )
        return (controller, store, source)
    }

    @Test("A wrong answer advances rather than holding the question")
    func wrongAnswerAdvances() {
        let (controller, _, _) = makeController()
        controller.beginTest()
        controller.startSection()

        let first = controller.currentQuestion
        controller.submit(.integer(-9_999))

        #expect(controller.currentQuestion != first)
    }

    @Test("Leaving partway writes an incomplete result and places nobody")
    func leavingEarlyPlacesNobody() {
        let (controller, store, _) = makeController()
        controller.beginTest()
        controller.startSection()
        controller.leaveTest()

        #expect(controller.phase == .leftEarly)
        #expect(controller.result?.wasCompleted == false)
        #expect(store.placementUnlocks.isEmpty)
        #expect(store.onboardingComplete == false)
    }

    @Test("Paused time is excluded from the section measurement")
    func pauseExcludesSectionTime() {
        let (controller, _, source) = makeController()
        controller.beginTest()
        controller.startSection()

        source.advance(by: 5)
        controller.pause()
        source.advance(by: 300)
        controller.resume()
        source.advance(by: 5)
        controller.skipSection()

        let section = controller.result?.sectionSummaries.first
        #expect(section == nil || abs((section?.elapsedSeconds ?? 0) - 10) < 0.01)
    }

    @Test("Skipping a section marks every remaining question as skipped")
    func sectionSkipMarksEverything() {
        let (controller, _, _) = makeController()
        controller.beginTest()
        controller.startSection()
        controller.skipSection()

        #expect(controller.phase == .sectionComplete)
    }

    @Test("Accepting the placement applies it, overriding starts at A")
    func acceptAndOverride() {
        let (controller, store, source) = makeController()
        controller.beginTest()

        // Walk both sections, answering nothing.
        while controller.phase != .results {
            if controller.phase == .intro { controller.startSection() }
            if controller.phase == .running { source.advance(by: 1); controller.skipSection() }
            if controller.phase == .sectionComplete { controller.continueToNextSection() }
        }

        controller.startFromLevelAInstead()
        #expect(store.appliedPlacements.last?.accepted == "A")
        #expect(store.onboardingComplete)
    }
}

// MARK: - Payload validation

@Suite("Placement payload")
struct PlacementRepositoryTests {

    @Test("A band with no rule is an error")
    func unknownBandIsRejected() {
        let payload = PlacementPayload(
            placementVersion: "1.0.0",
            bands: [.init(band: "A", entryLevelID: "A", paceSecondsPerQuestion: 7,
                          masteryAccuracy: nil, developingAccuracy: nil, minimumQuestions: nil)],
            sections: [PlacementSection(sectionID: "S1", title: "Test", blurb: nil,
                                        items: [PlacementItem(band: "Z", count: 2,
                                                              generator: GeneratorSpec(kind: "times_tables",
                                                                                       params: nil))])]
        )
        #expect(PlacementValidator.validate(payload).contains { $0.ruleID == "PV-04" })
    }

    @Test("A band sampled below its minimum raises a warning, not an error")
    func underSampledBandWarns() {
        let payload = PlacementPayload(
            placementVersion: "1.0.0",
            bands: [.init(band: "A", entryLevelID: "A", paceSecondsPerQuestion: 7,
                          masteryAccuracy: nil, developingAccuracy: nil, minimumQuestions: 6)],
            sections: [PlacementSection(sectionID: "S1", title: "Test", blurb: nil,
                                        items: [PlacementItem(band: "A", count: 2,
                                                              generator: GeneratorSpec(kind: "times_tables",
                                                                                       params: nil))])]
        )
        let diagnostics = PlacementValidator.validate(payload)
        #expect(diagnostics.contains { $0.ruleID == "PV-06" && $0.severity == .warning })
        #expect(!diagnostics.contains { $0.severity == .error })
    }
}
