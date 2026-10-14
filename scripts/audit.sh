#!/bin/zsh
#
#  audit.sh
#  ClipBoard
#
#  The only entry point for building and testing. Usage: scripts/audit.sh gate
#  gate: static checks, build with warnings as errors, unit tests, coverage floors.
#  Output: build/audit/<timestamp>/ (xcresult, xcodebuild.log, summary.json, report.md).
#  ClipBoard has no simulator tiers (macOS menu-bar app, no UI journeys yet), so only `gate` exists.
#

set -uo pipefail

TIER="${1:-gate}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "$TIER" != "gate" ]]; then
  echo "Tier '$TIER' is not available for ClipBoard; only 'gate' exists."
  exit 2
fi

STAMP="$(date +%Y-%m-%d_%H%M%S)"
OUT="build/audit/$STAMP"
mkdir -p "$OUT"
FAILURES=()

echo "▸ Static checks"
if grep -rnE 'accessibilityIdentifier\("' ClipBoard --include='*.swift' > "$OUT/identifier-literals.txt"; then
  FAILURES+=("accessibility identifier string literal at a call site (see identifier-literals.txt)")
fi
if grep -rnE '(^|[^.A-Za-z_])(sleep|usleep)\(' ClipBoardUnitTests --include='*.swift' > "$OUT/sleeps.txt"; then
  FAILURES+=("sleep() in tests (see sleeps.txt)")
fi

echo "▸ Build + unit tests (warnings are errors)"
xcodebuild test \
  -project ClipBoard.xcodeproj \
  -scheme ClipBoard \
  -testPlan Gate \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/DerivedData \
  -resultBundlePath "$OUT/gate.xcresult" \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
  GCC_TREAT_WARNINGS_AS_ERRORS=YES \
  > "$OUT/xcodebuild.log" 2>&1
TEST_STATUS=$?

grep -E "^$ROOT/(ClipBoard|ClipBoardUnitTests)/.*: (error|warning): " "$OUT/xcodebuild.log" | sort -u > "$OUT/diagnostics.txt"
if [[ -s "$OUT/diagnostics.txt" ]]; then
  FAILURES+=("compiler errors/warnings in repo code (see diagnostics.txt)")
fi
if [[ $TEST_STATUS -ne 0 ]]; then
  FAILURES+=("xcodebuild test exited $TEST_STATUS (see xcodebuild.log)")
fi

TESTS_JSON="{}"
if [[ -d "$OUT/gate.xcresult" ]]; then
  TESTS_JSON="$(xcrun xcresulttool get test-results summary --path "$OUT/gate.xcresult" --compact 2>/dev/null || echo '{}')"
  xcrun xcresulttool get test-results tests --path "$OUT/gate.xcresult" --compact > "$OUT/tests.json" 2>/dev/null || true

  echo "▸ Coverage floors"
  if ! python3 scripts/coverage_check.py "$OUT/gate.xcresult" scripts/audit.config.json > "$OUT/coverage.txt" 2>&1; then
    FAILURES+=("coverage below floor (see coverage.txt)")
  fi
  cat "$OUT/coverage.txt"
else
  FAILURES+=("no xcresult produced")
fi

RESULT="PASS"
[[ ${#FAILURES[@]} -gt 0 ]] && RESULT="FAIL"

python3 - "$OUT" "$RESULT" "$TESTS_JSON" "${FAILURES[@]}" <<'PY'
import json, sys
out, result, tests_raw, *failures = sys.argv[1:]
try:
    tests = json.loads(tests_raw)
except ValueError:
    tests = {}
summary = {
    "tier": "gate",
    "result": result,
    "tests": {k: tests.get(k) for k in ("totalTestCount", "passedTests", "failedTests", "skippedTests")},
    "failures": failures,
}
json.dump(summary, open(f"{out}/summary.json", "w"), indent=2)
lines = [f"# ClipBoard audit: gate — {result}", ""]
t = summary["tests"]
lines.append(f"- Tests: {t['passedTests']} passed, {t['failedTests']} failed, {t['skippedTests']} skipped (of {t['totalTestCount']})")
lines.append("- Failures: " + ("none" if not failures else ""))
lines += [f"  - {f}" for f in failures]
lines += ["", "## Coverage", "", "```", open(f"{out}/coverage.txt").read().rstrip() if __import__("os").path.exists(f"{out}/coverage.txt") else "n/a", "```"]
open(f"{out}/report.md", "w").write("\n".join(lines) + "\n")
PY

echo ""
echo "▸ Result: $RESULT  (report: $OUT/report.md)"
for f in "${FAILURES[@]}"; do echo "  ✗ $f"; done
[[ "$RESULT" == "PASS" ]]
