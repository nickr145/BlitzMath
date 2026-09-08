# Software Requirements Specification
## BlitzMath (project identifier: `blitzmath`)

| Field | Value |
| --- | --- |
| Document ID | BLZ-SRS-001 |
| Version | 1.0.0 |
| Status | Baselined for implementation |
| Date | 2026-09-07 |
| Author | N. Rebello |
| Standard | Structured after ISO/IEC/IEEE 29148:2018, clause 9.5 |
| Target release | BlitzMath 1.0.0 (iOS, App Store binary) |

---

## 1. Introduction

### 1.1 Purpose

This document specifies the complete functional and non-functional requirements for BlitzMath 1.0.0, an offline-first, gamified iOS mathematics application. It is written for the implementing engineer, the curriculum author who maintains `curriculum.json`, and the reviewer who verifies the build before submission.

The specification is granular by design. Every requirement is atomic, uniquely identified, individually verifiable, and traced to a component in section 12.

### 1.2 Scope

BlitzMath converts a paper-based, incremental mathematics progression modelled on the Kumon Learning Method (foundational Levels A through F) into interactive mobile Worlds. Each World holds an ordered set of Modules. Each Module is a timed drill measured against a Standard Completion Time (SCT). Performance against the SCT awards a Medal, and accumulated Medals unlock later Worlds.

In scope for 1.0.0:

- Local curriculum ingestion from a bundled static JSON payload.
- Timed drill sessions with immediate answer validation.
- Medal award, local persistence of player state, and Milestone Gate evaluation.
- Skill tree navigation across Levels A through F.
- Full functionality with the device in Airplane Mode.

Explicitly out of scope for 1.0.0:

- Any network request, remote configuration, telemetry upload, or account system.
- CloudKit synchronisation, multi-device state, leaderboards, and social features.
- In-app purchases and advertising.
- Handwriting recognition and pencil input.
- Localisation beyond en-CA.

### 1.3 Definitions, acronyms, and abbreviations

| Term | Definition |
| --- | --- |
| Level | A curriculum tier identified by a single letter, A through F. Presented to the player as a World. |
| Module | The smallest playable unit inside a Level, identified as `<LEVEL>_<NN>`, for example `E_02`. |
| SCT | Standard Completion Time. The target duration in seconds for a flawless run of a Module. |
| Blitz Engine | The timing, scoring, and medal subsystem that governs a session. |
| Session | One attempt at one Module, from first question presentation to summary or abandonment. |
| Medal | The award tier granted at session end. One of Gold, Silver, Bronze, or None. |
| Qualifying Medal | A Gold or Silver Medal. Only these count toward Milestone Gates. |
| Milestone Gate | The rule that locks a Level until a Medal threshold on the preceding Level is met. |
| Flawless | A session in which no incorrect answer was submitted and no hint was consumed. |
| Curriculum Payload | The bundled `curriculum.json` file and its decoded in-memory representation. |
| Player State | All locally persisted data describing one player's progress. |
| Monotonic clock | A time source unaffected by wall-clock adjustment, used for all session timing. |

### 1.4 References

| Ref | Document |
| --- | --- |
| R1 | Project Identity and Architectural Brief, BlitzMath, 2026-09-07 (the originating brief) |
| R2 | Apple SwiftData Framework Documentation, iOS 17+ |
| R3 | Apple Human Interface Guidelines, Games and Accessibility chapters |
| R4 | WCAG 2.2 Level AA, applied to native mobile UI where transferable |
| R5 | `curriculum.json` schema definition, section 4 of this document |

### 1.5 Document conventions

- **Shall** denotes a mandatory requirement. Absence blocks release.
- **Should** denotes a recommended requirement. Absence requires a written waiver.
- **May** denotes an optional capability.
- Priority: P1 blocks release, P2 is required for feature completeness, P3 is deferrable to 1.1.
- Verification method: **T** test, **D** demonstration, **I** inspection, **A** analysis.

---

## 2. Overall description

### 2.1 Product perspective

BlitzMath is a self-contained iOS client with no server component. The application binary is the sole distribution channel for curriculum content. Content corrections, SCT retuning, and new Modules ship as App Store binary iterations. This constraint is deliberate and drives the architecture: there is no remote configuration path, no feature flag service, and no fallback network route to disable.

The system decomposes into five layers with a strict downward dependency rule.

```
┌──────────────────────────────────────────────────────────┐
│ Presentation      SwiftUI views, vector shape canvases   │
├──────────────────────────────────────────────────────────┤
│ Control           Observable session controllers          │
├──────────────────────────────────────────────────────────┤
│ Domain            Blitz Engine, medal rules, gate rules   │
├──────────────────────────────────────────────────────────┤
│ Data Access       Curriculum repository, progress store   │
├──────────────────────────────────────────────────────────┤
│ Storage           App bundle JSON, SwiftData container    │
└──────────────────────────────────────────────────────────┘
```

### 2.2 Product functions

| Ref | Function |
| --- | --- |
| PF-1 | Load and validate the bundled curriculum at launch. |
| PF-2 | Render a skill tree of Levels A through F with locked and unlocked states. |
| PF-3 | Run a timed Module session with per-question validation and haptic feedback. |
| PF-4 | Evaluate performance against the SCT and award a Medal. |
| PF-5 | Persist player state, session history, and best results locally. |
| PF-6 | Evaluate Milestone Gates and unlock Levels when thresholds are met. |
| PF-7 | Present a session summary with time, accuracy, Medal, and personal best delta. |
| PF-8 | Operate with full function while the device has no network connectivity. |

### 2.3 User classes and characteristics

