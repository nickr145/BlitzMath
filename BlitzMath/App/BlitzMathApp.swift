//
//  BlitzMathApp.swift
//  BlitzMath
//
//  Entry point and composition root. Curriculum load happens before the first
//  frame that depends on it (SRS FR-CUR-001). A payload that cannot be read
//  traps in Debug and shows a recovery screen in Release (FR-CUR-007, 008).
//

import SwiftUI
import SwiftData
import UIKit

@main
struct BlitzMathApp: App {

    private let container: ModelContainer
    private let curriculumResult: Result<CurriculumRepository, Error>
    private let placement: PlacementRepository?

    init() {
        do {
            container = try BlitzModelContainer.make()
        } catch {
            fatalError("The local store could not be opened: \(error)")
        }

        do {
            curriculumResult = .success(try CurriculumRepository())
        } catch {
            #if DEBUG
            fatalError("curriculum.json failed to load: \(error)")
            #else
            curriculumResult = .failure(error)
            #endif
        }

        // A missing or broken placement payload is not fatal. The onboarding
        // choice simply drops to starting at the beginning (Addendum FR-ONB-004).
        do {
            placement = try PlacementRepository()
        } catch {
            #if DEBUG
            fatalError("placement.json failed to load: \(error)")
            #else
            placement = nil
            #endif
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(curriculumResult: curriculumResult, placement: placement)
                .modelContainer(container)
                .tint(BlitzTheme.Palette.velocity)
        }
    }
}

// MARK: - Root

struct RootView: View {

    let curriculumResult: Result<CurriculumRepository, Error>
    let placement: PlacementRepository?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    /// The progress check resolves before either screen draws (FR-ONB-008).
    private enum Route: Equatable { case checking, onboarding, placement, map }
    @State private var route: Route = .checking

    var body: some View {
        switch curriculumResult {
        case .success(let curriculum):
            let store = ProgressStore(context: modelContext)
            content(curriculum: curriculum, store: store)
                .task { await resolveRoute(store: store) }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { try? touchProfile(store: store) }
                }

        case .failure:
            CurriculumRecoveryView()
        }
    }

    @ViewBuilder
    private func content(curriculum: CurriculumRepository, store: ProgressStore) -> some View {
        switch route {
        case .checking:
            // Neutral surface, no flash of the map behind onboarding.
            GraphPaperGrid().ignoresSafeArea()

        case .onboarding:
            OnboardingChoiceView(
                onTakeTest: { route = placement == nil ? .map : .placement },
                onStartAtBeginning: {
                    try? store.openLevelA(in: curriculum.payload.orderedLevels)
                    route = .map
                }
            )

        case .placement:
            if let placement {
                PlacementView(
                    controller: PlacementController(placement: placement,
                                                    curriculum: curriculum,
                                                    store: store,
                                                    feedback: HapticFeedback()),
                    onFinished: { route = .map }
                )
            } else {
                OnboardingChoiceView(onTakeTest: {}, onStartAtBeginning: { route = .map })
            }

        case .map:
            WorldMapView(
                model: WorldMapViewModel(curriculum: curriculum, store: store),
                makeSessionController: {
                    LevelSessionController(curriculum: curriculum,
                                           store: store,
                                           feedback: HapticFeedback())
                }
            )
        }
    }

    /// FR-ONB-001 to FR-ONB-003.
    private func resolveRoute(store: ProgressStore) async {
        guard route == .checking else { return }
        let hasProgress = (try? store.hasAnyProgress()) ?? true
        route = hasProgress ? .map : .onboarding
    }

    private func touchProfile(store: ProgressStore) throws {
        try store.profile().lastActiveAt = Date()
    }
}

// MARK: - Recovery

struct CurriculumRecoveryView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Lessons could not be read", systemImage: "doc.questionmark")
        } description: {
            Text("Reinstall BlitzMath from the App Store to restore the lessons. Your medals stay on this device.")
        }
        .background(GraphPaperGrid().ignoresSafeArea())
    }
}

// MARK: - Haptics

/// The only UIKit dependency in the app (SRS CN-06, NFR-POR-001).
struct HapticFeedback: SessionFeedbackDelivering {

    func correctAnswer() {
        Task { @MainActor in
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    func incorrectAnswer() {
        Task { @MainActor in
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    func medalAwarded(_ medal: MedalTier) {
        Task { @MainActor in
            let style: UIImpactFeedbackGenerator.FeedbackStyle = medal == .gold ? .heavy : .medium
            UIImpactFeedbackGenerator(style: style).impactOccurred()
        }
    }
}
