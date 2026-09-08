//
//  QuestionFactory.swift
//  BlitzMath
//
//  Deterministic, seeded question generation bound to a module's generator kind
//  (SRS AS-03, section 8.3). Pure domain code: no bundle access, no persistence.
//

import Foundation

// MARK: - Answer forms

enum AnswerForm: Sendable, Equatable {
    case integer(Int)
    case quotientRemainder(quotient: Int, remainder: Int)
    case fraction(numerator: Int, denominator: Int)
    case mixedFraction(whole: Int, numerator: Int, denominator: Int)
    case decimal(Double)
    case choice(index: Int)
}

/// What the player typed or tapped, before comparison.
enum AnswerInput: Sendable, Equatable {
    case integer(Int)
    case quotientRemainder(quotient: Int, remainder: Int)
    case fraction(numerator: Int, denominator: Int)
    case mixedFraction(whole: Int, numerator: Int, denominator: Int)
    case decimal(Double)
    case choice(index: Int)
}

// MARK: - Question

struct Question: Sendable, Equatable, Identifiable {
    let id: Int
    /// Rendered as text or as a vector layout, depending on `presentation`.
    let prompt: String
    let presentation: Presentation
    let answer: AnswerForm
    let choices: [String]
    let hint: String?

    enum Presentation: String, Sendable {
        case inline           // 7 + 8 =
        case verticalColumn   // stacked column arithmetic
        case fractionStack    // numerator over denominator
        case grid             // long multiplication grid
        case prose            // word problem
    }

    static let decimalTolerance = 1e-6

    /// Answer comparison, including lowest-terms normalisation (SRS 8.3).
    func isCorrect(_ input: AnswerInput) -> Bool {
        switch (answer, input) {
        case let (.integer(expected), .integer(given)):
            return expected == given

        case let (.quotientRemainder(q, r), .quotientRemainder(gq, gr)):
            return q == gq && r == gr

        case let (.fraction(n, d), .fraction(gn, gd)):
            return Fraction(numerator: n, denominator: d).reduced
                == Fraction(numerator: gn, denominator: gd).reduced

        case let (.mixedFraction(w, n, d), .mixedFraction(gw, gn, gd)):
            return Fraction.improper(whole: w, numerator: n, denominator: d).reduced
                == Fraction.improper(whole: gw, numerator: gn, denominator: gd).reduced

        case let (.mixedFraction(w, n, d), .fraction(gn, gd)):
            return Fraction.improper(whole: w, numerator: n, denominator: d).reduced
                == Fraction(numerator: gn, denominator: gd).reduced

        case let (.decimal(expected), .decimal(given)):
            return abs(expected - given) < Self.decimalTolerance

        case let (.decimal(expected), .integer(given)):
            return abs(expected - Double(given)) < Self.decimalTolerance

        case let (.choice(expected), .choice(given)):
            return expected == given

        default:
            return false
        }
    }
}

// MARK: - Fraction helper

struct Fraction: Sendable, Equatable {
    var numerator: Int
    var denominator: Int

    static func improper(whole: Int, numerator: Int, denominator: Int) -> Fraction {
        let sign = whole < 0 ? -1 : 1
        return Fraction(numerator: abs(whole) * denominator + numerator, denominator: denominator * sign)
    }

    var reduced: Fraction {
        guard denominator != 0 else { return self }
        let divisor = max(1, Self.gcd(abs(numerator), abs(denominator)))
        let sign = denominator < 0 ? -1 : 1
        return Fraction(numerator: sign * numerator / divisor, denominator: sign * denominator / divisor)
    }

    var decimalValue: Double {
        denominator == 0 ? .nan : Double(numerator) / Double(denominator)
    }

    static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
    static func lcm(_ a: Int, _ b: Int) -> Int { a / max(1, gcd(a, b)) * b }
}

// MARK: - Seeded randomness

/// Small deterministic generator so a session is reproducible from its seed.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

// MARK: - Factory

enum QuestionFactory {

