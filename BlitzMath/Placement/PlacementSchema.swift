//
//  PlacementSchema.swift
//  BlitzMath
//
//  Decoded representation of placement.json and its repository
//  (SRS Addendum 01, section A4.1).
//

import Foundation

// MARK: - Payload

struct PlacementPayload: Codable, Sendable, Equatable {
    let placementVersion: String
    let bands: [PlacementBandRule]
    let sections: [PlacementSection]

    /// Bands in curriculum order, which is the order the scorer walks.
    var orderedBands: [PlacementBandRule] {
        bands.sorted { $0.order < $1.order }
    }

    func rule(for band: String) -> PlacementBandRule? {
        bands.first { $0.band == band }
    }

    var totalQuestionCount: Int {
        sections.flatMap(\.items).reduce(0) { $0 + $1.count }
    }

    enum CodingKeys: String, CodingKey {
        case placementVersion = "placement_version"
        case bands
        case sections
    }
}

// MARK: - Band rule

struct PlacementBandRule: Codable, Sendable, Equatable, Identifiable {
    let band: String
    let entryLevelID: String
    let paceSecondsPerQuestion: Double
    let masteryAccuracy: Double?
    let developingAccuracy: Double?
    let minimumQuestions: Int?

    var id: String { band }

    var resolvedMasteryAccuracy: Double { masteryAccuracy ?? 0.80 }
    var resolvedDevelopingAccuracy: Double { developingAccuracy ?? 0.60 }
    var resolvedMinimumQuestions: Int { minimumQuestions ?? 4 }

    /// A is 1, F is 6.
    var order: Int {
        guard let scalar = band.unicodeScalars.first else { return .max }
        return Int(scalar.value) - Int(UnicodeScalar("A").value) + 1
    }

    enum CodingKeys: String, CodingKey {
        case band
        case entryLevelID = "entry_level_id"
        case paceSecondsPerQuestion = "pace_seconds_per_question"
        case masteryAccuracy = "mastery_accuracy"
        case developingAccuracy = "developing_accuracy"
        case minimumQuestions = "minimum_questions"
    }
}

// MARK: - Section

struct PlacementSection: Codable, Sendable, Equatable, Identifiable {
    let sectionID: String
    let title: String
    let blurb: String?
    let items: [PlacementItem]

    var id: String { sectionID }
    var questionCount: Int { items.reduce(0) { $0 + $1.count } }

    enum CodingKeys: String, CodingKey {
        case sectionID = "section_id"
        case title
        case blurb
        case items
    }
}

struct PlacementItem: Codable, Sendable, Equatable {
    let band: String
    let count: Int
    let generator: GeneratorSpec
}

// MARK: - Banded question

/// A question paired with the band it scores against.
struct PlacementQuestion: Sendable, Equatable, Identifiable {
    let question: Question
    let band: String
    let sectionID: String

    var id: String { "\(sectionID)-\(band)-\(question.id)" }
}

// MARK: - Repository

protocol PlacementProviding: Sendable {
    var payload: PlacementPayload { get }
    var diagnostics: [CurriculumDiagnostic] { get }
    func questions(forSection sectionID: String, seed: UInt64) -> [PlacementQuestion]
}

enum PlacementLoadError: Error, LocalizedError {
    case fileMissing(String)
    case undecodable(underlying: Error)
    case invalid([CurriculumDiagnostic])

    var errorDescription: String? {
        switch self {
        case .fileMissing(let name): "The placement file \(name) is not in the app bundle."
        case .undecodable: "The placement file is not valid JSON for this version."
        case .invalid: "The placement file did not pass validation."
        }
    }
}

final class PlacementRepository: PlacementProviding, @unchecked Sendable {

    let payload: PlacementPayload
    let diagnostics: [CurriculumDiagnostic]

    init(payload: PlacementPayload) throws {
        let found = PlacementValidator.validate(payload)
        guard !found.contains(where: { $0.severity == .error }) else {
            throw PlacementLoadError.invalid(found)
        }
        self.payload = payload
        self.diagnostics = found
    }

    convenience init(bundle: Bundle = .main, resource: String = "placement") throws {
        guard let url = bundle.url(forResource: resource, withExtension: "json") else {
            throw PlacementLoadError.fileMissing("\(resource).json")
        }
        let decoded: PlacementPayload
        do {
            decoded = try JSONDecoder().decode(PlacementPayload.self, from: Data(contentsOf: url))
        } catch {
            throw PlacementLoadError.undecodable(underlying: error)
        }
        try self.init(payload: decoded)
    }

