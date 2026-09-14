#!/usr/bin/env python3
"""Produce a compact, reproducible report from retained device-run evidence."""
import json
from pathlib import Path
import re
import statistics
import sys


def write_summary(directory):
    directory = Path(directory)
    run = json.loads((directory / "run.json").read_text())
    rows = []
    log = directory / "build.log"
    pattern = re.compile(r"Test Case '(.+?)' measured \[(.+?)\] average: ([^,]+),.*?values: \[([^]]+)\]")
    if log.exists():
        ui_implementation = "unknown"
        for line in log.read_text(errors="replace").splitlines():
            named = re.search(r"Added attachment named '(legacy|swift)-", line)
            if named:
                ui_implementation = named.group(1)
            match = pattern.search(line)
            if not match:
                continue
            test, metric, average, raw = match.groups()
            implementation = ("legacy" if "LegacyDriverTests" in test else
                              "swift" if "SharedDriverTests" in test else ui_implementation)
            values = [float(value.strip()) for value in raw.split(",")]
            rows.append({"implementation": implementation, "test": test, "metric": metric,
                         "mean": statistics.mean(values), "samples": values})
    interactions = []
    manifest = directory / "attachments/manifest.json"
    if manifest.exists():
        for test in json.loads(manifest.read_text()):
            for attachment in test.get("attachments", []):
                if "-measurement" in attachment.get("suggestedHumanReadableName", ""):
                    path = manifest.parent / attachment["exportedFileName"]
                    interactions.append({"configuration": attachment.get("configurationName"),
                                         "file": str(path.relative_to(directory)), "observation": path.read_text()})
    (directory / "measurements.json").write_text(json.dumps({"xctest": rows, "interactions": interactions}, indent=2) + "\n")
    counts = run.get("tests", {})
    lines = ["# Device test result", "", f"Status: **{run['status']}**; xcodebuild exit {run['exitCode']}.",
             f"Destination: `{run['destination']}`.",
             f"Unique tests: {counts.get('passedTests', '?')} passed, {counts.get('failedTests', '?')} failed, {counts.get('skippedTests', '?')} skipped.", ""]
    for entry in run.get("devicesAndConfigurations", []):
        device = entry.get("device", {})
        config = entry.get("testPlanConfiguration", {}).get("configurationName", "unknown")
        lines.append(f"- {config}: {entry.get('passedTests')} passed, {entry.get('failedTests')} failed on {device.get('modelName')} / {device.get('osVersion')}.")
    lines += ["", "The same hosted tests run in each configuration; unique test totals may be deduplicated by xcresulttool.",
              "", "## Measurements", "", "| Implementation | Test | Metric | Mean | Samples |", "| --- | --- | --- | ---: | ---: |"]
    for row in rows:
        lines.append(f"| {row['implementation']} | {row['test']} | {row['metric']} | {row['mean']:.6f} | {len(row['samples'])} |")
    lines += ["", "Memory metrics describe the entire test host and include earlier allocations in that process. Use isolated performance runs for a fairer comparison.",
              "UI interaction durations include automation overhead; they are not frame timings.",
              "", "See measurements.json for raw samples, run.json for fixtures/configuration, and Tests.xcresult for complete evidence."]
    (directory / "Summary.md").write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    write_summary(sys.argv[1])
