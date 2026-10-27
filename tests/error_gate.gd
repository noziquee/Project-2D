class_name ErrorGate
extends Logger
## Watches every error the engine or a script logs while the smoke suite runs (H4.4), so a NEW error turns the run red.
##
## A logged error is fine when
##   1. the running test declared it (expect(pattern, count): the test provokes it on purpose), or
##   2. it is in the baseline file tests/expected_errors.txt (the deliberate negative tests that existed when the gate
##      was introduced; recorded by running the suite once with `--record-errors`).
## Anything else is "unexpected" and fails the run. A declared error that does not happen also fails: the test no
## longer exercises what it claims to.
##
## Warnings (push_warning) are counted but never gated. Leaks reported by the engine at shutdown come after the script
## ends and are reported by tools/run_checks.sh instead.
##
## handle_error() holds all the logic and takes a plain message, so the gate itself is testable without logging.

## Set while the suite tests the gate itself, so its probes are not mistaken for real errors.
var suspended := false
## True once a baseline exists; until then nothing is gated (the first run only records).
var armed := false
## normalized message -> true
var baseline: Dictionary = {}
## normalized message -> how many times it was logged, for every error seen.
var observed: Dictionary = {}
## normalized message -> count, for errors that were neither declared nor in the baseline.
var unexpected: Dictionary = {}
var warnings_seen := 0

## Each: {"pattern": String, "count": int (-1 = at least once), "seen": int}
var _expectations: Array = []
var _mutex := Mutex.new()

## Collapses long numbers (instance ids, addresses) so the same error compares equal between runs.
static func normalize(text: String) -> String:
	var regex := RegEx.new()
	regex.compile("\\d{4,}")
	return " ".join(regex.sub(text, "#", true).split(" ", false)).strip_edges()

## Loads the baseline. Returns true (and arms the gate) when the file exists.
func load_baseline(path: String) -> bool:
	baseline.clear()
	armed = false
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	while not file.eof_reached():
		var line := file.get_line()
		if line.strip_edges() == "" or line.begins_with("#"):
			continue
		var parts := line.split("\t", true, 1)
		baseline[parts[1] if parts.size() == 2 else parts[0]] = true
	armed = true
	return true

## Writes every distinct error seen as a baseline: "<times seen>\t<message>", one per line, sorted.
func save_baseline(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_line("# Errors the smoke suite is allowed to log: the deliberate negative tests. One per line: <times seen>\t<message>.")
	file.store_line("# Regenerate with: tools/run_checks.sh --record-errors   (review the diff before committing it).")
	var messages := observed.keys()
	messages.sort()
	for message in messages:
		file.store_line("%d\t%s" % [observed[message], message])
	return true

## The running test declares an error it provokes on purpose. `pattern` is a substring of the message; `count` is how
## many times it must happen (-1 = at least once).
func expect(pattern: String, count: int = -1) -> void:
	_mutex.lock()
	_expectations.append({"pattern": pattern, "count": count, "seen": 0})
	_mutex.unlock()

## Declarations that were not met (never seen, or seen a different number of times), as readable lines. Clears them.
func take_unmet_expectations() -> Array[String]:
	_mutex.lock()
	var unmet: Array[String] = []
	for entry in _expectations:
		var count: int = entry["count"]
		var seen: int = entry["seen"]
		if count < 0 and seen == 0:
			unmet.append("expected an error containing '%s' but none was logged" % entry["pattern"])
		elif count >= 0 and seen != count:
			unmet.append("expected %d error(s) containing '%s' but %d were logged" % [count, entry["pattern"], seen])
	_expectations.clear()
	_mutex.unlock()
	return unmet

## The whole decision for one logged error message.
func handle_error(message: String) -> void:
	if suspended:
		return
	var normalized := normalize(message)
	_mutex.lock()
	observed[normalized] = int(observed.get(normalized, 0)) + 1
	var declared := false
	for entry in _expectations:
		if normalized.contains(entry["pattern"]):
			entry["seen"] = int(entry["seen"]) + 1
			declared = true
			break
	if not declared and not baseline.has(normalized):
		unexpected[normalized] = int(unexpected.get(normalized, 0)) + 1
	_mutex.unlock()

## One line per distinct unexpected error.
func unexpected_report() -> Array[String]:
	var lines: Array[String] = []
	for message in unexpected:
		lines.append("UNEXPECTED ERROR x%d: %s" % [unexpected[message], message])
	return lines

func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type == Logger.ERROR_TYPE_WARNING:
		warnings_seen += 1
		return
	handle_error((code + " " + rationale).strip_edges())
