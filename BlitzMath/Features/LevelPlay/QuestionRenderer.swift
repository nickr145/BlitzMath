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
        Text("vertical column")
            .font(BlitzTheme.Typography.question)
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