    /// Every kind the payload may reference. Validation rejects anything outside this set.
    static let supportedKinds: Set<String> = [
        "addition_within_10", "addition_within_24", "subtraction_small_step", "mixed_within_20",
        "vertical_addition", "vertical_addition_carry", "vertical_subtraction_borrow", "column_addition",
        "times_tables", "long_multiplication",
        "division_exact", "division_remainder", "fraction_identification", "fraction_reduction",
        "fraction_add_like", "fraction_add_unlike", "mixed_fraction_subtract",
        "three_fraction_mixed", "fraction_decimal_convert", "algebraic_word_problem", "order_of_operations"
    ]

    /// Builds the full question set before the clock starts (SRS FR-SES-002).
    static func build(module: CurriculumModule, seed: UInt64) -> [Question] {
        var rng = SeededGenerator(seed: seed)
        let spec = module.resolvedGenerator
        return (0..<module.resolvedQuestionCount).map { index in
            make(kind: spec.kind, spec: spec, id: index, rng: &rng)
        }
    }

    // MARK: Dispatch

    private static func make(kind: String, spec: GeneratorSpec, id: Int, rng: inout SeededGenerator) -> Question {
        switch kind {
        case "addition_within_10":
            additive(id: id, upper: spec.param("max", default: 10), subtract: false, rng: &rng)
        case "addition_within_24":
            additive(id: id, upper: spec.param("max", default: 24), subtract: false, rng: &rng)
        case "subtraction_small_step":
            smallStepSubtraction(id: id, spec: spec, rng: &rng)
        case "mixed_within_20":
            additive(id: id, upper: spec.param("max", default: 20), subtract: Bool.random(using: &rng), rng: &rng)
        case "vertical_addition", "vertical_addition_carry":
            vertical(id: id, spec: spec, carrying: kind.hasSuffix("carry"), rng: &rng)
        case "vertical_subtraction_borrow":
            verticalSubtraction(id: id, spec: spec, rng: &rng)
        case "column_addition":
            columnAddition(id: id, spec: spec, rng: &rng)
        case "times_tables":
            timesTable(id: id, spec: spec, rng: &rng)
        case "long_multiplication":
            longMultiplication(id: id, spec: spec, rng: &rng)
        case "division_exact":
            exactDivision(id: id, spec: spec, rng: &rng)
        case "division_remainder":
            remainderDivision(id: id, spec: spec, rng: &rng)
        case "fraction_identification":
            fractionIdentification(id: id, spec: spec, rng: &rng)
        case "fraction_reduction":
            fractionReduction(id: id, spec: spec, rng: &rng)
        case "fraction_add_like":
            fractionAddition(id: id, spec: spec, likeDenominators: true, rng: &rng)
        case "fraction_add_unlike":
            fractionAddition(id: id, spec: spec, likeDenominators: false, rng: &rng)
        case "mixed_fraction_subtract":
            mixedFractionSubtraction(id: id, spec: spec, rng: &rng)
        case "three_fraction_mixed":
            threeFractionMixed(id: id, spec: spec, rng: &rng)
        case "fraction_decimal_convert":
            fractionToDecimal(id: id, spec: spec, rng: &rng)
        case "algebraic_word_problem":
            wordProblem(id: id, spec: spec, rng: &rng)
        default:
            orderOfOperations(id: id, spec: spec, rng: &rng)
        }
    }

    // MARK: Levels A and B

    private static func additive(id: Int, upper: Int, subtract: Bool, rng: inout SeededGenerator) -> Question {
        let total = Int.random(in: max(2, upper / 2)...upper, using: &rng)
        let left = Int.random(in: 1..<total, using: &rng)
        let right = total - left
        return subtract
            ? Question(id: id, prompt: "\(total) − \(left) =", presentation: .inline,
                       answer: .integer(right), choices: [], hint: "Count back from \(total).")
            : Question(id: id, prompt: "\(left) + \(right) =", presentation: .inline,
                       answer: .integer(total), choices: [], hint: "Start at \(left) and count on \(right).")
    }

