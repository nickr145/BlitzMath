#!/usr/bin/env python3
"""
validate-curriculum.py

Build-phase validation of the bundled curriculum payload (SRS DV-01 to DV-09).
A malformed payload fails the build rather than the app.

Usage:
    scripts/validate-curriculum.py <curriculum.json> [QuestionFactory.swift]

Emits Xcode-formatted diagnostics ("file:line: error: message") so failures
appear inline in the issue navigator. Exits non-zero on any error.

Runs on the python3 shipped with the Xcode command line tools. No third-party
packages, in keeping with SRS CN-05.
"""

import json
import re
import sys

MODULE_ID = re.compile(r"^[A-F]_[0-9]{2}$")
SCT_RANGE = (30, 900)
QUESTION_RANGE = (5, 40)
DEFAULT_QUESTION_COUNT = 20

errors: list[str] = []
warnings: list[str] = []


def error(rule: str, path: str, message: str) -> None:
    errors.append(f"[{rule}] {path}: {message}")


def warn(rule: str, path: str, message: str) -> None:
    warnings.append(f"[{rule}] {path}: {message}")


def supported_kinds(factory_path: str) -> set[str]:
    """Reads the authoritative generator set out of QuestionFactory.swift."""
    try:
        source = open(factory_path, encoding="utf-8").read()
        block = source.split("supportedKinds: Set<String> = [")[1].split("]")[0]
        return set(re.findall(r'"([a-z0-9_]+)"', block))
    except (OSError, IndexError):
        warn("DV-09", factory_path, "Generator set could not be read. Kind checking skipped.")
        return set()


def validate(payload: dict, kinds: set[str]) -> None:
    levels = payload.get("curriculum")
    if not isinstance(levels, list) or not levels:
        error("DV-01", "curriculum", "The payload has no levels.")
        return

    seen_levels: dict[str, dict] = {}
    seen_modules: set[str] = set()

    for index, level in enumerate(levels):
        base = f"curriculum[{index}]"
        level_id = level.get("level_id", "")

        # DV-02
        if not (isinstance(level_id, str) and len(level_id) == 1 and "A" <= level_id <= "F"):
            error("DV-02", f"{base}.level_id", f"Level id {level_id!r} is outside A to F.")
            continue
        if level_id in seen_levels:
            error("DV-02", f"{base}.level_id", f"Duplicate level id {level_id}.")
            continue
        seen_levels[level_id] = level

        modules = level.get("modules") or []
        if not modules:
            error("DV-03", f"{base}.modules", f"Level {level_id} has no modules.")

        for m_index, module in enumerate(modules):
            m_base = f"{base}.modules[{m_index}]"
            module_id = module.get("id", "")

            # DV-03
            if not MODULE_ID.match(module_id):
                error("DV-03", f"{m_base}.id", f"Module id {module_id!r} does not match <LEVEL>_<NN>.")
                continue
            if module_id.split("_")[0] != level_id:
                error("DV-03", f"{m_base}.id", f"Module {module_id} is not prefixed with level {level_id}.")
            if module_id in seen_modules:
                error("DV-03", f"{m_base}.id", f"Duplicate module id {module_id}.")
            seen_modules.add(module_id)

            # DV-04
            sct = module.get("target_sct_seconds")
            if not isinstance(sct, int) or not SCT_RANGE[0] <= sct <= SCT_RANGE[1]:
                error("DV-04", f"{m_base}.target_sct_seconds",
                      f"SCT {sct} is outside {SCT_RANGE[0]} to {SCT_RANGE[1]}.")

            count = module.get("question_count", DEFAULT_QUESTION_COUNT)
            if not isinstance(count, int) or not QUESTION_RANGE[0] <= count <= QUESTION_RANGE[1]:
                error("DV-04", f"{m_base}.question_count",
                      f"Question count {count} is outside {QUESTION_RANGE[0]} to {QUESTION_RANGE[1]}.")

            # DV-09
            kind = (module.get("generator") or {}).get("kind")
            if kinds and kind and kind not in kinds:
                error("DV-09", f"{m_base}.generator.kind",
                      f"Unknown generator kind {kind!r}. Add a case in QuestionFactory first.")

    order = {lid: lv.get("level_order") or (ord(lid) - ord("A") + 1) for lid, lv in seen_levels.items()}

    # DV-07
    entry_points = [lid for lid, lv in seen_levels.items() if lv.get("unlock_requirement") is None]
    if not entry_points:
        error("DV-07", "curriculum", "No level is unlocked at first launch.")
    elif len(entry_points) > 1:
        warn("DV-07", "curriculum", f"More than one entry point: {', '.join(sorted(entry_points))}.")

    # DV-05, DV-06
    for level_id, level in seen_levels.items():
        requirement = level.get("unlock_requirement")
        if requirement is None:
            continue
        path = f"curriculum[{level_id}].unlock_requirement"
        source_id = requirement.get("source_level_id")

        if source_id not in seen_levels:
            error("DV-05", f"{path}.source_level_id", f"Source level {source_id!r} does not exist.")
            continue
        if order[source_id] >= order[level_id]:
            error("DV-05", f"{path}.source_level_id",
                  f"Source level {source_id} does not precede {level_id}.")

        required = requirement.get("required_medal_count", 0)
        gold = requirement.get("required_gold_count", 0)
        source_modules = len(seen_levels[source_id].get("modules") or [])

        if required > source_modules:
            error("DV-06", f"{path}.required_medal_count",
                  f"Requires {required} medals but level {source_id} has {source_modules} modules.")
        if gold > required:
            error("DV-06", f"{path}.required_gold_count",
                  f"Gold requirement {gold} exceeds the total medal requirement {required}.")

    print(f"Curriculum: {len(seen_levels)} levels, {len(seen_modules)} modules, "
          f"entry point {', '.join(sorted(entry_points)) or 'none'}.")