| Class | Description | Implications |
| --- | --- | --- |
| Primary learner | Age 6 to 13, variable reading fluency, uses the app in short sessions. | Large tap targets, minimal text, numeric input over prose, no destructive actions without confirmation. |
| Supervising adult | Parent or tutor reviewing progress. | Read-only progress view, plain summary of Medal counts and times. |
| Curriculum author | Internal, edits `curriculum.json` between releases. | Schema must be human-editable, validated at build time, and fail loudly on malformed input. |

### 2.4 Operating environment

| Item | Requirement |
| --- | --- |
| OS | iOS 17.0 and later. |
| Devices | iPhone SE (2nd generation) and later, all iPad models supporting iOS 17. |
| Orientation | Portrait on iPhone. Portrait and landscape on iPad. |
| UI framework | SwiftUI only. UIKit permitted solely for haptic engine bridging. |
| Persistence | SwiftData, local store only. |
| Network | None. The application shall not link any networking symbol used at runtime. |
| Storage budget | Application bundle under 60 MB. Player store under 5 MB after 12 months of daily use. |

### 2.5 Design and implementation constraints

| ID | Constraint |
| --- | --- |
| CN-01 | No `URLSession`, `Network.framework`, or third-party networking dependency shall appear in the shipping target. |
| CN-02 | The curriculum shall reside in the application bundle as static JSON. No writes to the bundle at runtime. |
| CN-03 | Visual content shall be text and vector shapes. No raster assets for curriculum artwork. |
| CN-04 | All timing shall use a monotonic clock. Wall-clock time is recorded for history only. |
| CN-05 | Third-party dependencies are prohibited in the shipping target. Test-only dependencies require written approval. |
| CN-06 | The Domain layer shall contain no import of SwiftUI or SwiftData, so that medal and gate rules remain unit-testable in isolation. |
| CN-07 | No analytics, tracking identifier, or crash reporter that transmits off device. |

### 2.6 Assumptions and dependencies

| ID | Statement |
| --- | --- |
| AS-01 | The bundled curriculum is authored correctly and passes schema validation during the build. |
| AS-02 | A single player profile per device installation is sufficient for 1.0.0. Multi-profile support is deferred. |
| AS-03 | Question content for 1.0.0 is produced by deterministic on-device generators bound to each Module, seeded per session, rather than by an exhaustive question bank in JSON. This keeps the bundle small and the drill re-playable. |
| AS-04 | Device haptics may be unavailable on some hardware. All haptic feedback is supplementary and never the sole channel for information. |

---

## 3. System architecture

### 3.1 Component inventory

| ID | Component | Layer | Responsibility |
| --- | --- | --- | --- |
| CMP-01 | `BlitzMathApp` | Presentation | Application entry point, container injection, scene phase handling. |
| CMP-02 | `RootView`, `WorldMapView` | Presentation | Skill tree rendering, lock state display, Module entry. |
| CMP-03 | `LevelSessionView` | Presentation | Active drill surface, timer ring, answer pad, summary sheet. |
| CMP-04 | `LevelSessionController` | Control | Session state machine, question sequencing, scoring, persistence handoff. |
| CMP-05 | `BlitzClock` | Domain | Monotonic elapsed time with pause and resume. |
| CMP-06 | `MedalEvaluator` | Domain | Pure medal award function. |
| CMP-07 | `ProgressionGate` | Domain | Pure Milestone Gate evaluation. |
| CMP-08 | `QuestionFactory` | Domain | Deterministic seeded question generation per Module generator kind. |
| CMP-09 | `CurriculumRepository` | Data Access | Bundle load, decode, validate, cache, query. |
| CMP-10 | `ProgressStore` | Data Access | SwiftData reads and writes, medal aggregation, unlock queries. |
| CMP-11 | SwiftData models | Storage | `PlayerProfile`, `LevelProgressRecord`, `ModuleProgressRecord`, `SessionRecord`. |
| CMP-12 | `BlitzTheme` | Presentation | Colour, type, and motion tokens. |

### 3.2 Dependency rule

A component shall depend only on components in its own layer or a lower layer. Presentation shall never reference SwiftData model types directly except through `ProgressStore` view models. Domain shall depend on nothing but the Swift standard library and Foundation.

### 3.3 Session data flow

```
WorldMapView
   │ selects moduleID
   ▼
LevelSessionController.start(moduleID:)
   │ 1. CurriculumRepository.module(id:)      → CurriculumModule (name, SCT, generator)
   │ 2. QuestionFactory.build(module:seed:)   → [Question]
   │ 3. BlitzClock.start()                    → elapsed stream at 10 Hz
   ▼
LevelSessionView renders question n, receives answer
   │ 4. controller.submit(answer:)            → correct / incorrect, haptic
   ▼ (last question answered)
   │ 5. BlitzClock.stop()                     → final elapsed
   │ 6. MedalEvaluator.award(...)             → MedalTier
   │ 7. ProgressStore.record(result:)         → SessionRecord + ModuleProgressRecord upsert
   │ 8. ProgressionGate.evaluate(...)         → newly unlocked Levels
   ▼
SessionSummary presented, skill tree invalidated
```

---

## 4. Data requirements

### 4.1 Curriculum payload schema, version 1.1

The payload is a single UTF-8 encoded file, `curriculum.json`, located in the application bundle Resources group. Version 1.1 is a strict superset of the 1.0.0 payload given in the originating brief. Every field added in 1.1 is optional and carries a documented default, so a 1.0.0 payload decodes without modification.

#### 4.1.1 Root object