    private static func smallStepSubtraction(id: Int, spec: GeneratorSpec, rng: inout SeededGenerator) -> Question {
        let step = Int.random(in: 1...spec.param("max_step", default: 2), using: &rng)
        let start = Int.random(in: (step + 1)...spec.param("max", default: 20), using: &rng)
        return Question(id: id, prompt: "\(start) − \(step) =", presentation: .inline,
                        answer: .integer(start - step), choices: [], hint: "Take away \(step).")
    }

    private static func vertical(id: Int, spec: GeneratorSpec, carrying: Bool, rng: inout SeededGenerator) -> Question {
        let lower = spec.param("min", default: 10)
        let upper = spec.param("max", default: 89)
        var left = Int.random(in: lower...upper, using: &rng)
        var right = Int.random(in: lower...upper, using: &rng)
        if carrying && (left % 10) + (right % 10) < 10 {
            left += 10 - (left % 10) - 1
            right += 10 - (right % 10)
        }
        return Question(id: id, prompt: "\(left) + \(right)", presentation: .verticalColumn,
                        answer: .integer(left + right), choices: [],
                        hint: carrying ? "Add the ones first, then carry into the tens." : "Add the ones, then the tens.")
    }

    private static func verticalSubtraction(id: Int, spec: GeneratorSpec, rng: inout SeededGenerator) -> Question {
        let upper = spec.param("max", default: 99)
        let left = Int.random(in: spec.param("min", default: 21)...upper, using: &rng)
        let right = Int.random(in: 10..<max(11, left), using: &rng)
        return Question(id: id, prompt: "\(left) − \(right)", presentation: .verticalColumn,
                        answer: .integer(left - right), choices: [],
                        hint: "If the ones digit is too small, borrow from the tens.")
    }

    private static func columnAddition(id: Int, spec: GeneratorSpec, rng: inout SeededGenerator) -> Question {
        let terms = spec.param("terms", default: 3)
        let values = (0..<terms).map { _ in
            Int.random(in: spec.param("min", default: 8)...spec.param("max", default: 60), using: &rng)
        }
        return Question(id: id, prompt: values.map(String.init).joined(separator: " + "),
                        presentation: .verticalColumn, answer: .integer(values.reduce(0, +)),
                        choices: [], hint: "Add two numbers first, then add the third.")
    }

    // MARK: Level C

    private static func timesTable(id: Int, spec: GeneratorSpec, rng: inout SeededGenerator) -> Question {
        let table = Int.random(in: spec.param("min_table", default: 1)...spec.param("max_table", default: 9), using: &rng)
        let multiplier = Int.random(in: 1...12, using: &rng)
        return Question(id: id, prompt: "\(table) × \(multiplier) =", presentation: .inline,
                        answer: .integer(table * multiplier), choices: [],
                        hint: "\(table) added \(multiplier) times.")
    }

    private static func longMultiplication(id: Int, spec: GeneratorSpec, rng: inout SeededGenerator) -> Question {
        let left = randomNumber(digits: spec.param("left_digits", default: 2), rng: &rng)
        let right = randomNumber(digits: spec.param("right_digits", default: 1), rng: &rng)
        return Question(id: id, prompt: "\(left) × \(right) =", presentation: .grid,
                        answer: .integer(left * right), choices: [],
                        hint: "Split \(left) into tens and ones, multiply each part, then add.")
    }

    // MARK: Level D

    private static func exactDivision(id: Int, spec: GeneratorSpec, rng: inout SeededGenerator) -> Question {
        let divisor = Int.random(in: 2...spec.param("max_divisor", default: 9), using: &rng)
        let quotient = Int.random(in: 2...spec.param("max_quotient", default: 12), using: &rng)
        return Question(id: id, prompt: "\(divisor * quotient) ÷ \(divisor) =", presentation: .inline,
                        answer: .integer(quotient), choices: [],
                        hint: "How many groups of \(divisor) fit inside \(divisor * quotient)?")
    }

