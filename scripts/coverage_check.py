#!/usr/bin/env python3
#
#  coverage_check.py
#  ClipBoard
#
#  Fails when line coverage of a guarded layer (Models, Persistence, Services, ViewModels) is under
#  the floor in audit.config.json. Files listed under coverageExclusions are left out, with a reason.
#
import json
import subprocess
import sys

xcresult, config_path = sys.argv[1], sys.argv[2]
config = json.load(open(config_path))
floor = config["coverageFloor"]
layers = config["coverageLayers"]
excluded = {entry["file"] for entry in config["coverageExclusions"]}

result = subprocess.run(["xcrun", "xccov", "view", "--report", "--json", xcresult], capture_output=True, text=True)
if result.returncode != 0:
    print("No coverage report in the result bundle (did the build fail?)")
    sys.exit(1)
report = json.loads(result.stdout)
app = next((t for t in report["targets"] if t["name"].startswith("ClipBoard.app")), None)
if app is None:
    print("No coverage data for ClipBoard.app")
    sys.exit(1)

totals = {layer: [0, 0] for layer in layers}
rows = []
for f in app["files"]:
    # Path relative to the app source folder, e.g. "Services/PasteService.swift". The repo folder is
    # also called ClipBoard, so split on the last occurrence.
    name = f["path"].rsplit("/ClipBoard/", 1)[-1]
    layer = name.split("/", 1)[0]
    if layer not in layers:
        continue
    if name in excluded:
        rows.append(f"  {'excluded':>8}  {name}")
        continue
    totals[layer][0] += f["coveredLines"]
    totals[layer][1] += f["executableLines"]
    rows.append(f"  {f['lineCoverage'] * 100:7.1f}%  {name}")

failed = False
for layer, (covered, executable) in totals.items():
    pct = 100.0 * covered / executable if executable else 100.0
    ok = pct >= floor
    failed |= not ok
    print(f"{'✓' if ok else '✗'} {layer}: {pct:.1f}% (floor {floor}%)")
print("\n".join(sorted(rows)))
sys.exit(1 if failed else 0)
