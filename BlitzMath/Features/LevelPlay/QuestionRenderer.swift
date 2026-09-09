//
//  QuestionRenderer.swift
//  BlitzMath
//
//  Renders question prompts according to their presentation style using SwiftUI shapes
//  and BlitzTheme tokens (UI-03, CN-03, FR-ACC-002).
//

import SwiftUI

enum QuestionRenderer {

    /// Renders a question prompt according to its presentation style.
    @ViewBuilder
    static func render(_ question: Question) -> some View {
        switch question.presentation {
        case .inline:
            inlinePresentation(question)
        case .prose:
            prosePresentation(question)
        case .verticalColumn:
            verticalColumnPresentation(question)
        case .fractionStack:
            fractionStackPresentation(question)
        case .grid:
            gridPresentation(question)
        }
    }

    // MARK: - Parsing helpers

    /// Extracts numeric operands and operator from a prompt like "23 + 45" or "100 − 25 + 10".
    /// Returns (operands: [String], operator: String?, hasEquals: Bool)
    /// Example: "23 + 45 =" → (["23", "45"], "+", true)
    private static func parseArithmetic(_ prompt: String) -> (operands: [String], lastOperator: String, hasEquals: Bool) {
        let trimmed = prompt.trimmingCharacters(in: .whitespaces)
        let hasEquals = trimmed.hasSuffix("=")
        let withoutEquals = hasEquals ? String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces) : trimmed

        // Split by operators: +, −, ×, ÷
        var operands: [String] = []
        var lastOperator = "+"
        var current = ""