| Field | Type | Required | Default | Rule |
| --- | --- | --- | --- | --- |
| `app_name` | String | Yes | none | Informational. Shall equal `BlitzMath`. |
| `version` | String | Yes | none | Semantic version of the payload, not the app. |
| `schema_version` | String | No | `1.0` | Consumed by the decoder to select validation rules. |
| `curriculum` | Array\<Level\> | Yes | none | Minimum 1 element. Order in the array is not authoritative. |

#### 4.1.2 Level object

| Field | Type | Required | Default | Rule |
| --- | --- | --- | --- | --- |
| `level_id` | String | Yes | none | Single uppercase letter, A to F. Unique across the payload. |
| `level_name` | String | Yes | none | 1 to 48 characters, display text. |
| `level_order` | Int | No | derived from `level_id` alphabetically | Ascending, starting at 1, unique. |
| `unlock_requirement` | UnlockRequirement | No | `null` | `null` means the Level is unlocked from first launch. |
| `modules` | Array\<Module\> | Yes | none | Minimum 1 element, maximum 24. |

#### 4.1.3 UnlockRequirement object

| Field | Type | Required | Default | Rule |
| --- | --- | --- | --- | --- |
| `source_level_id` | String | Yes | none | Shall reference an existing `level_id` with a lower `level_order`. |
| `required_medal_count` | Int | Yes | none | 0 to the Module count of the source Level. Counts Qualifying Medals. |
| `required_gold_count` | Int | No | `0` | Subset requirement. Shall not exceed `required_medal_count`. |

#### 4.1.4 Module object

| Field | Type | Required | Default | Rule |
| --- | --- | --- | --- | --- |
| `id` | String | Yes | none | Matches `^[A-F]_[0-9]{2}$`. Globally unique. Prefix shall equal the parent `level_id`. |
| `name` | String | Yes | none | 1 to 64 characters. |
| `target_sct_seconds` | Int | Yes | none | 30 to 900 inclusive. |
| `question_count` | Int | No | `20` | 5 to 40 inclusive. |
| `generator` | Generator | No | inferred from `id` prefix | Binds the Module to a question generator. |

#### 4.1.5 Generator object

| Field | Type | Required | Default | Rule |
| --- | --- | --- | --- | --- |
| `kind` | String | Yes | none | One of the enumerated generator kinds in section 8.2. Unknown values fail validation. |
| `params` | Object\<String, Int\> | No | `{}` | Generator-specific bounds such as `min`, `max`, `max_denominator`. |

### 4.2 Payload validation rules

| ID | Rule | Failure behaviour |
| --- | --- | --- |
| DV-01 | The file shall exist in the bundle and decode as UTF-8 JSON. | Fatal at launch in Debug. Recovery screen in Release. |
| DV-02 | All `level_id` values shall be unique and drawn from A to F. | Validation error, Level rejected. |
| DV-03 | All Module `id` values shall be globally unique and prefix-matched to the parent Level. | Validation error, Module rejected. |
| DV-04 | `target_sct_seconds` shall fall inside 30 to 900. | Validation error, Module rejected. |
| DV-05 | Every `unlock_requirement.source_level_id` shall resolve to a Level of lower order. | Validation error, Level treated as permanently locked and reported. |
| DV-06 | `required_medal_count` shall not exceed the Module count of the source Level, otherwise the Gate is unsatisfiable. | Validation error, Level rejected. |
| DV-07 | Exactly one Level shall have a `null` unlock requirement, forming the entry point. | Validation error if zero. Warning if more than one. |
| DV-08 | Validation shall run as a build phase script against the bundled file, so that a malformed payload fails the build rather than the app. | Build failure with the offending path and field. |

### 4.3 Persistent entity specifications

All entities are SwiftData `@Model` classes in a single local `ModelContainer`. Enumerations are persisted as their `String` raw value and exposed through a computed property, so that adding a case does not force a store migration.

#### 4.3.1 `PlayerProfile`

| Attribute | Type | Constraint | Notes |
| --- | --- | --- | --- |
| `id` | UUID | Unique | Stable local identity. |
| `displayName` | String | 1 to 24 characters | Defaults to `Player`. |
| `createdAt` | Date | Non-null | Wall clock. |
| `lastActiveAt` | Date | Non-null | Updated on scene activation. |
| `currentStreakDays` | Int | >= 0 | Consecutive calendar days with at least one completed session. |
| `longestStreakDays` | Int | >= 0 | Monotonic high-water mark. |
| `reducedMotionOverride` | Bool | Non-null | Player-level override layered over the system setting. |
| `hapticsEnabled` | Bool | Non-null | Defaults to true. |
| `levelProgress` | Relationship, to-many `LevelProgressRecord` | Cascade delete | Inverse `profile`. |
| `sessions` | Relationship, to-many `SessionRecord` | Cascade delete | Inverse `profile`. |

#### 4.3.2 `LevelProgressRecord`

| Attribute | Type | Constraint | Notes |
| --- | --- | --- | --- |
| `levelID` | String | Unique per profile | A to F. |
| `stateRaw` | String | Non-null | `locked`, `unlocked`, `completed`. |
| `unlockedAt` | Date? | Nullable | Set on Gate satisfaction. |
| `completedAt` | Date? | Nullable | Set when every Module holds a Qualifying Medal. |
| `moduleProgress` | Relationship, to-many `ModuleProgressRecord` | Cascade delete | Inverse `level`. |

#### 4.3.3 `ModuleProgressRecord`