    /// Builds one section's questions, tagged with their band.
    /// Question ids are unique within the section so the view can key on them.
    func questions(forSection sectionID: String, seed: UInt64) -> [PlacementQuestion] {
        guard let section = payload.sections.first(where: { $0.sectionID == sectionID }) else { return [] }

        var built: [PlacementQuestion] = []
        for (itemIndex, item) in section.items.enumerated() {
            // A synthetic module lets the existing factory generate for us.
            let carrier = CurriculumModule(
                id: "\(item.band)_00",
                name: sectionID,
                targetSCTSeconds: 60,
                questionCount: item.count,
                generator: item.generator
            )
            let itemSeed = seed &+ UInt64(itemIndex &* 7919)
            let questions = QuestionFactory.build(module: carrier, seed: itemSeed)

            for (offset, question) in questions.enumerated() {
                let identified = Question(
                    id: built.count + offset,
                    prompt: question.prompt,
                    presentation: question.presentation,
                    answer: question.answer,
                    choices: question.choices,
                    hint: nil                        // no hints in placement (FR-PLC-011)
                )
                built.append(PlacementQuestion(question: identified,
                                               band: item.band,
                                               sectionID: sectionID))
            }
        }
        return built
    }
}

// MARK: - Validator

enum PlacementValidator {

    private static let sectionPattern = /^S[0-9]$/

    static func validate(_ payload: PlacementPayload) -> [CurriculumDiagnostic] {
        var diagnostics: [CurriculumDiagnostic] = []
        var seenBands: Set<String> = []

        for (index, rule) in payload.bands.enumerated() {
            let path = "bands[\(index)]"
            if !(rule.band.count == 1 && ("A"..."F").contains(rule.band)) {
                diagnostics.append(.init(severity: .error, ruleID: "PV-01", path: "\(path).band",
                                         message: "Band \(rule.band) is outside A to F."))
            }
            if !seenBands.insert(rule.band).inserted {
                diagnostics.append(.init(severity: .error, ruleID: "PV-01", path: "\(path).band",
                                         message: "Duplicate band \(rule.band)."))
            }
            if !(3.0...90.0).contains(rule.paceSecondsPerQuestion) {
                diagnostics.append(.init(severity: .error, ruleID: "PV-02", path: "\(path).pace_seconds_per_question",
                                         message: "Pace \(rule.paceSecondsPerQuestion) is outside 3 to 90."))
            }
            if rule.resolvedDevelopingAccuracy > rule.resolvedMasteryAccuracy {
                diagnostics.append(.init(severity: .error, ruleID: "PV-02", path: "\(path).developing_accuracy",
                                         message: "Developing accuracy exceeds mastery accuracy."))
            }
        }

        var seenSections: Set<String> = []
        var bandCounts: [String: Int] = [:]

        for (index, section) in payload.sections.enumerated() {
            let path = "sections[\(index)]"
            if section.sectionID.wholeMatch(of: sectionPattern) == nil {
                diagnostics.append(.init(severity: .error, ruleID: "PV-03", path: "\(path).section_id",
                                         message: "Section id \(section.sectionID) does not match S<n>."))
            }
            if !seenSections.insert(section.sectionID).inserted {
                diagnostics.append(.init(severity: .error, ruleID: "PV-03", path: "\(path).section_id",
                                         message: "Duplicate section id \(section.sectionID)."))
            }
            if section.items.isEmpty {
                diagnostics.append(.init(severity: .error, ruleID: "PV-03", path: "\(path).items",
                                         message: "Section \(section.sectionID) has no items."))
            }
            for (itemIndex, item) in section.items.enumerated() {
                let itemPath = "\(path).items[\(itemIndex)]"
                if !seenBands.contains(item.band) {
                    diagnostics.append(.init(severity: .error, ruleID: "PV-04", path: "\(itemPath).band",
                                             message: "Band \(item.band) has no rule."))
                }
                if !(1...12).contains(item.count) {
                    diagnostics.append(.init(severity: .error, ruleID: "PV-04", path: "\(itemPath).count",
                                             message: "Count \(item.count) is outside 1 to 12."))
                }
                if !QuestionFactory.supportedKinds.contains(item.generator.kind) {
                    diagnostics.append(.init(severity: .error, ruleID: "PV-05", path: "\(itemPath).generator.kind",
                                             message: "Unknown generator kind \(item.generator.kind)."))
                }
                bandCounts[item.band, default: 0] += item.count
            }
        }

        // A band sampled below its own minimum can never be judged mastered.
        // Legal, and sometimes intended, so this is a warning (Addendum A6.2).
        for rule in payload.bands {
            let sampled = bandCounts[rule.band] ?? 0
            if sampled < rule.resolvedMinimumQuestions {
                diagnostics.append(.init(severity: .warning, ruleID: "PV-06", path: "bands[\(rule.band)]",
                                         message: "Band \(rule.band) is sampled \(sampled) times but needs \(rule.resolvedMinimumQuestions) to be judged mastered."))
            }
        }

        return diagnostics
    }
}
