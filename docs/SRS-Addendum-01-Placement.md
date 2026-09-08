# Software Requirements Specification, Addendum 01
## First-Run Placement Test

| Field | Value |
| --- | --- |
| Document ID | BLZ-SRS-A01 |
| Version | 1.0.0 |
| Status | Baselined for implementation |
| Date | 2026-09-07 |
| Extends | BLZ-SRS-001 v1.0.0 |
| Target release | BlitzMath 1.0.0 |

This addendum adds the Placement Test and the first-run routing that surrounds it. It extends sections 2, 4, 5, and 8 of the base SRS. Where the two documents disagree, this one governs the placement flow only. Nothing here changes medal rules, the Blitz Engine, or the offline constraint.

---

## A1. Purpose and rationale

Every player currently begins at Level A, Module 1. For a player who already handles multi-digit multiplication, the first several Worlds are unearned repetition, and repetition is where a drill app loses people. The Placement Test measures what the player can already do, quickly, and opens the World that fits.

The model is the Kumon paper placement test: a short, timed, mixed-difficulty diagnostic sat once before the programme begins. Two properties of that model carry over and are requirements here.

- **Speed is part of the measurement.** A player who answers correctly but slowly has not mastered the material at the level the drill expects. Accuracy alone would place people too high.
- **The test is a starting point, not a grade.** Nothing is awarded, nothing is failed, and the result is presented as a starting position that the player can override.

## A2. Definitions added to the base glossary

| Term | Definition |
| --- | --- |
| Placement Test | The optional first-run diagnostic, composed of four Sections. |
| Section | One timed screen of the Placement Test. The player-facing pacing unit. Four in total. |
| Band | The scoring unit, identified A through F, matching a curriculum Level. Every Placement question carries exactly one Band. |
| Band Verdict | The outcome for one Band, one of mastered, developing, or not ready. |
| Entry Level | The Level the player starts at, decided by the scorer or chosen by the player. |
| Placed Out | A Level opened by placement rather than by earning medals. |
| Pace Target | The seconds-per-question ceiling for a Band, above which correct answers do not count as mastery. |

## A3. Sections and Bands

Sections group questions the way the player experiences them. Bands decide placement. The two are separate because four Sections cannot resolve to six Levels on their own, and because a single skill area spans more than one Level of difficulty. Adding and taking away covers Band A single-digit work and Band B carrying and borrowing in the same Section, and the scorer needs to tell those apart.

| Section | Title | Bands present | Questions |
| --- | --- | --- | --- |
| S1 | Adding and taking away | A, B | 9 |
| S2 | Times and sharing | C, D | 8 |
| S3 | Whole numbers and the order of operations | D, F | 8 |
| S4 | Fractions | D, E, F | 10 |

Total 35 questions, targeted at 8 to 11 minutes. Band D appears in three Sections by design. Its verdict is computed once, across every Band D question in the test.

Section 3 is the interpretation of "integers" from the originating request: whole-number work that is not a single operation, meaning division with remainders, bracketed order of operations, and one-step word problems. Signed negative numbers are not part of Levels A through F and are not tested. If signed integers are wanted, that is a Level G question and belongs in a curriculum change, not here.

## A4. Data requirements

### A4.1 `placement.json`

A second bundled payload, loaded and validated on the same terms as `curriculum.json` (base SRS DV-01, DV-08).

#### Root

| Field | Type | Required | Rule |
| --- | --- | --- | --- |
| `placement_version` | String | Yes | Semantic version of this payload. |
| `sections` | Array\<Section\> | Yes | Exactly 4 for 1.0.0. Presented in array order. |
| `bands` | Array\<BandRule\> | Yes | One entry per Band referenced by any item. |

#### Section

| Field | Type | Required | Rule |
| --- | --- | --- | --- |
| `section_id` | String | Yes | Matches `^S[0-9]$`. Unique. |
| `title` | String | Yes | Player-facing, 1 to 48 characters. |
| `blurb` | String | No | One line shown before the Section starts. |
| `items` | Array\<Item\> | Yes | Minimum 1. |

#### Item