def validate_placement(payload: dict, kinds: set[str]) -> None:
    """SRS Addendum 01 rules PV-01 to PV-06."""
    rules = {}
    for index, rule in enumerate(payload.get("bands") or []):
        path = f"bands[{index}]"
        band = rule.get("band", "")
        if not (isinstance(band, str) and len(band) == 1 and "A" <= band <= "F"):
            error("PV-01", f"{path}.band", f"Band {band!r} is outside A to F.")
            continue
        if band in rules:
            error("PV-01", f"{path}.band", f"Duplicate band {band}.")
        pace = rule.get("pace_seconds_per_question")
        if not isinstance(pace, (int, float)) or not 3.0 <= pace <= 90.0:
            error("PV-02", f"{path}.pace_seconds_per_question", f"Pace {pace} is outside 3 to 90.")
        mastery = rule.get("mastery_accuracy", 0.80)
        developing = rule.get("developing_accuracy", 0.60)
        if developing > mastery:
            error("PV-02", f"{path}.developing_accuracy",
                  f"Developing accuracy {developing} exceeds mastery accuracy {mastery}.")
        rules[band] = rule

    seen_sections = set()
    band_counts: dict[str, int] = {}

    for index, section in enumerate(payload.get("sections") or []):
        path = f"sections[{index}]"
        section_id = section.get("section_id", "")
        if not re.fullmatch(r"S[0-9]", section_id):
            error("PV-03", f"{path}.section_id", f"Section id {section_id!r} does not match S<n>.")
        if section_id in seen_sections:
            error("PV-03", f"{path}.section_id", f"Duplicate section id {section_id}.")
        seen_sections.add(section_id)

        items = section.get("items") or []
        if not items:
            error("PV-03", f"{path}.items", f"Section {section_id} has no items.")

        for item_index, item in enumerate(items):
            item_path = f"{path}.items[{item_index}]"
            band = item.get("band")
            if band not in rules:
                error("PV-04", f"{item_path}.band", f"Band {band!r} has no rule.")
            count = item.get("count")
            if not isinstance(count, int) or not 1 <= count <= 12:
                error("PV-04", f"{item_path}.count", f"Count {count} is outside 1 to 12.")
            kind = (item.get("generator") or {}).get("kind")
            if kinds and kind not in kinds:
                error("PV-05", f"{item_path}.generator.kind", f"Unknown generator kind {kind!r}.")
            if band and isinstance(count, int):
                band_counts[band] = band_counts.get(band, 0) + count

    # PV-06. Legal but worth surfacing: the band can never be judged mastered.
    for band, rule in rules.items():
        sampled = band_counts.get(band, 0)
        minimum = rule.get("minimum_questions", 4)
        if sampled < minimum:
            warn("PV-06", f"bands[{band}]",
                 f"Band {band} is sampled {sampled} times but needs {minimum} to be judged mastered.")

    total = sum(band_counts.values())
    print(f"Placement: {len(seen_sections)} sections, {total} questions, "
          f"band spread {dict(sorted(band_counts.items()))}.")


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: validate-curriculum.py <curriculum.json> [QuestionFactory.swift] [placement.json]",
              file=sys.stderr)
        return 2

    payload_path = sys.argv[1]
    factory_path = sys.argv[2] if len(sys.argv) > 2 else None
    placement_path = sys.argv[3] if len(sys.argv) > 3 else None

    # DV-01
    try:
        payload = json.load(open(payload_path, encoding="utf-8"))
    except OSError as exc:
        print(f"{payload_path}:1: error: [DV-01] The payload could not be read. {exc}")
        return 1
    except json.JSONDecodeError as exc:
        print(f"{payload_path}:{exc.lineno}: error: [DV-01] Invalid JSON. {exc.msg}")
        return 1

    kinds = supported_kinds(factory_path) if factory_path else set()
    validate(payload, kinds)

    if placement_path:
        try:
            validate_placement(json.load(open(placement_path, encoding="utf-8")), kinds)
        except OSError as exc:
            print(f"{placement_path}:1: error: [PV-00] The placement payload could not be read. {exc}")
            return 1
        except json.JSONDecodeError as exc:
            print(f"{placement_path}:{exc.lineno}: error: [PV-00] Invalid JSON. {exc.msg}")
            return 1

    for message in warnings:
        print(f"{payload_path}:1: warning: {message}")
    for message in errors:
        print(f"{payload_path}:1: error: {message}")

    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