| Attribute | Type | Constraint | Notes |
| --- | --- | --- | --- |
| `moduleID` | String | Unique per profile | Matches curriculum Module id. |
| `levelID` | String | Non-null | Denormalised for gate aggregation without a join. |
| `bestMedalRaw` | String | Non-null | Highest Medal ever achieved. Never downgraded. |
| `bestTimeSeconds` | Double? | Nullable, > 0 | Fastest flawless completion. |
| `lastTimeSeconds` | Double? | Nullable, > 0 | Most recent completion. |
| `bestAccuracy` | Double | 0.0 to 1.0 | Highest accuracy achieved. |
| `attemptCount` | Int | >= 0 | Includes abandoned attempts. |
| `completionCount` | Int | >= 0 | Excludes abandoned attempts. |
| `firstCompletedAt` | Date? | Nullable | |
| `lastAttemptAt` | Date? | Nullable | |

#### 4.3.4 `SessionRecord`

| Attribute | Type | Constraint | Notes |
| --- | --- | --- | --- |
| `id` | UUID | Unique | |
| `moduleID` | String | Non-null | |
| `levelID` | String | Non-null | |
| `startedAt` | Date | Non-null | Wall clock, history only. |
| `endedAt` | Date? | Nullable | Null while a session is in flight. |
| `elapsedSeconds` | Double | >= 0 | Monotonic measurement, excludes paused intervals. |
| `questionCount` | Int | > 0 | |
| `correctFirstTryCount` | Int | >= 0 | Drives accuracy. |
| `incorrectAttemptCount` | Int | >= 0 | Total wrong submissions across all questions. |
| `hintsUsed` | Int | >= 0 | Non-zero disqualifies a Gold Medal. |
| `medalRaw` | String | Non-null | Medal awarded for this session. |
| `wasAbandoned` | Bool | Non-null | True if the session ended without answering every question. |
| `sctSecondsAtRun` | Int | > 0 | The SCT in force at run time, retained so history survives SCT retuning. |

### 4.4 Schema versioning and migration

| ID | Requirement |
| --- | --- |
| DM-01 | The store schema shall be declared through a versioned `SchemaMigrationPlan` from the first release, even though 1.0.0 has a single version. |
| DM-02 | Lightweight migration shall be used for additive changes. A custom migration stage is mandatory for any attribute rename or type change. |
| DM-03 | A Module removed from the curriculum shall leave its historical `ModuleProgressRecord` intact and hidden, never deleted. Progress is not destroyed by a content change. |
| DM-04 | A change to `target_sct_seconds` shall not retroactively alter Medals already awarded. Awards are immutable once written. |

### 4.5 Invariants

| ID | Invariant |
| --- | --- |
| IV-01 | `bestMedalRaw` is monotonic. A weaker result never overwrites a stronger one. |
| IV-02 | `bestTimeSeconds` is set only from flawless completions, so it is comparable across attempts. |
| IV-03 | `completionCount <= attemptCount` for every Module. |
| IV-04 | A Level in state `unlocked` or `completed` never returns to `locked`. |
| IV-05 | The sum of Qualifying Medals for a Level never exceeds that Level's Module count. |

---

## 5. Functional requirements

### 5.1 Curriculum ingestion, FR-CUR

| ID | Requirement | Priority | Verify |
| --- | --- | --- | --- |
| FR-CUR-001 | The system shall load `curriculum.json` from the application bundle during the launch sequence, before the first frame that depends on curriculum data. | P1 | T |
| FR-CUR-002 | The system shall decode the payload using snake_case to camelCase key conversion, with all 1.1 fields optional. | P1 | T |
| FR-CUR-003 | The system shall apply every validation rule in section 4.2 and produce a structured list of validation diagnostics. | P1 | T |
| FR-CUR-004 | The system shall cache the decoded curriculum in memory for the process lifetime and shall not re-read the file on view refresh. | P1 | A |
| FR-CUR-005 | The system shall expose lookup of a Level by `level_id` and a Module by `id` in constant time. | P2 | I |
| FR-CUR-006 | When validation rejects one or more Modules, the system shall continue to run with the valid remainder and shall record the diagnostics in a developer-visible diagnostics screen. | P2 | T |
| FR-CUR-007 | When the payload cannot be decoded at all, the Release build shall present a recovery screen stating that the content could not be read and inviting the player to reinstall. The app shall not crash. | P1 | T |
| FR-CUR-008 | The Debug build shall trap on an undecodable payload so that authoring errors surface immediately during development. | P2 | I |
| FR-CUR-009 | The system shall not write to, mutate, or attempt to update the bundled payload at runtime. | P1 | I |

### 5.2 Navigation and skill tree, FR-NAV

| ID | Requirement | Priority | Verify |
| --- | --- | --- | --- |
| FR-NAV-001 | The system shall present Levels A through F as an ordered skill tree ascending by `level_order`. | P1 | D |
| FR-NAV-002 | Each Level shall render its lock state as one of locked, unlocked, or completed, using shape and text and not colour alone. | P1 | D |
| FR-NAV-003 | A locked Level shall display its outstanding requirement in plain language, stating the count of Medals still needed and the source Level. | P1 | D |
| FR-NAV-004 | Selecting a locked Level shall not start a session and shall surface the same requirement text with a non-destructive feedback pattern. | P1 | T |
| FR-NAV-005 | Each Module row shall display its name, SCT expressed in minutes and seconds, and the best Medal held. | P1 | D |
| FR-NAV-006 | A Module with no attempt shall display an explicit empty state rather than a zeroed statistic. | P2 | D |
| FR-NAV-007 | The skill tree shall refresh its lock and Medal state whenever a session summary is dismissed, without an application restart. | P1 | T |
| FR-NAV-008 | Modules within a Level shall be playable in any order. Only Level entry is gated. | P2 | I |

### 5.3 Session lifecycle, FR-SES