| Field | Type | Required | Rule |
| --- | --- | --- | --- |
| `band` | String | Yes | A to F. Shall have a matching `bands` entry. |
| `count` | Int | Yes | 1 to 12. |
| `generator` | Generator | Yes | Same shape and same permitted kinds as the curriculum payload. |

#### BandRule

| Field | Type | Required | Default | Rule |
| --- | --- | --- | --- | --- |
| `band` | String | Yes | none | A to F, unique. |
| `entry_level_id` | String | Yes | none | The Level a failure in this Band places the player at. |
| `pace_seconds_per_question` | Double | Yes | none | 3.0 to 90.0. |
| `mastery_accuracy` | Double | No | `0.80` | 0.0 to 1.0. |
| `developing_accuracy` | Double | No | `0.60` | Shall not exceed `mastery_accuracy`. |
| `minimum_questions` | Int | No | `4` | Below this count the Band cannot be judged mastered. |

### A4.2 Persistent additions

Added to `PlayerProfile`:

| Attribute | Type | Notes |
| --- | --- | --- |
| `hasCompletedOnboarding` | Bool | True once the player has taken the test, declined it, or already has progress. |
| `placementEntryLevelID` | String? | The Level placement opened. Null when the test was declined. |

Added to `LevelProgressRecord`:

| Attribute | Type | Notes |
| --- | --- | --- |
| `unlockedByPlacement` | Bool | Distinguishes a Placed Out Level from one opened by earning medals. |

New entity `PlacementResultRecord`:

| Attribute | Type | Notes |
| --- | --- | --- |
| `id` | UUID | Unique. |
| `takenAt` | Date | Wall clock. |
| `wasCompleted` | Bool | False when the player left partway through. |
| `entryLevelID` | String | The scorer's placement. |
| `acceptedLevelID` | String | What the player actually started at, which may differ. |
| `totalSeconds` | Double | Monotonic, sum of Section times. |
| `sectionSummaries` | [PlacementSectionSummary] | Codable value type, one per Section. |
| `bandSummaries` | [PlacementBandSummary] | Codable value type, one per Band. |

`PlacementSectionSummary`: `sectionID`, `elapsedSeconds`, `askedCount`, `correctCount`, `incorrectCount`, `skippedCount`.

`PlacementBandSummary`: `band`, `askedCount`, `correctCount`, `skippedCount`, `totalSeconds`, `verdictRaw`.

The record is written once and never mutated. It is retained for the progress review screen, so a supervising adult can see why the player started where they did.

## A5. Functional requirements

### A5.1 First-run routing, FR-ONB

| ID | Requirement | Priority | Verify |
| --- | --- | --- | --- |
| FR-ONB-001 | On launch the system shall determine whether the profile has any prior progress, defined as at least one `SessionRecord`, at least one `ModuleProgressRecord`, or `hasCompletedOnboarding` being true. | P1 | T |
| FR-ONB-002 | When prior progress exists the system shall route straight to the skill tree and shall not offer the Placement Test. | P1 | T |
| FR-ONB-003 | When no prior progress exists the system shall present the onboarding choice screen before the skill tree. | P1 | T |
| FR-ONB-004 | The choice screen shall offer exactly two actions, taking the test and starting at the beginning, presented as equal options with neither pre-selected or visually favoured. | P1 | D |
| FR-ONB-005 | Declining the test shall set `hasCompletedOnboarding` to true, open Level A only, and route to the skill tree. The player shall not be asked again. | P1 | T |
| FR-ONB-006 | The choice screen shall state, in one line, roughly how long the test takes and that nothing is graded. | P2 | D |
| FR-ONB-007 | The Placement Test shall be reachable later from Settings, for a player who declined and changed their mind, and re-taking it shall never lower an already unlocked Level. | P2 | T |
| FR-ONB-008 | Routing shall not flash the skill tree before the choice screen. The progress check completes before the first frame either screen draws. | P2 | D |

### A5.2 Test execution, FR-PLC

