//
//  PlacementView.swift
//  BlitzMath
//
//  Onboarding choice, the four timed sections, and the result screen
//  (SRS Addendum 01, FR-ONB and FR-PLC).
//

import SwiftUI

// MARK: - Onboarding choice

/// Two equal options. Neither is pre-selected or visually favoured (FR-ONB-004).
struct OnboardingChoiceView: View {

    let onTakeTest: () -> Void
    let onStartAtBeginning: () -> Void

    var body: some View {
        ZStack {
            GraphPaperGrid().ignoresSafeArea()

            VStack(spacing: BlitzTheme.Layout.stackGap) {
                Spacer()

                Text("Where should you start?")
                    .font(BlitzTheme.Typography.title)
                    .foregroundStyle(BlitzTheme.Palette.ink)

                Text("Answer a few questions and BlitzMath will open the world that fits. About eight minutes, nothing is graded, and you can skip anything you have not learned yet.")
                    .font(BlitzTheme.Typography.body)
                    .foregroundStyle(BlitzTheme.Palette.inkSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BlitzTheme.Layout.gutter)

                Spacer()

                VStack(spacing: BlitzTheme.Layout.tightGap) {
                    Button("Find my starting point", action: onTakeTest)
                        .frame(maxWidth: .infinity, minHeight: BlitzTheme.Layout.minimumTarget + 8)
                        .buttonStyle(.bordered)

                    Button("Start at the beginning", action: onStartAtBeginning)
                        .frame(maxWidth: .infinity, minHeight: BlitzTheme.Layout.minimumTarget + 8)
                        .buttonStyle(.bordered)
                }
                .padding(.bottom, BlitzTheme.Layout.gutter)
            }
            .padding(BlitzTheme.Layout.gutter)
        }
    }
}

// MARK: - Placement test

struct PlacementView: View {

    @State private var controller: PlacementController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Called once the player has been placed, or has left the test.
    let onFinished: () -> Void

    init(controller: PlacementController, onFinished: @escaping () -> Void) {
        _controller = State(initialValue: controller)
        self.onFinished = onFinished
    }

    var body: some View {
        ZStack {
            GraphPaperGrid().ignoresSafeArea()

            switch controller.phase {
            case .intro:            sectionIntro
            case .running, .paused: questionSurface
            case .sectionComplete:  sectionComplete
            case .results:          PlacementResultView(controller: controller, onDone: onFinished)
            case .leftEarly:        leftEarly
            case .failed(let text): unavailable(text)
            }
        }
        .task { if controller.result == nil { controller.beginTest() } }
        .animation(BlitzTheme.Motion.respectingReduceMotion(BlitzTheme.Motion.answerFeedback,
                                                            reduced: reduceMotion),
                   value: controller.phase)
    }

    // MARK: Section intro