        for char in withoutEquals {
            switch char {
            case "+", "−", "×", "÷":
                if !current.trimmingCharacters(in: .whitespaces).isEmpty {
                    operands.append(current.trimmingCharacters(in: .whitespaces))
                }
                lastOperator = String(char)
                current = ""
            default:
                current.append(char)
            }
        }

        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            operands.append(current.trimmingCharacters(in: .whitespaces))
        }

        return (operands: operands, lastOperator: lastOperator, hasEquals: hasEquals)
    }

    /// Extracts fractions from prompts like "3/4 + 5/8" or "Reduce 6/8".
    /// Returns array of (numerator, denominator) tuples and the operation.
    /// Example: "3/4 + 5/8 =" → (fractions: [(3,4), (5,8)], operation: "+", hasEquals: true)
    private static func parseFractions(_ prompt: String) -> (fractions: [(num: String, denom: String)], operation: String, hasEquals: Bool) {
        let trimmed = prompt.trimmingCharacters(in: .whitespaces)
        let hasEquals = trimmed.hasSuffix("=")
        let withoutEquals = hasEquals ? String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces) : trimmed

        var fractions: [(num: String, denom: String)] = []
        var operation = ""

        // Split by operators
        let parts = withoutEquals.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        for part in parts {
            if part.contains("/") {
                let components = part.components(separatedBy: "/")
                if components.count == 2 {
                    fractions.append((num: components[0], denom: components[1]))
                }
            } else if ["+", "−", "×", "÷"].contains(part) {
                operation = part
            }
        }

        return (fractions: fractions, operation: operation, hasEquals: hasEquals)
    }

    /// Extracts operands from multiplication prompts like "23 × 4".
    /// Returns (multiplicand, multiplier, hasEquals).
    private static func parseMultiplication(_ prompt: String) -> (multiplicand: String, multiplier: String, hasEquals: Bool) {
        let trimmed = prompt.trimmingCharacters(in: .whitespaces)
        let hasEquals = trimmed.hasSuffix("=")
        let withoutEquals = hasEquals ? String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces) : trimmed

        let parts = withoutEquals.components(separatedBy: "×").map { $0.trimmingCharacters(in: .whitespaces) }
        let multiplicand = parts.first ?? ""
        let multiplier = parts.count > 1 ? parts[1] : ""

        return (multiplicand: multiplicand, multiplier: multiplier, hasEquals: hasEquals)
    }

    // MARK: - Presentation styles

    /// Renders a single fraction with numerator over denominator and horizontal bar.
    @ViewBuilder
    private static func fractionView(numerator: String, denominator: String) -> some View {
        VStack(spacing: 2) {
            Text(numerator)
                .font(BlitzTheme.Typography.question)
                .foregroundStyle(BlitzTheme.Palette.ink)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)

            Divider()
                .background(BlitzTheme.Palette.ink)

            Text(denominator)
                .font(BlitzTheme.Typography.question)
                .foregroundStyle(BlitzTheme.Palette.ink)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 60)
    }

    @ViewBuilder
    private static func inlinePresentation(_ question: Question) -> some View {
        Text(question.prompt)
            .font(BlitzTheme.Typography.question)
            .multilineTextAlignment(.center)
            .foregroundStyle(BlitzTheme.Palette.ink)
    }

    @ViewBuilder
    private static func prosePresentation(_ question: Question) -> some View {
        Text(question.prompt)
            .font(BlitzTheme.Typography.questionCompact)
            .multilineTextAlignment(.center)
            .foregroundStyle(BlitzTheme.Palette.ink)
    }

    @ViewBuilder
    private static func verticalColumnPresentation(_ question: Question) -> some View {
        let (operands, lastOperator, _) = parseArithmetic(question.prompt)

        VStack(alignment: .trailing, spacing: BlitzTheme.Layout.tightGap) {
            ForEach(Array(operands.dropLast()), id: \.self) { operand in
                Text(operand)
                    .font(BlitzTheme.Typography.question)
                    .foregroundStyle(BlitzTheme.Palette.ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }

            if let lastOperand = operands.last {
                Divider()
                    .background(BlitzTheme.Palette.ink)
                    .padding(.bottom, BlitzTheme.Layout.tightGap / 2)

                HStack(spacing: BlitzTheme.Layout.tightGap / 2) {
                    Text(lastOperator)
                        .font(BlitzTheme.Typography.question)
                        .foregroundStyle(BlitzTheme.Palette.inkSecondary)
                    Text(lastOperand)
                        .font(BlitzTheme.Typography.question)
                        .foregroundStyle(BlitzTheme.Palette.ink)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder
    private static func fractionStackPresentation(_ question: Question) -> some View {
        let (fractions, operation, _) = parseFractions(question.prompt)

        HStack(alignment: .center, spacing: BlitzTheme.Layout.tightGap) {
            ForEach(Array(fractions.enumerated()), id: \.offset) { index, fraction in
                fractionView(numerator: fraction.num, denominator: fraction.denom)

                if index < fractions.count - 1 && !operation.isEmpty {
                    Text(operation)
                        .font(BlitzTheme.Typography.question)
                        .foregroundStyle(BlitzTheme.Palette.inkSecondary)
                        .frame(maxHeight: 60)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private static func gridPresentation(_ question: Question) -> some View {
        let (multiplicand, multiplier, _) = parseMultiplication(question.prompt)

        VStack(alignment: .trailing, spacing: BlitzTheme.Layout.tightGap) {
            // Multiplicand × Multiplier
            HStack(alignment: .bottom, spacing: 8) {
                Text(multiplicand)
                    .font(BlitzTheme.Typography.question)
                    .foregroundStyle(BlitzTheme.Palette.ink)
                    .minimumScaleFactor(0.6)
                Text("×")
                    .font(BlitzTheme.Typography.question)
                    .foregroundStyle(BlitzTheme.Palette.inkSecondary)
                Text(multiplier)
                    .font(BlitzTheme.Typography.question)
                    .foregroundStyle(BlitzTheme.Palette.ink)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            // Divider line
            Divider()
                .background(BlitzTheme.Palette.ink)

            // Hint text about partial products
            Text("Split and multiply each part →")
                .font(BlitzTheme.Typography.caption)
                .foregroundStyle(BlitzTheme.Palette.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
    }
}