| ID | Requirement | Priority | Verify |
| --- | --- | --- | --- |
| FR-PLC-001 | The system shall build the full question set for every Section before the first Section clock starts. | P1 | T |
| FR-PLC-002 | Each Section shall be timed independently with the monotonic clock, and Section time shall exclude paused intervals. | P1 | T |
| FR-PLC-003 | The system shall record, per question, its Band, whether the first answer was correct, whether it was skipped, and the seconds spent on it. | P1 | T |
| FR-PLC-004 | Unlike a drill session, an incorrect answer shall advance to the next question rather than holding the current one. The test measures, it does not teach. | P1 | T |
| FR-PLC-005 | The system shall provide a per-question "I have not learned this yet" action, recorded as skipped and scored as incorrect for its Band. | P1 | T |
| FR-PLC-006 | The system shall provide a per-Section skip, marking every remaining question in that Section as skipped. | P2 | T |
| FR-PLC-007 | No medal, streak, or module progress shall be written by the Placement Test. | P1 | T |
| FR-PLC-008 | The test shall show Section position, as Section n of 4, and shall not show a countdown or any failure state. | P1 | D |
| FR-PLC-009 | Leaving partway through shall write a `PlacementResultRecord` with `wasCompleted` false, shall not place the player, and shall return them to the choice screen. | P1 | T |
| FR-PLC-010 | Backgrounding shall pause the Section clock and require an explicit resume, matching base FR-SES-008 and FR-SES-009. | P1 | T |
| FR-PLC-011 | Hints shall not be offered during the Placement Test. | P1 | I |

### A5.3 Scoring and placement, FR-PLA

| ID | Requirement | Priority | Verify |
| --- | --- | --- | --- |
| FR-PLA-001 | The scorer shall be a pure function over the answer log and the Band rules, with no clock, store, or view dependency. | P1 | I |
| FR-PLA-002 | Band accuracy shall be `correct / asked`, where a skipped question counts as asked and not correct. | P1 | I |
| FR-PLA-003 | Band pace shall be `totalSeconds / asked`, measured only across that Band's questions. | P1 | I |
| FR-PLA-004 | A Band shall be judged mastered when `asked >= minimum_questions`, accuracy is at or above `mastery_accuracy`, and pace is at or below `pace_seconds_per_question`. | P1 | T |
| FR-PLA-005 | A Band shall be judged developing when accuracy is at or above `developing_accuracy` but the mastered test fails. | P1 | T |
| FR-PLA-006 | A Band shall otherwise be judged not ready. A Band with fewer than `minimum_questions` answered shall never be judged mastered. | P1 | T |
| FR-PLA-007 | The Entry Level shall be the `entry_level_id` of the lowest-ordered Band that is not mastered. | P1 | T |
| FR-PLA-008 | When every Band is mastered the Entry Level shall be the highest Band's `entry_level_id`. The scorer shall never place a player past the last Level. | P1 | T |
| FR-PLA-009 | Placement shall open every Level ordered below the Entry Level, and the Entry Level itself, marking each `unlockedByPlacement`. | P1 | T |
| FR-PLA-010 | Placement shall not award medals for Placed Out Levels, and shall not mark their modules complete. Those Levels remain playable. | P1 | T |
| FR-PLA-011 | Levels above the Entry Level shall remain governed by the ordinary Milestone Gate. Placement opens a starting position, it does not bypass the gate chain. | P1 | T |
| FR-PLA-012 | The result screen shall state the Entry Level, name what it covers in plain language, and offer an explicit action to start at Level A instead. | P1 | D |
| FR-PLA-013 | If the player overrides the placement, `acceptedLevelID` shall record the override, and the Placed Out Levels shall remain open. | P2 | T |
| FR-PLA-014 | The result screen shall not present a score, percentage, rank, or any pass and fail language. | P1 | I |

## A6. Placement blueprint

### A6.1 Band rules

| Band | Entry Level | Pace target, seconds per question | Mastery accuracy | Minimum questions |
| --- | --- | --- | --- | --- |
| A | A | 7.0 | 0.80 | 4 |
| B | B | 14.0 | 0.80 | 4 |
| C | C | 10.0 | 0.80 | 4 |
| D | D | 18.0 | 0.80 | 6 |
| E | E | 26.0 | 0.75 | 4 |
| F | F | 38.0 | 0.75 | 4 |

Band D carries a higher minimum because it is sampled across three Sections and a placement into Level D or E turns on it.