| ID | Requirement | Priority | Verify |
| --- | --- | --- | --- |
| FR-SES-001 | The controller shall accept a Module identifier, resolve it through the curriculum repository, and reject an unknown identifier without starting a session. | P1 | T |
| FR-SES-002 | The controller shall build the question set before the clock starts, so that generation cost is never charged to the player's time. | P1 | T |
| FR-SES-003 | The session shall present exactly `question_count` questions, one at a time. | P1 | T |
| FR-SES-004 | The controller shall implement the state machine in section 10.1 and shall reject any transition not defined there. | P1 | T |
| FR-SES-005 | A correct answer shall advance to the next question, increment the correct counter when it is a first attempt, and fire a success haptic. | P1 | T |
| FR-SES-006 | An incorrect answer shall keep the current question active, increment `incorrectAttemptCount`, and fire a warning haptic. | P1 | T |
| FR-SES-007 | The system shall not impose a per-question time limit. Pressure is applied by the SCT alone. | P2 | I |
| FR-SES-008 | Moving the application to the background shall pause the session clock within one run loop cycle. | P1 | T |
| FR-SES-009 | Returning to the foreground shall present a resume prompt and shall not resume the clock automatically. | P1 | T |
| FR-SES-010 | A session abandoned by the player shall be written with `wasAbandoned` true and shall increment `attemptCount` without awarding a Medal. | P1 | T |
| FR-SES-011 | Termination of the process during a session shall leave no partial session in the store. Session records are written at completion, not incrementally. | P1 | T |
| FR-SES-012 | The controller shall expose progress as answered count over total count for display. | P2 | D |

### 5.4 Blitz Engine and timing, FR-BLZ

| ID | Requirement | Priority | Verify |
| --- | --- | --- | --- |
| FR-BLZ-001 | Elapsed time shall be measured with a monotonic clock and shall be immune to wall-clock changes, time zone changes, and daylight saving transitions. | P1 | T |
| FR-BLZ-002 | The timer display shall update at 10 Hz or faster while running and shall never drive a full view rebuild of the question surface. | P1 | A |
| FR-BLZ-003 | Paused intervals shall be excluded from `elapsedSeconds`. | P1 | T |
| FR-BLZ-004 | The system shall render SCT consumption as a vector progress ring bound to `elapsed / sct`, clamped to a maximum of 1.0. | P1 | D |
| FR-BLZ-005 | The ring shall change state at 0.75 and at 1.0 of the SCT, communicated through shape and numeric readout as well as colour. | P2 | D |
| FR-BLZ-006 | Crossing the SCT shall not end the session. The session continues and remains eligible for a Silver Medal. | P1 | T |
| FR-BLZ-007 | Elapsed time shall be recorded with millisecond resolution and displayed to one tenth of a second. | P2 | I |
| FR-BLZ-008 | The timer shall stop before the final answer is validated, so that validation latency is not charged to the player. | P1 | T |

### 5.5 Medal award, FR-MED

| ID | Requirement | Priority | Verify |
| --- | --- | --- | --- |
| FR-MED-001 | A Gold Medal shall be awarded when the session is completed, is flawless, and `elapsedSeconds <= target_sct_seconds`. | P1 | T |
| FR-MED-002 | A Silver Medal shall be awarded when the session is completed and flawless but `elapsedSeconds > target_sct_seconds`. | P1 | T |
| FR-MED-003 | A Bronze Medal shall be awarded when the session is completed with accuracy at or above 0.80 but the run was not flawless. Bronze is a completion marker and is not a Qualifying Medal. | P2 | T |
| FR-MED-004 | No Medal shall be awarded when accuracy falls below 0.80 or when the session was abandoned. | P1 | T |
| FR-MED-005 | Flawless shall be defined as `incorrectAttemptCount == 0 && hintsUsed == 0`. | P1 | I |
| FR-MED-006 | Accuracy shall be defined as `correctFirstTryCount / questionCount`. | P1 | I |
| FR-MED-007 | The medal evaluator shall be a pure function with no dependency on persistence, view state, or the system clock. | P1 | I |
| FR-MED-008 | A Medal already recorded shall never be downgraded by a later weaker session. | P1 | T |
| FR-MED-009 | The award shall be computed against the SCT in force at run time and that SCT shall be persisted with the session. | P1 | T |

### 5.6 Milestone Gate, FR-GATE

| ID | Requirement | Priority | Verify |
| --- | --- | --- | --- |
| FR-GATE-001 | A Level with a null unlock requirement shall be unlocked on first launch. | P1 | T |
| FR-GATE-002 | A Level shall be unlocked when the count of Qualifying Medals held on the source Level is at or above `required_medal_count` and the count of Gold Medals is at or above `required_gold_count`. | P1 | T |
| FR-GATE-003 | Gate evaluation shall query persisted player state, not in-memory session state, so that the check survives a restart. | P1 | T |
| FR-GATE-004 | Gate evaluation shall run after every session that awards a Qualifying Medal, and again on every cold launch. | P1 | T |
| FR-GATE-005 | Newly unlocked Levels shall be surfaced to the player in the session summary as a distinct unlock event. | P2 | D |
| FR-GATE-006 | An unlocked Level shall never revert to locked, including after a curriculum update that raises the threshold. | P1 | T |
| FR-GATE-007 | The gate evaluator shall be a pure function over a Medal count snapshot and the requirement. | P1 | I |

### 5.7 Persistence, FR-PER

