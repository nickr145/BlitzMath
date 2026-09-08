//
//  CurriculumRepository.swift
//  BlitzMath
//
//  Loads, validates, and caches the bundled curriculum payload.
//  This is the only component permitted to touch the bundle (SRS FR-CUR).
//

import Foundation
import OSLog

// MARK: - Protocol

protocol CurriculumProviding: Sendable {
    var payload: CurriculumPayload { get }
    var diagnostics: [CurriculumDiagnostic] { get }
    func level(id: String) -> CurriculumLevel?
    func module(id: String) -> CurriculumModule?
    func modules(inLevel levelID: String) -> [CurriculumModule]
}

// MARK: - Diagnostics

struct CurriculumDiagnostic: Sendable, Equatable, Identifiable {
    enum Severity: String, Sendable { case warning, error }

    let id = UUID()
    let severity: Severity
    let ruleID: String       // matches the DV-xx rules in the SRS
    let path: String         // "curriculum[2].modules[1].target_sct_seconds"
    let message: String

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.ruleID == rhs.ruleID && lhs.path == rhs.path && lhs.message == rhs.message
    }
}

enum CurriculumLoadError: Error, LocalizedError {
    case fileMissing(String)
    case unreadable(underlying: Error)
    case undecodable(underlying: Error)
    case noPlayableContent

    var errorDescription: String? {
        switch self {
        case .fileMissing(let name):
            "The curriculum file \(name) is not in the app bundle."
        case .unreadable:
            "The curriculum file could not be read."
        case .undecodable:
            "The curriculum file is not valid JSON for this version."
        case .noPlayableContent:
            "The curriculum contains no playable levels."
        }
    }
}

// MARK: - Repository

final class CurriculumRepository: CurriculumProviding, @unchecked Sendable {

    let payload: CurriculumPayload
    let diagnostics: [CurriculumDiagnostic]

    private let levelIndex: [String: CurriculumLevel]
    private let moduleIndex: [String: CurriculumModule]
    private static let logger = Logger(subsystem: "com.blitzmath.app", category: "curriculum")

    // MARK: Construction

    /// Designated initialiser. Validation runs once, at construction.
    init(payload rawPayload: CurriculumPayload) throws {
        let validation = CurriculumValidator.validate(rawPayload)
        guard !validation.levels.isEmpty else { throw CurriculumLoadError.noPlayableContent }

        self.payload = CurriculumPayload(
            appName: rawPayload.appName,
            version: rawPayload.version,
            schemaVersion: rawPayload.schemaVersion,
            curriculum: validation.levels
        )
        self.diagnostics = validation.diagnostics

        self.levelIndex = Dictionary(uniqueKeysWithValues: validation.levels.map { ($0.levelID, $0) })
        self.moduleIndex = Dictionary(
            uniqueKeysWithValues: validation.levels.flatMap(\.modules).map { ($0.id, $0) }
        )

        for diagnostic in diagnostics where diagnostic.severity == .error {
            Self.logger.error("[\(diagnostic.ruleID)] \(diagnostic.path): \(diagnostic.message)")
        }
    }

    /// Loads `curriculum.json` from the given bundle.
    convenience init(bundle: Bundle = .main, resource: String = "curriculum") throws {
        guard let url = bundle.url(forResource: resource, withExtension: "json") else {
            throw CurriculumLoadError.fileMissing("\(resource).json")
        }
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch { throw CurriculumLoadError.unreadable(underlying: error) }

        let decoded: CurriculumPayload
        do { decoded = try JSONDecoder().decode(CurriculumPayload.self, from: data) }
        catch { throw CurriculumLoadError.undecodable(underlying: error) }

        try self.init(payload: decoded)
    }

    // MARK: Lookup, constant time (FR-CUR-005)

    func level(id: String) -> CurriculumLevel? { levelIndex[id] }
    func module(id: String) -> CurriculumModule? { moduleIndex[id] }
    func modules(inLevel levelID: String) -> [CurriculumModule] { levelIndex[levelID]?.modules ?? [] }

    var orderedLevels: [CurriculumLevel] { payload.orderedLevels }
}

// MARK: - Validator

enum CurriculumValidator {

    struct Result {
        let levels: [CurriculumLevel]
        let diagnostics: [CurriculumDiagnostic]
    }

    private static let modulePattern = /^[A-F]_[0-9]{2}$/
    private static let sctRange = 30...900
    private static let questionRange = 5...40