### A6.2 Section composition

| Section | Band | Generator kind | Count |
| --- | --- | --- | --- |
| S1 | A | `addition_within_24` | 3 |
| S1 | A | `subtraction_small_step` | 2 |
| S1 | B | `vertical_addition_carry` | 2 |
| S1 | B | `vertical_subtraction_borrow` | 2 |
| S2 | C | `times_tables` | 3 |
| S2 | C | `long_multiplication` | 2 |
| S2 | D | `division_exact` | 3 |
| S3 | D | `division_remainder` | 3 |
| S3 | F | `order_of_operations` | 3 |
| S3 | F | `algebraic_word_problem` | 2 |
| S4 | D | `fraction_reduction` | 2 |
| S4 | E | `fraction_add_like` | 2 |
| S4 | E | `fraction_add_unlike` | 2 |
| S4 | F | `fraction_decimal_convert` | 2 |
| S4 | F | `three_fraction_mixed` | 2 |

Band totals: A 5, B 4, C 5, D 8, E 4, F 9. Every Band meets or exceeds its own `minimum_questions`, which is a hard requirement of the payload rather than a style preference. A Band sampled below its minimum can never be judged mastered, and because the scorer stops at the first unmastered Band, one under-sampled Band silently caps every placement at that Band's Level. The build-phase validator raises PV-06 for this case.

## A7. Algorithm

```
function place(log, rules):
    byBand = group(log, key: .band)
    verdicts = {}

    for rule in rules.sortedByLevelOrder:
        entries = byBand[rule.band] ?? []
        asked = entries.count
        correct = entries.count(where: .wasCorrect)
        accuracy = asked > 0 ? correct / asked : 0
        pace = asked > 0 ? sum(entries.seconds) / asked : infinity

        if asked >= rule.minimumQuestions
           and accuracy >= rule.masteryAccuracy
           and pace <= rule.paceSecondsPerQuestion:
            verdicts[rule.band] = .mastered
        else if accuracy >= rule.developingAccuracy:
            verdicts[rule.band] = .developing
        else:
            verdicts[rule.band] = .notReady

    for rule in rules.sortedByLevelOrder:
        if verdicts[rule.band] != .mastered:
            return rule.entryLevelID

    return rules.sortedByLevelOrder.last.entryLevelID
```

The scorer stops at the first Band that is not mastered, so a player who is strong on fractions but shaky on carrying still starts at Level B. That is the intended conservative behaviour: the curriculum is cumulative, and a gap early is a gap that compounds.

## A8. Acceptance criteria

| ID | Acceptance criterion |
| --- | --- |
| AC-A01 | A clean install shows the choice screen, not the skill tree. |
| AC-A02 | Declining the test opens Level A only and never shows the choice screen again. |
| AC-A03 | An install with one completed session never shows the choice screen, on any later launch. |
| AC-A04 | A log that is perfect and fast on Bands A and B, and empty on C, places at Level C. |
| AC-A05 | A log that is perfect but slow on Band A places at Level A, despite full accuracy. |
| AC-A06 | Skipping every question places at Level A and writes a completed result with all Bands not ready. |
| AC-A07 | A perfect, fast run of every Band places at Level F and does not place beyond it. |
| AC-A08 | Placement into Level D opens A, B, C, and D, awards no medals, and leaves Level E governed by its medal gate. |
| AC-A09 | Overriding a Level D placement to start at Level A leaves B, C, and D open. |
| AC-A10 | Leaving the test partway writes a result with `wasCompleted` false and places nobody. |
| AC-A11 | Backgrounding during Section 2 adds no time to that Section's measurement. |
| AC-A12 | The result screen contains no percentage, score, or pass and fail wording. |

## A9. Traceability

| Requirement group | Components | Test target |
| --- | --- | --- |
| FR-ONB | `RootView`, `OnboardingChoiceView`, `ProgressStore` | `OnboardingRoutingTests` |
| FR-PLC | `PlacementController`, `PlacementView`, `BlitzClock` | `PlacementControllerTests` |
| FR-PLA | `PlacementScorer`, `ProgressStore.applyPlacement` | `PlacementScorerTests` |
