//
//  LevelSessionView.swift
//  BlitzMath
//
//  Presentation for one drill session. All state lives in the controller;
//  this file only renders it and forwards input (SRS UI-02, FR-ACC).
//

import SwiftUI

struct LevelSessionView: View {

    @State private var controller: LevelSessionController
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dismiss) private var dismiss
    /// In-app Reduce Motion preference (SRS FR-SET-002).
    @AppStorage(BlitzTheme.Motion.reduceMotionOverrideKey) private var reduceMotionOverride = false

    private var reduceMotion: Bool { systemReduceMotion || reduceMotionOverride }

    private let moduleID: String

    init(moduleID: String, controller: LevelSessionController) {
        self.moduleID = moduleID
        _controller = State(initialValue: controller)
    }

    var body: some View {
        ZStack {
            GraphPaperGrid().ignoresSafeArea()

            switch controller.phase {
            case .idle, .running, .paused, .grading:
                sessionSurface
            case .summary, .abandoned:
                sessionSurface
            case .failed(let message):
                contentUnavailable(message)
            }
        }
        .task {
            if controller.phase == .idle { controller.start(moduleID: moduleID) }
        }
        .sheet(isPresented: .constant(controller.summary != nil)) {
            if let summary = controller.summary {
                SessionSummaryView(summary: summary,
                                   onRetrySave: { controller.retrySave() },
                                   onDone: {
                                       controller.dismissSummary()
                                       dismiss()
                                   })
                .presentationDetents([.medium, .large])
                .interactiveDismissDisabled()
            }
        }
        .overlay(alignment: .top) { pausedBanner }
    }

    // MARK: Surface

    private var sessionSurface: some View {
        VStack(spacing: BlitzTheme.Layout.stackGap) {
            header
            Spacer(minLength: 0)
            questionCard
            Spacer(minLength: 0)
            if let hint = controller.revealedHint { hintRow(hint) }
            AnswerPad(question: controller.currentQuestion,
                      isEnabled: controller.isRunning,
                      showedMistake: controller.lastAnswerWasIncorrect,
                      onSubmit: { controller.submit($0) },
                      onHint: { controller.revealHint() })
        }
        .padding(BlitzTheme.Layout.gutter)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: BlitzTheme.Layout.stackGap) {
            timerRing

            VStack(alignment: .leading, spacing: 4) {
                Text(controller.module?.name ?? "")
                    .font(BlitzTheme.Typography.title)
                    .foregroundStyle(BlitzTheme.Palette.ink)
                Text("Target \(controller.targetText)")
                    .font(BlitzTheme.Typography.caption)
                    .foregroundStyle(BlitzTheme.Palette.inkSecondary)
                Text("Question \(min(controller.answeredCount + 1, controller.totalCount)) of \(controller.totalCount)")
                    .font(BlitzTheme.Typography.caption)
                    .foregroundStyle(BlitzTheme.Palette.inkSecondary)
            }

            Spacer()

            Button("Leave") { controller.abandon() }
                .font(BlitzTheme.Typography.caption)
                .frame(minWidth: BlitzTheme.Layout.minimumTarget, minHeight: BlitzTheme.Layout.minimumTarget)
                .accessibilityLabel("Leave this module")
        }
    }

    private var timerRing: some View {
        ZStack {
            Circle()
                .stroke(BlitzTheme.Palette.rule, lineWidth: BlitzTheme.Layout.ringWidth)
            // Stroke width intensifies with pace, so the threshold reads as
            // shape as well as colour (FR-BLZ-005, FR-FBK-004).
            SCTRing(fraction: controller.sctFraction)
                .stroke(BlitzTheme.colour(for: controller.pace),
                        style: StrokeStyle(lineWidth: BlitzTheme.ringStrokeWidth(for: controller.pace), lineCap: .round))
                .animation(BlitzTheme.Motion.ringTick, value: controller.sctFraction)
                .animation(BlitzTheme.Motion.ringTick, value: controller.pace)
            VStack(spacing: 2) {
                Text(controller.elapsedText)
                    .font(BlitzTheme.Typography.timer)
                    .foregroundStyle(BlitzTheme.Palette.ink)
                // Pace is stated in text as well as colour (FR-BLZ-005, FR-FBK-004).
                Text(paceLabel)
                    .font(BlitzTheme.Typography.caption)
                    .foregroundStyle(BlitzTheme.Palette.inkSecondary)
            }
        }
        .frame(width: BlitzTheme.Layout.ringDiameter, height: BlitzTheme.Layout.ringDiameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time")
        .accessibilityValue("\(controller.elapsedText) of \(controller.targetText) target. \(paceLabel).")
    }

    private var paceLabel: String {
        switch controller.pace {
        case .comfortable: "On pace"
        case .tightening: "Speed up"
        case .overTarget: "Past target"
        }
    }

    // MARK: Question

    @ViewBuilder
    private var questionCard: some View {
        if let question = controller.currentQuestion {
            VStack(spacing: BlitzTheme.Layout.stackGap) {
                QuestionRenderer.render(question)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, BlitzTheme.Layout.gutter)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .background(
                RoundedRectangle(cornerRadius: BlitzTheme.Layout.cardRadius)
                    .fill(BlitzTheme.Palette.surface)
                    .stroke(controller.lastAnswerWasIncorrect
                            ? BlitzTheme.Palette.overTarget
                            : BlitzTheme.Palette.rule, lineWidth: 1.5)
            )
            .animation(BlitzTheme.Motion.respectingReduceMotion(BlitzTheme.Motion.answerFeedback,
                                                                reduced: reduceMotion),
                       value: controller.lastAnswerWasIncorrect)
            .accessibilityLabel(question.prompt)
        }
    }

    private func hintRow(_ hint: String) -> some View {
        Text(hint)
            .font(BlitzTheme.Typography.body)
            .foregroundStyle(BlitzTheme.Palette.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var pausedBanner: some View {
        if controller.phase == .paused {
            VStack(spacing: BlitzTheme.Layout.tightGap) {
                Text("Paused. The clock is stopped.")
                    .font(BlitzTheme.Typography.body)
                Button("Keep going") { controller.resume() }
                    .buttonStyle(.borderedProminent)
                    .tint(BlitzTheme.Palette.velocity)
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: BlitzTheme.Layout.cardRadius))
            .padding(.top, BlitzTheme.Layout.gutter)
        }
    }

    private func contentUnavailable(_ message: String) -> some View {
        ContentUnavailableView {
            Label("This module will not open", systemImage: "questionmark.square.dashed")
        } description: {
            Text(message)
        } actions: {
            Button("Back to the map") { dismiss() }
        }
    }
}

// MARK: - Answer pad

struct AnswerPad: View {
    let question: Question?
    let isEnabled: Bool
    let showedMistake: Bool
    let onSubmit: (AnswerInput) -> Void
    let onHint: () -> Void

    @State private var primaryField = ""
    @State private var secondaryField = ""

    private var isFractionForm: Bool {
        guard let question else { return false }
        switch question.answer {
        case .fraction, .mixedFraction, .quotientRemainder: return true
        default: return false
        }
    }

    var body: some View {
        VStack(spacing: BlitzTheme.Layout.stackGap) {
            if let question, case .choice = question.answer {
                choiceGrid(question.choices)
            } else {
                entryRow
                digitPad
            }

            HStack {
                Button("Hint", action: onHint)
                    .font(BlitzTheme.Typography.caption)
                    .frame(minHeight: BlitzTheme.Layout.minimumTarget)
                Spacer()
                Button("Check", action: submit)
                    .buttonStyle(.borderedProminent)
                    .tint(BlitzTheme.Palette.velocity)
                    .frame(minHeight: BlitzTheme.Layout.minimumTarget)
                    .disabled(primaryField.isEmpty || !isEnabled)
            }
        }
        .disabled(!isEnabled)
        .onChange(of: question?.id) { _, _ in
            primaryField = ""
            secondaryField = ""
        }
    }

    private var entryRow: some View {
        HStack(spacing: BlitzTheme.Layout.tightGap) {
            fieldBox(primaryField, label: isFractionForm ? "Top number" : "Answer")
            if isFractionForm {
                Text("/")
                    .font(BlitzTheme.Typography.question)
                    .foregroundStyle(BlitzTheme.Palette.inkSecondary)
                fieldBox(secondaryField, label: "Bottom number")
            }
        }
    }

    private func fieldBox(_ value: String, label: String) -> some View {
        Text(value.isEmpty ? " " : value)
            .font(BlitzTheme.Typography.question)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(
                RoundedRectangle(cornerRadius: BlitzTheme.Layout.padRadius)
                    .stroke(showedMistake ? BlitzTheme.Palette.overTarget : BlitzTheme.Palette.rule,
                            lineWidth: 1.5)
            )
            .accessibilityLabel(label)
            .accessibilityValue(value.isEmpty ? "empty" : value)
    }

    private var digitPad: some View {
        Grid(horizontalSpacing: BlitzTheme.Layout.tightGap, verticalSpacing: BlitzTheme.Layout.tightGap) {
            ForEach([["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], [".", "0", "⌫"]], id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { key in
                        Button { tap(key) } label: {
                            Text(key)
                                .font(BlitzTheme.Typography.padDigit)
                                .frame(maxWidth: .infinity, minHeight: BlitzTheme.Layout.minimumTarget + 8)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(key == "⌫" ? "Delete" : key)
                    }
                }
            }
            if isFractionForm {
                GridRow {
                    Button("Next box") { /* focus moves to the second field */ }
                        .frame(maxWidth: .infinity, minHeight: BlitzTheme.Layout.minimumTarget)
                        .gridCellColumns(3)
                }
            }
        }
    }

    private func choiceGrid(_ choices: [String]) -> some View {
        Grid(horizontalSpacing: BlitzTheme.Layout.tightGap, verticalSpacing: BlitzTheme.Layout.tightGap) {
            ForEach(Array(stride(from: 0, to: choices.count, by: 2)), id: \.self) { start in
                GridRow {
                    ForEach(start..<min(start + 2, choices.count), id: \.self) { index in
                        Button { onSubmit(.choice(index: index)) } label: {
                            Text(choices[index])
                                .font(BlitzTheme.Typography.padDigit)
                                .frame(maxWidth: .infinity, minHeight: BlitzTheme.Layout.minimumTarget + 12)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    // MARK: Input handling

    private func tap(_ key: String) {
        switch key {
        case "⌫":
            if isFractionForm && !secondaryField.isEmpty { secondaryField.removeLast() }
            else if !primaryField.isEmpty { primaryField.removeLast() }
        default:
            if isFractionForm && !primaryField.isEmpty && secondaryField.count < 4 { secondaryField += key }
            else if primaryField.count < 6 { primaryField += key }
        }
    }

    private func submit() {
        guard let question else { return }
        switch question.answer {
        case .integer:
            if let value = Int(primaryField) { onSubmit(.integer(value)) }
        case .decimal:
            if let value = Double(primaryField) { onSubmit(.decimal(value)) }
        case .fraction, .mixedFraction:
            if let top = Int(primaryField), let bottom = Int(secondaryField), bottom != 0 {
                onSubmit(.fraction(numerator: top, denominator: bottom))
            }
        case .quotientRemainder:
            if let quotient = Int(primaryField), let remainder = Int(secondaryField) {
                onSubmit(.quotientRemainder(quotient: quotient, remainder: remainder))
            }
        case .choice:
            break
        }
        primaryField = ""
        secondaryField = ""
    }
}

// MARK: - Summary

struct SessionSummaryView: View {
    let summary: LevelSessionController.Summary
    let onRetrySave: () -> Void
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    /// In-app Reduce Motion preference (SRS FR-SET-002).
    @AppStorage(BlitzTheme.Motion.reduceMotionOverrideKey) private var reduceMotionOverride = false
    @State private var revealed = false

    private var reduceMotion: Bool { systemReduceMotion || reduceMotionOverride }

    var body: some View {
        VStack(spacing: BlitzTheme.Layout.stackGap) {
            MedalBadge()
                .stroke(BlitzTheme.colour(for: summary.medal), lineWidth: 4)
                .frame(width: 96, height: 110)
                .scaleEffect(revealed ? 1 : 0.85)
                .opacity(revealed ? 1 : 0)
                .animation(BlitzTheme.Motion.respectingReduceMotion(BlitzTheme.Motion.medalReveal,
                                                                    reduced: reduceMotion),
                           value: revealed)

            Text(summary.medal == .none ? "Module not finished" : "\(summary.medal.displayName) medal")
                .font(BlitzTheme.Typography.title)

            Text(summary.rationale)
                .font(BlitzTheme.Typography.body)
                .foregroundStyle(BlitzTheme.Palette.inkSecondary)
                .multilineTextAlignment(.center)

            statRow

            if summary.isNewBest && summary.medal != .none {
                Text("New best for \(summary.module.name).")
                    .font(BlitzTheme.Typography.caption)
                    .foregroundStyle(BlitzTheme.Palette.correct)
            }

            ForEach(summary.newlyUnlockedLevelIDs, id: \.self) { levelID in
                Text("World \(levelID) is open.")
                    .font(BlitzTheme.Typography.body)
                    .foregroundStyle(BlitzTheme.Palette.velocity)
            }

            if summary.saveFailed {
                VStack(spacing: BlitzTheme.Layout.tightGap) {
                    Text("This run was not saved.")
                        .font(BlitzTheme.Typography.caption)
                    Button("Try saving again", action: onRetrySave)
                }
            }

            Button("Back to the map", action: onDone)
                .buttonStyle(.borderedProminent)
                .tint(BlitzTheme.Palette.velocity)
                .frame(minHeight: BlitzTheme.Layout.minimumTarget)
        }
        .padding(BlitzTheme.Layout.gutter)
        .onAppear { revealed = true }
    }

    private var statRow: some View {
        HStack(spacing: 28) {
            stat("Time", String(format: "%.1f s", summary.outcome.elapsedSeconds))
            stat("Target", "\(summary.module.targetSCTSeconds) s")
            stat("Correct", "\(summary.outcome.correctFirstTryCount) of \(summary.outcome.questionCount)")
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(BlitzTheme.Typography.body).foregroundStyle(BlitzTheme.Palette.ink)
            Text(label).font(BlitzTheme.Typography.caption).foregroundStyle(BlitzTheme.Palette.inkSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

#Preview("Session, level A") {
    let curriculum = MockCurriculumProvider()
    let store = MockProgressStore()
    return LevelSessionView(
        moduleID: "A_01",
        controller: LevelSessionController(curriculum: curriculum, store: store, seedProvider: { 42 })
    )
}

#Preview("Session, fractions") {
    let curriculum = MockCurriculumProvider()
    let store = MockProgressStore()
    return LevelSessionView(
        moduleID: "E_02",
        controller: LevelSessionController(curriculum: curriculum, store: store, seedProvider: { 7 })
    )
}
