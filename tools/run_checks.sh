#!/usr/bin/env bash
# Runs the Godot import, then the headless smoke suite, and saves the full log.
# Usage:  tools/run_checks.sh                    (uses `godot` from PATH)
#         GODOT=/path/to/godot tools/run_checks.sh
#         tools/run_checks.sh --record-errors    (rewrites tests/expected_errors.txt from this run's errors; review the diff)
#         tools/run_checks.sh --only=p3,h4_rules (runs only those parts; a partial run is never the project total)
#         tools/run_checks.sh --twice            (runs the suite two times and compares every CHECK and PART line; H4.6)
#         godot --headless --path . --script res://tests/smoke_checks.gd -- --list    (prints the part names)
set -u
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.." || exit 2
mkdir -p tools/logs

TWICE=0
ARGS=()
for arg in "$@"; do
  if [ "$arg" = "--twice" ]; then TWICE=1; else ARGS+=("$arg"); fi
done

if ! command -v "$GODOT" >/dev/null 2>&1; then
  echo "Godot not found. Set GODOT=/path/to/godot (Godot 4.7.x)." >&2
  exit 2
fi

# run_suite LOGFILE: import, then the smoke suite, everything saved in LOGFILE.
run_suite() {
  {
    echo "# $("$GODOT" --version 2>&1 | head -n1)  |  $(date -Iseconds)"
    echo "## import"
    "$GODOT" --headless --import --path . 2>&1
    echo "## smoke suite"
    "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/smoke_checks.gd -- ${ARGS[@]+"${ARGS[@]}"} 2>&1
    echo "## exit code: ${PIPESTATUS[0]}"
  } > "$1"
}

STAMP="$(date +%Y-%m-%d_%H%M%S)"
LOG="tools/logs/run_${STAMP}.log"
run_suite "$LOG"

# The suite quits with 1 on failure; read the code from the last log line.
CODE="$(tail -n1 "$LOG" | sed 's/.*exit code: //')"
SUMMARY="$(grep -E '^SUMMARY ' "$LOG" | tail -n1)"
LEAK_PATTERN='ObjectDB instances leaked|resources still in use at exit|RID allocations|leaked at exit'
LEAKS="$(grep -cE "$LEAK_PATTERN" "$LOG")"
ERRORS="$(grep -v -E "$LEAK_PATTERN" "$LOG" | grep -c 'ERROR')"
UNEXPECTED="$(grep -c '^UNEXPECTED ERROR' "$LOG")"

echo "Log:      $LOG"
echo "Summary:  ${SUMMARY:-<no SUMMARY line found: the suite did not finish>}"
grep -E '^PART ' "$LOG" | sed 's/^/  /' || true
PARTIAL="$(grep -E '^PARTIAL RUN' "$LOG" | tail -n1)"
[ -n "$PARTIAL" ] && echo "$PARTIAL"
echo "ERROR lines in log: $ERRORS (the last known green run had 66, mostly deliberate negative tests)"
echo "Unexpected errors (not in tests/expected_errors.txt, not declared by a test): $UNEXPECTED"
echo "Shutdown leak lines (reported separately, not gated): $LEAKS"
grep -E '^ERROR GATE' "$LOG" || true
[ -z "$PARTIAL" ] && echo "Copy the summary line into docs/STATUS.md."

SAME=1
if [ "$TWICE" = "1" ]; then
  LOG2="tools/logs/run_${STAMP}_second.log"
  run_suite "$LOG2"
  grep -E '^(CHECK |PART )' "$LOG"  > "${LOG}.compare"
  grep -E '^(CHECK |PART )' "$LOG2" > "${LOG2}.compare"
  N="$(wc -l < "${LOG}.compare" | tr -d ' ')"
  if diff -q "${LOG}.compare" "${LOG2}.compare" >/dev/null; then
    echo "Determinism: two runs gave identical output ($N CHECK and PART lines). Second log: $LOG2"
  else
    SAME=0
    echo "Determinism: the two runs DIFFER. First lines that differ (full logs: $LOG and $LOG2):"
    diff "${LOG}.compare" "${LOG2}.compare" | head -n 20
  fi
  rm -f "${LOG}.compare" "${LOG2}.compare"
fi

[ -n "$SUMMARY" ] && [ "$CODE" = "0" ] && [ "$SAME" = "1" ] && exit 0
exit 1
