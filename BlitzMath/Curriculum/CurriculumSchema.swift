//
//  CurriculumSchema.swift
//  BlitzMath
//
//  Decoded representation of the bundled curriculum payload.
//  Schema v1.1. Every field introduced after v1.0 is optional with a
//  documented default, so a v1.0 payload decodes unchanged (SRS 4.1).
//

import Foundation

// MARK: - Root

struct CurriculumPayload: Codable, Sendable, Equatable {
    let appName: String
    let version: String
    let schemaVersion: String?
    let curriculum: [CurriculumLevel]

    var resolvedSchemaVersion: String { schemaVersion ?? "1.0" }

    /// Levels in authoritative play order.
    var orderedLevels: [CurriculumLevel] {
        curriculum.sorted { $0.resolvedOrder < $1.resolvedOrder }
    }

    enum CodingKeys: String, CodingKey {
        case appName = "app_name"
        case version
        case schemaVersion = "schema_version"
        case curriculum
    }
}

// MARK: - Level

struct CurriculumLevel: Codable, Sendable, Equatable, Identifiable {
    let levelID: String
    let levelName: String
    let levelOrder: Int?
    let unlockRequirement: UnlockRequirement?
    let modules: [CurriculumModule]

    var id: String { levelID }

    /// Falls back to alphabetical position when `level_order` is absent.
    var resolvedOrder: Int {
        if let levelOrder { return levelOrder }
        guard let scalar = levelID.unicodeScalars.first else { return .max }
        return Int(scalar.value) - Int(UnicodeScalar("A").value) + 1
    }

    enum CodingKeys: String, CodingKey {
        case levelID = "level_id"
        case levelName = "level_name"
        case levelOrder = "level_order"
        case unlockRequirement = "unlock_requirement"
        case modules
    }
}

// MARK: - Unlock requirement

struct UnlockRequirement: Codable, Sendable, Equatable {
    let sourceLevelID: String
    let requiredMedalCount: Int
    let requiredGoldCount: Int?

    var resolvedGoldCount: Int { requiredGoldCount ?? 0 }

    enum CodingKeys: String, CodingKey {
        case sourceLevelID = "source_level_id"
        case requiredMedalCount = "required_medal_count"
        case requiredGoldCount = "required_gold_count"
    }
}

// MARK: - Module

struct CurriculumModule: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let targetSCTSeconds: Int
    let questionCount: Int?
    let generator: GeneratorSpec?

    /// Default drill length when the payload omits `question_count`.
    static let defaultQuestionCount = 20

    var resolvedQuestionCount: Int { questionCount ?? Self.defaultQuestionCount }

    /// `A_02` yields `A`.
    var levelID: String { String(id.prefix(while: { $0 != "_" })) }

    var targetSCT: TimeInterval { TimeInterval(targetSCTSeconds) }

    /// Falls back to a generator inferred from the Level prefix (SRS 4.1.4).
    var resolvedGenerator: GeneratorSpec {
        generator ?? GeneratorSpec.inferred(forLevelID: levelID)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case targetSCTSeconds = "target_sct_seconds"
        case questionCount = "question_count"
        case generator
    }
}

// MARK: - Generator

struct GeneratorSpec: Codable, Sendable, Equatable {
    let kind: String
    let params: [String: Int]?

    func param(_ key: String, default fallback: Int) -> Int {
        params?[key] ?? fallback
    }

    static func inferred(forLevelID levelID: String) -> GeneratorSpec {
        switch levelID {
        case "A": GeneratorSpec(kind: "mixed_within_20", params: nil)
        case "B": GeneratorSpec(kind: "vertical_addition", params: nil)
        case "C": GeneratorSpec(kind: "times_tables", params: nil)
        case "D": GeneratorSpec(kind: "division_exact", params: nil)
        case "E": GeneratorSpec(kind: "fraction_add_like", params: nil)
        default:  GeneratorSpec(kind: "order_of_operations", params: nil)
        }
    }
}