| ID | Requirement | Priority | Verify |
| --- | --- | --- | --- |
| FR-PER-001 | The system shall create exactly one `PlayerProfile` on first launch and shall reuse it thereafter. | P1 | T |
| FR-PER-002 | The system shall write a `SessionRecord` and upsert the matching `ModuleProgressRecord` inside a single save operation. | P1 | T |
| FR-PER-003 | A failed save shall be surfaced to the player as a non-blocking notice and shall be retried once before the summary is dismissed. | P2 | T |
| FR-PER-004 | The store shall be configured as local only, with CloudKit explicitly disabled. | P1 | I |
| FR-PER-005 | All reads that drive the skill tree shall be served through fetch descriptors with predicates, not by loading and filtering the whole store in memory. | P2 | A |
| FR-PER-006 | The system shall provide a Reset Progress action, guarded by a confirmation that names the consequence, which deletes all player records and recreates an empty profile. | P2 | T |
| FR-PER-007 | Player data shall never leave the device. | P1 | I |

### 5.8 Feedback, motion, and haptics, FR-FBK

| ID | Requirement | Priority | Verify |
| --- | --- | --- | --- |
| FR-FBK-001 | Answer validation shall produce feedback within 100 ms of submission. | P1 | T |
| FR-FBK-002 | Haptic feedback shall be suppressed when `hapticsEnabled` is false or the device does not support the engine, with no other behavioural change. | P1 | T |
| FR-FBK-003 | Motion shall respect Reduce Motion, replacing transitions with cross-fades and disabling the medal award animation loop. | P1 | T |
| FR-FBK-004 | Correct and incorrect states shall be distinguishable without colour, using shape, position, and text. | P1 | D |
| FR-FBK-005 | Non-user-triggered motion shall be limited to a single orchestrated moment, the medal reveal on the summary screen. | P2 | I |

### 5.9 Accessibility, FR-ACC

| ID | Requirement | Priority | Verify |
| --- | --- | --- | --- |
| FR-ACC-001 | Every interactive element shall carry an accessibility label written in plain language for a young reader. | P1 | I |
| FR-ACC-002 | The layout shall remain usable from the smallest Dynamic Type size through AX3 without truncation of question text. | P1 | D |
| FR-ACC-003 | The timer ring shall expose its value to VoiceOver as remaining or elapsed seconds against the target, not as a raw fraction. | P2 | T |
| FR-ACC-004 | Tap targets shall be at least 44 by 44 points. | P1 | I |
| FR-ACC-005 | The application shall be operable with VoiceOver active for the full session flow. | P2 | D |

### 5.10 Offline guarantee, FR-OFF

| ID | Requirement | Priority | Verify |
| --- | --- | --- | --- |
| FR-OFF-001 | Every function in section 2.2 shall work with the device in Airplane Mode from a cold launch. | P1 | T |
| FR-OFF-002 | The application shall never present a connectivity error, retry prompt, or offline banner, because no code path requires connectivity. | P1 | T |
| FR-OFF-003 | The shipping target shall be verified free of runtime networking symbols by an automated inspection step in the release checklist. | P1 | I |

---

## 6. External interface requirements

### 6.1 User interfaces

| ID | Requirement |
| --- | --- |
| UI-01 | Screens: Skill Tree, Level Detail, Active Session, Session Summary, Progress Review, Settings. |
| UI-02 | The Active Session screen shall keep the question, the answer pad, and the timer ring simultaneously visible without scrolling on the smallest supported device. |
| UI-03 | Curriculum visuals shall be composed from SwiftUI `Shape` and `Path` primitives so that they scale without raster artefacts. |
| UI-04 | The numeric readout for time shall use monospaced digits so that the layout does not shift as digits change. |
| UI-05 | Colour, type, spacing, and motion shall be drawn from a single token file and shall not be hard-coded at call sites. |

### 6.2 Hardware interfaces

| ID | Requirement |
| --- | --- |
| HW-01 | Haptic engine, used for answer validation and medal award. Optional at runtime. |
| HW-02 | Touch input only. Keyboard input on iPad is optional and deferred to 1.1. |

### 6.3 Software interfaces

| ID | Requirement |
| --- | --- |
| SW-01 | SwiftUI for all presentation. |
| SW-02 | SwiftData for all persistence. |
| SW-03 | Foundation `JSONDecoder` for curriculum ingestion. |

### 6.4 Communication interfaces

None. This is a hard requirement, not an omission. See CN-01 and FR-OFF-003.

---

## 7. Non-functional requirements

### 7.1 Performance

| ID | Requirement | Budget | Verify |
| --- | --- | --- | --- |
| NFR-PRF-001 | Cold launch to interactive skill tree. | Under 800 ms on iPhone SE 2nd generation. | T |
| NFR-PRF-002 | Curriculum decode and validation. | Under 50 ms for a payload of 6 Levels and 24 Modules. | T |
| NFR-PRF-003 | Question set generation for one Module. | Under 20 ms. | T |
| NFR-PRF-004 | Answer submission to visible feedback. | Under 100 ms at the 95th percentile. | T |
| NFR-PRF-005 | Session save. | Under 150 ms, off the main actor where possible. | T |
| NFR-PRF-006 | Sustained frame rate during a session. | 60 fps minimum, 120 fps on ProMotion hardware. | A |
| NFR-PRF-007 | Memory footprint during a session. | Under 120 MB resident. | A |

### 7.2 Reliability

| ID | Requirement |
| --- | --- |
| NFR-REL-001 | No data loss on abrupt termination. At most the in-flight session is lost, and no partial record is written. |
| NFR-REL-002 | Crash-free session rate at or above 99.9 percent in internal testing. |
| NFR-REL-003 | Every failure path shall be handled by an explicit branch. Force unwrapping is prohibited outside test targets. |

### 7.3 Security and privacy

| ID | Requirement |
| --- | --- |
| NFR-SEC-001 | No personal data is collected. `displayName` is a local nickname with no validation against real identity. |
| NFR-SEC-002 | No data is transmitted off device under any circumstance. |
| NFR-SEC-003 | The store shall inherit the default file protection class of the application container. |
| NFR-SEC-004 | The privacy manifest shall declare no tracking and no collected data types. |