    private static func remainderDivision(id: Int, spec: GeneratorSpec, rng: inout SeededGenerator) -> Question {
        let divisor = Int.random(in: 2...spec.param("max_divisor", default: 9), using: &rng)
        let dividend = Int.random(in: (divisor + 1)...spec.param("max_dividend", default: 99), using: &rng)
        return Question(id: id, prompt: "\(dividend) ÷ \(divisor) =", presentation: .inline,
                        answer: .quotientRemainder(quotient: dividend / divisor, remainder: dividend % divisor),
                        choices: [], hint: "Give the whole groups, then what is left over.")
    }

    private static func fractionIdentification(id: Int, spec: GeneratorSpec, rng: inout SeededGenerator) -> Question {
        let denominator = Int.random(in: 2...spec.param("max_denominator", default: 12), using: &rng)
        let numerator = Int.random(in: 1..<denominator, using: &rng)
        let correct = "\(numerator)/\(denominator)"
        var options = Set([correct, "\(denominator)/\(numerator)",
                           "\(numerator)/\(denominator + 1)", "\(max(1, numerator - 1))/\(denominator)"])
        options.insert(correct)
        let ordered = options.sorted().shuffled(using: &rng)
        let index = ordered.firstIndex(of: correct) ?? 0
        return Question(id: id, prompt: "\(numerator) of \(denominator) equal parts are shaded. Which fraction is that?",
                        presentation: .fractionStack, answer: .choice(index: index),
                        choices: ordered, hint: "The parts shaded go on top.")
    }

    private static func fractionReduction(id: Int, spec: GeneratorSpec, rng: inout SeededGenerator) -> Question {
        let cap = spec.param("max_denominator", default: 24)
        let base = Int.random(in: 2...6, using: &rng)
        let denominator = Int.random(in: 2...max(3, cap / base), using: &rng)
        let numerator = Int.random(in: 1..<max(2, denominator), using: &rng)
        let reduced = Fraction(numerator: numerator, denominator: denominator).reduced
        return Question(id: id, prompt: "Reduce \(numerator * base)/\(denominator * base)",
                        presentation: .fractionStack,
                        answer: .fraction(numerator: reduced.numerator, denominator: reduced.denominator),
                        choices: [], hint: "Divide the top and the bottom by the same number.")
    }

    // MARK: Level E

    private static func fractionAddition(id: Int, spec: GeneratorSpec, likeDenominators: Bool,
                                         rng: inout SeededGenerator) -> Question {
        let cap = spec.param("max_denominator", default: 12)
        let leftDenominator = Int.random(in: 2...cap, using: &rng)
        let rightDenominator = likeDenominators ? leftDenominator : Int.random(in: 2...cap, using: &rng)
        let leftNumerator = Int.random(in: 1..<max(2, leftDenominator), using: &rng)
        let rightNumerator = Int.random(in: 1..<max(2, rightDenominator), using: &rng)

        let denominator = Fraction.lcm(leftDenominator, rightDenominator)
        let numerator = leftNumerator * (denominator / leftDenominator)
                      + rightNumerator * (denominator / rightDenominator)
        let sum = Fraction(numerator: numerator, denominator: denominator).reduced

        return Question(id: id,
                        prompt: "\(leftNumerator)/\(leftDenominator) + \(rightNumerator)/\(rightDenominator) =",
                        presentation: .fractionStack,
                        answer: .fraction(numerator: sum.numerator, denominator: sum.denominator),
                        choices: [],
                        hint: likeDenominators
                            ? "The bottoms match, so add the tops."
                            : "Find a common bottom number first.")
    }

    private static func mixedFractionSubtraction(id: Int, spec: GeneratorSpec, rng: inout SeededGenerator) -> Question {
        let denominator = Int.random(in: 2...spec.param("max_denominator", default: 12), using: &rng)
        let maxWhole = spec.param("max_whole", default: 6)
        let leftWhole = Int.random(in: 2...maxWhole, using: &rng)
        let rightWhole = Int.random(in: 1..<leftWhole, using: &rng)
        let leftNumerator = Int.random(in: 1..<max(2, denominator), using: &rng)
        let rightNumerator = Int.random(in: 1..<max(2, denominator), using: &rng)

        let left = Fraction.improper(whole: leftWhole, numerator: leftNumerator, denominator: denominator)
        let right = Fraction.improper(whole: rightWhole, numerator: rightNumerator, denominator: denominator)
        let difference = Fraction(numerator: left.numerator - right.numerator, denominator: denominator).reduced

        return Question(id: id,
                        prompt: "\(leftWhole) \(leftNumerator)/\(denominator) − \(rightWhole) \(rightNumerator)/\(denominator) =",
                        presentation: .fractionStack,
                        answer: .fraction(numerator: difference.numerator, denominator: difference.denominator),
                        choices: [], hint: "Turn both into improper fractions, then subtract.")
    }