    static func validate(_ payload: CurriculumPayload) -> Result {
        var diagnostics: [CurriculumDiagnostic] = []
        var acceptedLevels: [CurriculumLevel] = []
        var seenLevelIDs: Set<String> = []
        var seenModuleIDs: Set<String> = []

        for (levelIndex, level) in payload.curriculum.enumerated() {
            let levelPath = "curriculum[\(levelIndex)]"

            // DV-02 unique, A to F
            guard level.levelID.count == 1, ("A"..."F").contains(level.levelID) else {
                diagnostics.append(.init(severity: .error, ruleID: "DV-02", path: "\(levelPath).level_id",
                                         message: "Level id \(level.levelID) is outside the range A to F."))
                continue
            }
            guard seenLevelIDs.insert(level.levelID).inserted else {
                diagnostics.append(.init(severity: .error, ruleID: "DV-02", path: "\(levelPath).level_id",
                                         message: "Duplicate level id \(level.levelID)."))
                continue
            }

            // Modules
            var acceptedModules: [CurriculumModule] = []
            for (moduleIndex, module) in level.modules.enumerated() {
                let modulePath = "\(levelPath).modules[\(moduleIndex)]"

                guard module.id.wholeMatch(of: modulePattern) != nil else {
                    diagnostics.append(.init(severity: .error, ruleID: "DV-03", path: "\(modulePath).id",
                                             message: "Module id \(module.id) does not match <LEVEL>_<NN>."))
                    continue
                }
                guard module.levelID == level.levelID else {
                    diagnostics.append(.init(severity: .error, ruleID: "DV-03", path: "\(modulePath).id",
                                             message: "Module \(module.id) is not prefixed with its level \(level.levelID)."))
                    continue
                }
                guard seenModuleIDs.insert(module.id).inserted else {
                    diagnostics.append(.init(severity: .error, ruleID: "DV-03", path: "\(modulePath).id",
                                             message: "Duplicate module id \(module.id)."))
                    continue
                }
                guard sctRange.contains(module.targetSCTSeconds) else {
                    diagnostics.append(.init(severity: .error, ruleID: "DV-04", path: "\(modulePath).target_sct_seconds",
                                             message: "SCT \(module.targetSCTSeconds) is outside 30 to 900."))
                    continue
                }
                guard questionRange.contains(module.resolvedQuestionCount) else {
                    diagnostics.append(.init(severity: .error, ruleID: "DV-04", path: "\(modulePath).question_count",
                                             message: "Question count \(module.resolvedQuestionCount) is outside 5 to 40."))
                    continue
                }
                if QuestionFactory.supportedKinds.contains(module.resolvedGenerator.kind) == false {
                    diagnostics.append(.init(severity: .error, ruleID: "DV-09", path: "\(modulePath).generator.kind",
                                             message: "Unknown generator kind \(module.resolvedGenerator.kind)."))
                    continue
                }
                acceptedModules.append(module)
            }

            guard !acceptedModules.isEmpty else {
                diagnostics.append(.init(severity: .error, ruleID: "DV-03", path: "\(levelPath).modules",
                                         message: "Level \(level.levelID) has no valid modules and was dropped."))
                continue
            }

            acceptedLevels.append(CurriculumLevel(
                levelID: level.levelID,
                levelName: level.levelName,
                levelOrder: level.resolvedOrder,
                unlockRequirement: level.unlockRequirement,
                modules: acceptedModules
            ))
        }

        diagnostics.append(contentsOf: validateGates(across: acceptedLevels))
        return Result(levels: acceptedLevels, diagnostics: diagnostics)
    }

    /// DV-05, DV-06, DV-07
    private static func validateGates(across levels: [CurriculumLevel]) -> [CurriculumDiagnostic] {
        var diagnostics: [CurriculumDiagnostic] = []
        let byID = Dictionary(uniqueKeysWithValues: levels.map { ($0.levelID, $0) })

        let entryPoints = levels.filter { $0.unlockRequirement == nil }
        if entryPoints.isEmpty {
            diagnostics.append(.init(severity: .error, ruleID: "DV-07", path: "curriculum",
                                     message: "No level is unlocked at first launch."))
        } else if entryPoints.count > 1 {
            diagnostics.append(.init(severity: .warning, ruleID: "DV-07", path: "curriculum",
                                     message: "More than one level is unlocked at first launch."))
        }

        for level in levels {
            guard let requirement = level.unlockRequirement else { continue }
            let path = "curriculum[\(level.levelID)].unlock_requirement"

            guard let source = byID[requirement.sourceLevelID] else {
                diagnostics.append(.init(severity: .error, ruleID: "DV-05", path: "\(path).source_level_id",
                                         message: "Source level \(requirement.sourceLevelID) does not exist."))
                continue
            }
            if source.resolvedOrder >= level.resolvedOrder {
                diagnostics.append(.init(severity: .error, ruleID: "DV-05", path: "\(path).source_level_id",
                                         message: "Source level \(source.levelID) does not precede \(level.levelID)."))
            }
            if requirement.requiredMedalCount > source.modules.count {
                diagnostics.append(.init(severity: .error, ruleID: "DV-06", path: "\(path).required_medal_count",
                                         message: "Requires \(requirement.requiredMedalCount) medals but \(source.levelID) has \(source.modules.count) modules."))
            }
            if requirement.resolvedGoldCount > requirement.requiredMedalCount {
                diagnostics.append(.init(severity: .error, ruleID: "DV-06", path: "\(path).required_gold_count",
                                         message: "Gold requirement exceeds the total medal requirement."))
            }
        }
        return diagnostics
    }
}