### 7.4 Maintainability

| ID | Requirement |
| --- | --- |
| NFR-MNT-001 | Domain logic shall reach at least 90 percent unit test line coverage. |
| NFR-MNT-002 | Adding a Module shall require a curriculum edit only, with no Swift change, provided its generator kind already exists. |
| NFR-MNT-003 | Adding a generator kind shall require a change in exactly one file, the question factory. |
| NFR-MNT-004 | Every layer boundary shall be expressed as a protocol so that a test double can be substituted. |

### 7.5 Portability

| ID | Requirement |
| --- | --- |
| NFR-POR-001 | No use of private API and no UIKit dependency beyond the haptic bridge. |
| NFR-POR-002 | Layout shall adapt to iPhone and iPad through size classes, not device checks. |

---

## 8. Curriculum blueprint, Levels A to F

### 8.1 Level inventory and gates

| Level | Name | Order | Unlock requirement | Modules | SCT band |
| --- | --- | --- | --- | --- | --- |
| A | Basic Arithmetic Foundations | 1 | None, entry point | 4 | 120 to 180 s |
| B | Multi-Digit Vertical Operations | 2 | 3 Qualifying Medals on A | 4 | 180 to 300 s |
| C | Multiplication Foundations | 3 | 3 Qualifying Medals on B | 4 | 150 to 300 s |
| D | Division and Rational Numbers | 4 | 3 Qualifying Medals on C | 4 | 180 to 240 s |
| E | Fraction Operations | 5 | 4 Qualifying Medals on D, at least 1 Gold | 4 | 180 to 300 s |
| F | Advanced Order of Operations | 6 | 4 Qualifying Medals on E, at least 2 Gold | 4 | 300 to 420 s |

### 8.2 Module inventory and generator bindings

| Module | Name | SCT (s) | Questions | Generator kind |
| --- | --- | --- | --- | --- |
| A_01 | Review of 2A Operations | 120 | 20 | `addition_within_10` |
| A_02 | Addition Summary up to 24 | 180 | 24 | `addition_within_24` |
| A_03 | Subtraction by 1 and 2 | 120 | 20 | `subtraction_small_step` |
| A_04 | Mixed Operations to 20 | 180 | 24 | `mixed_within_20` |
| B_01 | Vertical Addition to 100 | 180 | 20 | `vertical_addition` |
| B_02 | Vertical Addition with Carrying | 240 | 20 | `vertical_addition_carry` |
| B_03 | Vertical Subtraction with Borrowing | 240 | 20 | `vertical_subtraction_borrow` |
| B_04 | Three-Term Column Addition | 300 | 16 | `column_addition` |
| C_01 | Multiplication Tables 1 to 5 | 150 | 25 | `times_tables` |
| C_02 | Multiplication Tables 6 to 9 | 180 | 25 | `times_tables` |
| C_03 | Two-Digit by One-Digit Multiplication | 240 | 16 | `long_multiplication` |
| C_04 | Long Multiplication Grids | 300 | 12 | `long_multiplication` |
| D_01 | Division Facts without Remainders | 180 | 20 | `division_exact` |
| D_02 | Division with Remainders | 240 | 20 | `division_remainder` |
| D_03 | Fraction Identification | 180 | 18 | `fraction_identification` |
| D_04 | Fraction Reduction | 240 | 18 | `fraction_reduction` |
| E_01 | Review of Division and Multiples | 180 | 20 | `division_exact` |
| E_02 | Addition of Fractions (Like Denominators) | 240 | 20 | `fraction_add_like` |
| E_03 | Subtraction of Mixed Fractions | 300 | 16 | `mixed_fraction_subtract` |
| E_04 | Addition of Fractions (Unlike Denominators) | 300 | 16 | `fraction_add_unlike` |
| F_01 | Three-Fraction Mixed Operations | 300 | 14 | `three_fraction_mixed` |
| F_02 | Fractions and Decimals Conversions | 360 | 16 | `fraction_decimal_convert` |
| F_03 | Algebraic Word Problems | 420 | 12 | `algebraic_word_problem` |
| F_04 | Order of Operations with Brackets | 360 | 14 | `order_of_operations` |

Modules A_01 through A_03, E_01 through E_03, and F_01 through F_03 retain the exact names and SCT values supplied in the originating brief. All other Modules are new and derived from the Level descriptions in that brief.

### 8.3 Answer forms by generator

| Generator kind | Answer form | Validation rule |
| --- | --- | --- |
| Integer arithmetic generators | Integer | Exact match. |
| `division_remainder` | Quotient and remainder pair | Both parts shall match. |
| `fraction_identification` | Multiple choice | Single correct option. |
| `fraction_reduction`, `fraction_add_like`, `fraction_add_unlike`, `three_fraction_mixed` | Numerator and denominator pair | Shall be in lowest terms unless the Module explicitly disables that rule. |
| `mixed_fraction_subtract` | Whole, numerator, denominator triple | Improper results shall be accepted and normalised before comparison. |
| `fraction_decimal_convert` | Decimal string | Compared with a tolerance of 1e-6. |
| `algebraic_word_problem`, `order_of_operations` | Integer or decimal | Tolerance of 1e-6 for decimal results. |

---

## 9. Algorithms

### 9.1 Medal award

```
function award(elapsed, sct, correctFirstTry, questionCount, incorrectAttempts, hintsUsed, abandoned):
    if abandoned:                       return .none
    accuracy = correctFirstTry / questionCount
    flawless = (incorrectAttempts == 0) and (hintsUsed == 0)
    if flawless and elapsed <= sct:     return .gold
    if flawless:                        return .silver
    if accuracy >= 0.80:                return .bronze
    return .none
```