    private var sectionIntro: some View {
        VStack(spacing: BlitzTheme.Layout.stackGap) {
            Spacer()
            Text(controller.sectionPositionText)
                .font(BlitzTheme.Typography.caption)
                .foregroundStyle(BlitzTheme.Palette.inkSecondary)
            Text(controller.currentSection?.title ?? "")
                .font(BlitzTheme.Typography.title)
                .multilineTextAlignment(.center)
            if let blurb = controller.currentSection?.blurb {
                Text(blurb)
                    .font(BlitzTheme.Typography.body)
                    .foregroundStyle(BlitzTheme.Palette.inkSecondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Button("Start this section") { controller.startSection() }
                .buttonStyle(.borderedProminent)
                .tint(BlitzTheme.Palette.velocity)
                .frame(minHeight: BlitzTheme.Layout.minimumTarget)
            Button("Leave the test") { controller.leaveTest() }
                .font(BlitzTheme.Typography.caption)
                .frame(minHeight: BlitzTheme.Layout.minimumTarget)
        }
        .padding(BlitzTheme.Layout.gutter)
    }

    // MARK: Question surface

    private var questionSurface: some View {
        VStack(spacing: BlitzTheme.Layout.stackGap) {
            header

            Spacer(minLength: 0)

            if let question = controller.currentQuestion {
                Text(question.prompt)
                    .font(question.presentation == .prose
                          ? BlitzTheme.Typography.questionCompact
                          : BlitzTheme.Typography.question)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(BlitzTheme.Palette.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .background(
                        RoundedRectangle(cornerRadius: BlitzTheme.Layout.cardRadius)
                            .fill(BlitzTheme.Palette.surface)
                            .stroke(BlitzTheme.Palette.rule, lineWidth: 1.5)
                    )
                    .accessibilityLabel(question.prompt)
            }

            Spacer(minLength: 0)

            // No hint button here (FR-PLC-011). The skip is the escape hatch.
            AnswerPad(question: controller.currentQuestion,
                      isEnabled: controller.phase == .running,
                      showedMistake: false,
                      onSubmit: { controller.submit($0) },
                      onHint: { controller.skipQuestion() })

            Button("I have not learned this yet") { controller.skipQuestion() }
                .font(BlitzTheme.Typography.caption)
                .frame(minHeight: BlitzTheme.Layout.minimumTarget)
        }
        .padding(BlitzTheme.Layout.gutter)
        .overlay(alignment: .top) { pausedBanner }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(controller.sectionPositionText)
                    .font(BlitzTheme.Typography.caption)
                    .foregroundStyle(BlitzTheme.Palette.inkSecondary)
                Text(controller.currentSection?.title ?? "")
                    .font(BlitzTheme.Typography.body)
                    .foregroundStyle(BlitzTheme.Palette.ink)
            }
            Spacer()
            // Position, never a countdown and never a failure state (FR-PLC-008).
            Text(controller.questionPositionText)
                .font(BlitzTheme.Typography.timer)
                .foregroundStyle(BlitzTheme.Palette.inkSecondary)
                .accessibilityLabel("Question \(controller.questionPositionText)")
        }
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

    // MARK: Between sections

    private var sectionComplete: some View {
        VStack(spacing: BlitzTheme.Layout.stackGap) {
            Spacer()
            Text("Section done")
                .font(BlitzTheme.Typography.title)
            Text(controller.isLastSection
                 ? "That is all of them."
                 : "Next up, \(controller.sections[min(controller.sectionIndex + 1, controller.sections.count - 1)].title.lowercased()).")
                .font(BlitzTheme.Typography.body)
                .foregroundStyle(BlitzTheme.Palette.inkSecondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button(controller.isLastSection ? "See where I am starting" : "Keep going") {
                controller.continueToNextSection()
            }
            .buttonStyle(.borderedProminent)
            .tint(BlitzTheme.Palette.velocity)
            .frame(minHeight: BlitzTheme.Layout.minimumTarget)
        }
        .padding(BlitzTheme.Layout.gutter)
    }

    private var leftEarly: some View {
        ContentUnavailableView {
            Label("Test not finished", systemImage: "arrow.uturn.left")
        } description: {
            Text("Nothing was changed. You can take it again any time, or start at the beginning.")
        } actions: {
            Button("Back") { onFinished() }
        }
    }

    private func unavailable(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Placement is unavailable", systemImage: "questionmark.square.dashed")
        } description: {
            Text(message)
        } actions: {
            Button("Start at the beginning") { onFinished() }
        }
    }
}

// MARK: - Result

/// No score, no percentage, no pass and fail language (FR-PLA-014).
struct PlacementResultView: View {

    let controller: PlacementController
    let onDone: () -> Void

    @State private var accepted = false

    var body: some View {
        ScrollView {
            VStack(spacing: BlitzTheme.Layout.stackGap) {
                Text("You are starting at")
                    .font(BlitzTheme.Typography.caption)
                    .foregroundStyle(BlitzTheme.Palette.inkSecondary)

                Text("World \(controller.result?.entryLevelID ?? "A")")
                    .font(.system(size: 52, weight: .semibold, design: .rounded))
                    .foregroundStyle(BlitzTheme.Palette.velocity)

                Text(controller.entryLevelName)
                    .font(BlitzTheme.Typography.title)
                    .multilineTextAlignment(.center)

                Text(controller.explanation)
                    .font(BlitzTheme.Typography.body)
                    .foregroundStyle(BlitzTheme.Palette.inkSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BlitzTheme.Layout.tightGap)

                bandTable

                VStack(spacing: BlitzTheme.Layout.tightGap) {
                    Button("Open my map") {
                        controller.acceptPlacement()
                        accepted = true
                        onDone()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BlitzTheme.Palette.velocity)
                    .frame(maxWidth: .infinity, minHeight: BlitzTheme.Layout.minimumTarget)

                    // FR-PLA-012. Always available, never buried.
                    Button("Start at World A instead") {
                        controller.startFromLevelAInstead()
                        accepted = true
                        onDone()
                    }
                    .frame(maxWidth: .infinity, minHeight: BlitzTheme.Layout.minimumTarget)
                }
                .padding(.top, BlitzTheme.Layout.tightGap)

                if controller.saveFailed {
                    Text("Your starting point could not be saved. Try opening the map again.")
                        .font(BlitzTheme.Typography.caption)
                        .foregroundStyle(BlitzTheme.Palette.overTarget)
                }
            }
            .padding(BlitzTheme.Layout.gutter)
        }
    }

    /// Verdicts in words, with time per section. No numbers that read as a grade.
    private var bandTable: some View {
        VStack(alignment: .leading, spacing: BlitzTheme.Layout.tightGap) {
            ForEach(controller.result?.bandSummaries ?? []) { summary in
                HStack {
                    Text("World \(summary.band)")
                        .font(BlitzTheme.Typography.body)
                        .foregroundStyle(BlitzTheme.Palette.ink)
                    Spacer()
                    Text(summary.verdict.displayName)
                        .font(BlitzTheme.Typography.caption)
                        .foregroundStyle(summary.verdict == .mastered
                                         ? BlitzTheme.Palette.correct
                                         : BlitzTheme.Palette.inkSecondary)
                }
                .accessibilityElement(children: .combine)
                Divider().background(BlitzTheme.Palette.rule)
            }
        }
        .padding(BlitzTheme.Layout.gutter)
        .background(
            RoundedRectangle(cornerRadius: BlitzTheme.Layout.cardRadius)
                .fill(BlitzTheme.Palette.surface)
                .stroke(BlitzTheme.Palette.rule, lineWidth: 1)
        )
    }
}

// MARK: - Previews

#Preview("Onboarding choice") {
    OnboardingChoiceView(onTakeTest: {}, onStartAtBeginning: {})
}
