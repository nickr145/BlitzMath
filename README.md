# BlitzMath

Offline-first, gamified iOS math app. SwiftUI presentation, SwiftData persistence, curriculum bundled as static JSON. No network code anywhere in the target.

The full specification is in [`docs/SRS.md`](docs/SRS.md), with the first-run placement test in [`docs/SRS-Addendum-01-Placement.md`](docs/SRS-Addendum-01-Placement.md). Source comments reference its requirement IDs, so `FR-MED-001` in a comment resolves to a line in the spec.

## File map

```
docs/SRS.md                                  Software Requirements Specification
docs/SRS-Addendum-01-Placement.md            Addendum 01, first-run placement test
BlitzMath/
├── App/BlitzMathApp.swift                   Entry point, composition root, haptics, recovery screen
├── Resources/curriculum.json                Bundled curriculum, Levels A to F, 24 modules
├── Resources/placement.json                 Placement test, 4 sections, 35 questions
├── Curriculum/
│   ├── CurriculumSchema.swift               Codable payload types, schema v1.1
│   └── CurriculumRepository.swift           Bundle load, validation, constant-time lookup
├── Domain/                                  Pure logic. No SwiftUI, no SwiftData imports.
│   ├── MedalEvaluator.swift                 Medal tiers and the award function
│   ├── ProgressionGate.swift                Milestone Gate evaluation and lock states
│   ├── BlitzClock.swift                     Monotonic clock with pause and resume
│   └── QuestionFactory.swift                Seeded generators for all 21 generator kinds
├── Placement/
│   ├── PlacementSchema.swift                Placement payload types, repository, validator
│   └── PlacementScorer.swift                Band verdicts and entry-level decision
├── Persistence/
│   ├── PlayerModels.swift                   SwiftData models, schema, migration plan, container
│   └── ProgressStore.swift                  The only component that touches a ModelContext
├── Features/
│   ├── Placement/
│   │   ├── PlacementController.swift        Section runner, per-question timing, scoring handoff
│   │   └── PlacementView.swift              Onboarding choice, sections, result screen
│   ├── WorldMap/WorldMapView.swift          Skill tree, lock states, module rows
│   └── LevelPlay/
│       ├── LevelSessionController.swift     Session state machine, plus preview doubles
│       └── LevelSessionView.swift           Timer ring, question surface, answer pad, summary
└── DesignSystem/BlitzTheme.swift            Colour, type, spacing, motion tokens, vector shapes
BlitzMathTests/DomainTests.swift             Suites traced to SRS acceptance criteria
BlitzMathTests/PlacementTests.swift          Suites traced to Addendum 01 acceptance criteria
```

## Assembling the Xcode project

The project is generated from `project.yml`, so there is no `.xcodeproj` in version control and no manual file dragging.

```bash
brew install xcodegen
cd BlitzMath
xcodegen generate            # writes BlitzMath.xcodeproj
open BlitzMath.xcodeproj
```

Build and test without opening Xcode:

```bash
xcodebuild -project BlitzMath.xcodeproj -scheme BlitzMath \
  -destination 'platform=iOS Simulator,name=iPhone 15' build

xcodebuild -project BlitzMath.xcodeproj -scheme BlitzMath \
  -destination 'platform=iOS Simulator,name=iPhone 15' test
```

Re-run `xcodegen generate` after adding a file. Everything the manifest covers - target membership, the iOS 17 deployment target, `curriculum.json` in Copy Bundle Resources, the test target, and the payload validation build phase - is declared there rather than clicked through the UI.

Requirements: Xcode 16 or later, since the test suites use Swift Testing.

### Payload validation

`scripts/validate-curriculum.py` enforces the DV rules from the SRS and runs as a pre-build phase, so a malformed payload fails the build rather than the app. It emits Xcode-formatted diagnostics, so errors land in the issue navigator. Run it directly at any time:

```bash
python3 scripts/validate-curriculum.py \
  BlitzMath/Resources/curriculum.json \
  BlitzMath/Domain/QuestionFactory.swift \
  BlitzMath/Resources/placement.json
```

It checks both payloads. PV-06 in particular catches a placement band sampled below its own `minimum_questions`, which would otherwise silently cap every placement at that band's level.

## Where to change things

| Change | File |
| --- | --- |
| Add a module or retune an SCT | `Resources/curriculum.json` only. No Swift change. |
| Retune placement difficulty or pace | `Resources/placement.json` only. Band rules and section composition both live there. |
| Add a new question type | `QuestionFactory.swift`, one `case` plus one entry in `supportedKinds`. |
| Change medal rules | `MedalEvaluator.swift`. Pure function, fully unit-testable. |
| Change unlock thresholds | `unlock_requirement` in the payload. The gate reads it, nothing is hard-coded. |
| Restyle | `BlitzTheme.swift`. Views pull tokens and never define colours at the call site. |

## Design direction

The visual heritage of this curriculum is a printed worksheet, so the surface is paper with a faint grid rule and ink-dark numerals. Boldness is spent in one place, the SCT ring, which is the only element that changes colour under pressure. Pace and lock states are always carried by text and shape as well as colour, and the single piece of non-user-triggered motion in the app is the medal reveal on the summary sheet.

## What is deliberately absent

No `URLSession`, no analytics, no third-party dependency, no CloudKit, no raster curriculum art. Verified against the payload: 6 levels, 24 modules, one entry point, all 21 generator kinds bound to an implementation.