    // MARK: Level F

    private static func threeFractionMixed(id: Int, spec: GeneratorSpec, rng: inout SeededGenerator) -> Question {
        let cap = spec.param("max_denominator", default: 12)
        let denominators = (0..<3).map { _ in Int.random(in: 2...cap, using: &rng) }
        let numerators = denominators.map { Int.random(in: 1..<max(2, $0), using: &rng) }

        let common = denominators.reduce(1) { Fraction.lcm($0, $1) }
        let scaled = zip(numerators, denominators).map { $0 * (common / $1) }
        let total = scaled[0] + scaled[1] - scaled[2]
        let result = Fraction(numerator: total, denominator: common).reduced

        let prompt = "\(numerators[0])/\(denominators[0]) + \(numerators[1])/\(denominators[1]) − \(numerators[2])/\(denominators[2]) ="
        return Question(id: id, prompt: prompt, presentation: .fractionStack,
                        answer: .fraction(numerator: result.numerator, denominator: result.denominator),
                        choices: [], hint: "One common bottom number covers all three.")
    }

    private static func fractionToDecimal(id: Int, spec: GeneratorSpec, rng: inout SeededGenerator) -> Question {
        let terminating = [2, 4, 5, 8, 10, 16, 20].filter { $0 <= spec.param("max_denominator", default: 20) }
        let denominator = terminating.randomElement(using: &rng) ?? 4
        let numerator = Int.random(in: 1..<denominator, using: &rng)
        return Question(id: id, prompt: "Write \(numerator)/\(denominator) as a decimal",
                        presentation: .fractionStack,
                        answer: .decimal(Double(numerator) / Double(denominator)),
                        choices: [], hint: "Divide the top by the bottom.")
    }

    private static func wordProblem(id: Int, spec: GeneratorSpec, rng: inout SeededGenerator) -> Question {
        let coefficient = Int.random(in: 2...spec.param("max_coefficient", default: 12), using: &rng)
        let solution = Int.random(in: 2...12, using: &rng)
        let constant = Int.random(in: 1...20, using: &rng)
        let total = coefficient * solution + constant
        return Question(id: id,
                        prompt: "A box holds \(coefficient) cards. There are \(total) cards in total, with \(constant) left outside the boxes. How many boxes are full?",
                        presentation: .prose, answer: .integer(solution), choices: [],
                        hint: "Take the loose cards away first, then divide.")
    }

    private static func orderOfOperations(id: Int, spec: GeneratorSpec, rng: inout SeededGenerator) -> Question {
        let cap = spec.param("max_term", default: 12)
        let a = Int.random(in: 2...cap, using: &rng)
        let b = Int.random(in: 2...cap, using: &rng)
        let c = Int.random(in: 2...cap, using: &rng)
        let d = Int.random(in: 2...cap, using: &rng)
        return Question(id: id, prompt: "(\(a) + \(b)) × \(c) − \(d) =", presentation: .inline,
                        answer: .integer((a + b) * c - d), choices: [],
                        hint: "Brackets first, then multiply, then subtract.")
    }

    // MARK: Helpers

    private static func randomNumber(digits: Int, rng: inout SeededGenerator) -> Int {
        let clamped = max(1, min(digits, 4))
        let lower = clamped == 1 ? 2 : Int(pow(10.0, Double(clamped - 1)))
        let upper = Int(pow(10.0, Double(clamped))) - 1
        return Int.random(in: lower...upper, using: &rng)
    }
}
