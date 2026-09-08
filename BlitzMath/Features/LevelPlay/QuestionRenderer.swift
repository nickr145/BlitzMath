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

    // MARK: - Presentation styles

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
                    .lineLimit(1)
            }

            if let lastOperand = operands.last {
                Divider()
                    .background(BlitzTheme.Palette.ink)
                    .padding(.bottom, 4)

                HStack(spacing: 4) {
                    Text(lastOperator)
                        .font(BlitzTheme.Typography.question)
                        .foregroundStyle(BlitzTheme.Palette.inkSecondary)
                    Text(lastOperand)
                        .font(BlitzTheme.Typography.question)
                        .foregroundStyle(BlitzTheme.Palette.ink)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder
    private static func fractionStackPresentation(_ question: Question) -> some View {
        Text("fraction stack")
            .font(BlitzTheme.Typography.question)
    }

    @ViewBuilder
    private static func gridPresentation(_ question: Question) -> some View {
        Text("grid")
            .font(BlitzTheme.Typography.question)
    }
}
