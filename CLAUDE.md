# CLAUDE.md

Guidance for Claude Code working in this repository.

## What this is

BlitzMath, an offline-first gamified iOS math app. SwiftUI presentation, SwiftData persistence, curriculum bundled as static JSON. Levels A to F, modelled on the Kumon progression, with a Standard Completion Time (SCT) per module and a medal-gated skill tree.

## Spec first

`docs/SRS.md` and `docs/SRS-Addendum-01-Placement.md` are the source of truth. Requirements are atomic and numbered (`FR-MED-001`, `FR-PLA-007`, `DV-04`). Source comments cite these IDs.

- Before changing behaviour, read the relevant requirement. If the code and the spec disagree, that is a bug in one of them. Say which, do not silently pick.
- When you add behaviour that is not in the spec, add the requirement to the spec in the same change, with an ID, a priority, and a verification method.
- Do not renumber existing requirement IDs. They are referenced from code comments and the traceability matrix.

## Hard constraints, do not violate

- **No networking.** No `URLSession`, no `Network.framework`, no networking dependency in the shipping target. The app must work fully in Airplane Mode. This is CN-01 and FR-OFF-003.
- **No third-party dependencies** in the shipping target. Test-only dependencies need a written reason.
- **Domain layer stays pure.** Files under `BlitzMath/Domain/` and `BlitzMath/Placement/PlacementScorer.swift` must not import SwiftUI or SwiftData. They are unit-testable in isolation. This is CN-06.
- **Only `ProgressStore` touches `ModelContext`.** Views and controllers never fetch or save directly.
- **No raster assets for curriculum art.** Text and vector `Shape` only, CN-03.
- **Colours, fonts, spacing, and motion come from `BlitzTheme`.** Never hard-code them at a call site.
- **No `localStorage`-style shortcuts around SwiftData**, and no CloudKit. The store is local only.
- Force unwrapping is prohibited outside test targets.

## Layer rule

```
Presentation  →  Control  →  Domain  →  Data Access  →  Storage
```

A component may depend on its own layer or a lower one, never upward.

| Layer | Location |
| --- | --- |
| Presentation | `BlitzMath/Features/**/*View.swift`, `BlitzMath/App/`, `BlitzMath/DesignSystem/` |
| Control | `BlitzMath/Features/**/*Controller.swift` |
| Domain | `BlitzMath/Domain/`, `BlitzMath/Placement/PlacementScorer.swift` |
| Data Access | `BlitzMath/Curriculum/`, `BlitzMath/Placement/PlacementSchema.swift`, `BlitzMath/Persistence/ProgressStore.swift` |
| Storage | `BlitzMath/Persistence/PlayerModels.swift`, `BlitzMath/Resources/*.json` |

## Commands

```bash
xcodegen generate                                  # regenerate BlitzMath.xcodeproj after adding files
xcodebuild -project BlitzMath.xcodeproj -scheme BlitzMath \
  -destination 'platform=iOS Simulator,name=iPhone 15' build
xcodebuild -project BlitzMath.xcodeproj -scheme BlitzMath \
  -destination 'platform=iOS Simulator,name=iPhone 15' test
python3 scripts/validate-curriculum.py \
  BlitzMath/Resources/curriculum.json \
  BlitzMath/Domain/QuestionFactory.swift \
  BlitzMath/Resources/placement.json
```

The `.xcodeproj` is generated and gitignored. `project.yml` is the source of truth for targets, build settings, and build phases. Never hand-edit a `.xcodeproj`.

Run the validator after any change to either JSON payload or to `QuestionFactory.supportedKinds`. It also runs as a pre-build phase.

## Content changes need no Swift

- Adding a module or retuning an SCT: `Resources/curriculum.json` only.
- Retuning placement difficulty, pace targets, or band thresholds: `Resources/placement.json` only.
- Adding a question type: one `case` in `QuestionFactory` plus one entry in `supportedKinds`. Nothing else.

If a content change seems to require a Swift change, that is a signal the schema is wrong. Raise it before hard-coding.

## Testing

Swift Testing, not XCTest. Suites map to acceptance criteria (`AC-02`, `AC-A04`). When you change domain logic, update or add the suite that covers its requirement in the same change. Domain coverage target is 90 percent.

Test doubles already exist and should be reused rather than re-invented: `MockCurriculumProvider`, `MockPlacementProvider`, `MockProgressStore`, `ManualTimeSource`.

## Commit Rules

When making commits messages, do not mention anything under co-authored or what claude session it was. Simply describe what the commit is about.

## Invariants that are easy to break

- Medals are monotonic. A weaker later result never overwrites a stronger one.
- An unlocked level never returns to locked, including after a curriculum change.
- Placement opens levels but awards no medals, so gates above the entry level still require earned medals.
- Session timing uses the monotonic clock only. Wall clock is recorded for history and never for measurement.
- A placement band sampled below its own `minimum_questions` can never be mastered, which silently caps every placement at that band's level. The validator raises PV-06 for this.

## Writing style for docs and user-facing strings

Short, direct sentences. No em dashes. Canadian spellings in prose. No pass and fail language anywhere in the placement flow, and no score or percentage on the result screen (FR-PLA-014). Player-facing copy is written for a 6 to 13 year old reader.

## Current state

Skeleton is complete and internally consistent but has never been compiled, since it was authored outside Xcode. Expect first-build fixes: SwiftData macro details, `@Observable` and `@State` interactions, and the `String: Identifiable` retroactive conformance in `WorldMapView.swift`, which may be better replaced with a small wrapper type.
