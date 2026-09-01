#!/usr/bin/env python3
"""Validate review accounting, not the truth of scientific findings.

Every expected original finding and session must have an explicit disposition.
Missing review output is an error, never an empty successful result.
"""
import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DISPOSITIONS = {"confirmed", "narrowed", "refuted", "known", "resolved", "unresolved"}
AUDIT_DISPOSITIONS = {"confirmed", "narrowed", "contradicted", "unverified", "known", "resolved", "refuted"}

def text(value):
    return isinstance(value, str) and bool(value.strip())

def demand(condition, message):
    if not condition:
        raise ValueError(message)

def validate(directory):
    manifest = json.loads((directory / "recovery-manifest.json").read_text())
    report = json.loads((directory / "findings.json").read_text())
    audits = json.loads((directory / "session-audit.json").read_text())
    demand(all(isinstance(x, dict) for x in [manifest, report, audits]), "object records required")
    demand(isinstance(manifest.get("areas"), list) and manifest["areas"], "nonempty area roster required")
    demand(isinstance(manifest.get("expectedSessions"), list) and manifest["expectedSessions"],
           "nonempty session roster required")
    demand(all(text(s) for s in manifest["expectedSessions"]), "session names must be text")
    demand(len(set(manifest["expectedSessions"])) == len(manifest["expectedSessions"]), "duplicate session roster")
    demand(type(manifest.get("initialEntries")) is int and manifest["initialEntries"] > 0,
           "positive original entry count required")
    demand(isinstance(report.get("findings"), list), "findings list required")
    demand(isinstance(audits.get("sessions"), list), "session audits list required")
    errors = []
    expected = {}
    area_names = set()
    for area in manifest["areas"]:
        demand(isinstance(area, dict) and text(area.get("area")), "area object/name required")
        demand(area["area"] not in area_names, "duplicate area roster")
        demand(type(area.get("findings")) is int and area["findings"] > 0, "positive area count required")
        area_names.add(area["area"])
        original = json.loads((directory / "initial" / (area["area"] + ".json")).read_text())
        demand(isinstance(original, dict) and isinstance(original.get("findings"), list),
               "original findings list required")
        if len(original["findings"]) != area["findings"]:
            errors.append(f"original count changed: {area['area']}")
        for index, finding in enumerate(original["findings"], 1):
            demand(isinstance(finding, dict) and text(finding.get("title")), "original title required")
            expected[f"{area['area']}-{index:02}"] = finding["title"]
    if len(expected) != manifest["initialEntries"]:
        errors.append("manifest total disagrees with original findings")
    seen = set()
    for item in report["findings"]:
        demand(isinstance(item, dict) and text(item.get("id")), "finding object/id required")
        identifier = item.get("id")
        if identifier in seen:
            errors.append(f"duplicate finding: {identifier}")
        seen.add(identifier)
        if identifier not in expected or item.get("originalTitle") != expected.get(identifier):
            errors.append(f"unknown or changed original finding: {identifier}")
        if not text(item.get("status")) or item["status"] not in DISPOSITIONS:
            errors.append(f"missing/invalid disposition: {identifier}")
        for field in ["evidence", "verificationMethod", "remainingVerification"]:
            if not text(item.get(field)):
                errors.append(f"missing {field}: {identifier}")
    for identifier in sorted(set(expected) - seen):
        errors.append(f"missing verification: {identifier}")
    expected_sessions = set(manifest["expectedSessions"])
    seen_sessions = set()
    for session in audits["sessions"]:
        demand(isinstance(session, dict) and text(session.get("session")), "session object/name required")
        name = session.get("session")
        if name in seen_sessions or name not in expected_sessions:
            errors.append(f"duplicate/unknown session: {name}")
        seen_sessions.add(name)
        demand(isinstance(session.get("claims"), list), "audit claims list required")
        if not session["claims"]:
            errors.append(f"empty audit: {name}")
        for claim in session.get("claims", []):
            demand(isinstance(claim, dict), "audit claim object required")
            if not all(text(claim.get(k)) for k in ["claim", "status", "evidence"]):
                errors.append(f"incomplete claim in {name}")
            elif claim["status"] not in AUDIT_DISPOSITIONS:
                errors.append(f"invalid audit disposition in {name}")
    for name in sorted(expected_sessions - seen_sessions):
        errors.append(f"missing session audit: {name}")
    return errors, len(expected), len(expected_sessions)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", nargs="?", type=Path,
                        default=ROOT / "docs/archive/2026-08-31-review")
    args = parser.parse_args()
    try:
        errors, count, sessions = validate(args.directory)
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"FAIL: incomplete or malformed review evidence: {error}", file=sys.stderr)
        return 1
    if errors:
        for error in errors:
            print(f"FAIL: {error}", file=sys.stderr)
        return 1
    print(f"PASS: {count} original findings accounted; {sessions} session audits present")
    print("Accounting only: dispositions may include unresolved findings; this is not release approval.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