Post-conditions: the function is total, pure, and side effect free. It never reads the clock or the store.

### 9.2 Milestone Gate

```
function isUnlocked(requirement, snapshot):
    if requirement is null:                                     return true
    counts = snapshot.counts(for: requirement.sourceLevelID)
    qualifying = counts.gold + counts.silver
    return qualifying >= requirement.requiredMedalCount
       and counts.gold >= requirement.requiredGoldCount
```

The snapshot is built from persisted `ModuleProgressRecord` rows, one row per Module, using `bestMedalRaw`.

### 9.3 Best-result upsert

```
on session completion:
    record = fetch or create ModuleProgressRecord(moduleID)
    record.attemptCount += 1
    if not abandoned:
        record.completionCount += 1
        record.lastTimeSeconds = elapsed
        record.bestAccuracy = max(record.bestAccuracy, accuracy)
        if medal.rank > record.bestMedal.rank:
            record.bestMedalRaw = medal.raw
        if flawless and (record.bestTimeSeconds is null or elapsed < record.bestTimeSeconds):
            record.bestTimeSeconds = elapsed
        record.firstCompletedAt ??= now
    record.lastAttemptAt = now
```

---

## 10. State machines

### 10.1 Session states

| From | Event | To | Side effects |
| --- | --- | --- | --- |
| `idle` | `start` | `running` | Resolve Module, build questions, start clock. |
| `idle` | `start` with unknown Module | `failed` | Emit error, no clock start. |
| `running` | `submit` correct, questions remain | `running` | Advance index, success haptic. |
| `running` | `submit` correct, last question | `grading` | Stop clock, evaluate Medal. |
| `running` | `submit` incorrect | `running` | Increment incorrect count, warning haptic. |
| `running` | `background` or `pause` | `paused` | Pause clock, blur question surface. |
| `paused` | `resume` | `running` | Resume clock. |
| `paused` | `abandon` | `abandoned` | Stop clock, write abandoned session. |
| `running` | `abandon` | `abandoned` | Stop clock, write abandoned session. |
| `grading` | `persisted` | `summary` | Write records, evaluate Gates. |
| `grading` | `saveFailed` | `summary` | Present save notice, retain result in memory for retry. |
| `summary` | `dismiss` | `idle` | Invalidate skill tree state. |

Any transition not listed shall be rejected and logged as a programming error.

### 10.2 Level lock states

| From | Event | To |
| --- | --- | --- |
| `locked` | Gate satisfied | `unlocked` |
| `unlocked` | Every Module holds a Qualifying Medal | `completed` |
| `completed` | Curriculum adds a Module to the Level | `unlocked` |

`locked` is never re-entered once left. See IV-04.

---

## 11. Verification and acceptance criteria

| ID | Acceptance criterion |
| --- | --- |
| AC-01 | With the device in Airplane Mode and a clean install, a player can reach the skill tree, complete A_01, and receive a Medal. |
| AC-02 | A flawless run of E_02 at 239 seconds against an SCT of 240 awards Gold. The same run at 241 seconds awards Silver. |
| AC-03 | A run of E_02 with two incorrect submissions and final accuracy of 0.85 awards Bronze and does not count toward the Level F Gate. |
| AC-04 | Level E remains locked at 3 Qualifying Medals on Level D and unlocks at 4 with at least 1 Gold. |
| AC-05 | Force-quitting mid-session leaves the store with no `SessionRecord` for that attempt. |
| AC-06 | Backgrounding for 5 minutes and returning adds no time to `elapsedSeconds`. |
| AC-07 | Lowering `target_sct_seconds` in a later build does not change any Medal already awarded. |
| AC-08 | A malformed `curriculum.json` fails the build at the validation phase. |
| AC-09 | The full session flow is completable with VoiceOver active and Dynamic Type at AX3. |
| AC-10 | A static inspection of the shipping binary reports no runtime networking symbols. |

---

## 12. Traceability

| Requirement group | Components | Test target |
| --- | --- | --- |
| FR-CUR | CMP-09 | `CurriculumRepositoryTests` |
| FR-NAV | CMP-02, CMP-10 | `WorldMapStateTests` |
| FR-SES | CMP-04, CMP-03 | `LevelSessionControllerTests` |
| FR-BLZ | CMP-05 | `BlitzClockTests` |
| FR-MED | CMP-06 | `MedalEvaluatorTests` |
| FR-GATE | CMP-07, CMP-10 | `ProgressionGateTests` |
| FR-PER | CMP-10, CMP-11 | `ProgressStoreTests` |
| FR-FBK, FR-ACC | CMP-03, CMP-12 | Manual checklist, UI tests |
| FR-OFF | All | Release checklist, static inspection |

---

## Appendix A. Glossary of medal ranks

| Medal | Rank | Qualifying | Meaning |
| --- | --- | --- | --- |
| Gold | 3 | Yes | Flawless and inside the SCT. |
| Silver | 2 | Yes | Flawless, outside the SCT. |
| Bronze | 1 | No | Completed at 80 percent accuracy or better, not flawless. |
| None | 0 | No | Below 80 percent accuracy, or abandoned. |

## Appendix B. Open items for 1.1

| ID | Item |
| --- | --- |
| OI-01 | Multiple player profiles on one device. |
| OI-02 | Adaptive SCT that tightens as a player improves, recorded separately from the authored SCT. |
| OI-03 | Pencil and handwriting input for long multiplication grids. |
| OI-04 | Localisation beyond en-CA, including numeral formatting for fractions. |
| OI-05 | Guardian review screen with per-Level time-on-task summaries. |
