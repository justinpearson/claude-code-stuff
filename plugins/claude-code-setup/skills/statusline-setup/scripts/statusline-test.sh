#!/bin/zsh
# Test harness for statusline-command.sh.
#
# Pipes representative session JSON into the status line script exactly the way
# Claude Code does (JSON on stdin), once per scenario, so you can eyeball every
# context-color band and the directory/git/plugin lines.
#
# Usage:
#   ~/.claude/statusline-test.sh           # run all scenarios
#   ~/.claude/statusline-test.sh fresh     # run one scenario by name
#
# Scenario names: fresh mid low critical empty

emulate -L zsh
SCRIPT="${0:A:h}/statusline-command.sh"

if [[ ! -x "$SCRIPT" ]]; then
  print -u2 "statusline script not executable: $SCRIPT"
  print -u2 "run: chmod +x \"$SCRIPT\""
  exit 1
fi

# Emit a session-JSON blob. Args: remaining%  cost  duration_ms  effort
sample_json() {
  local remain="$1" cost="$2" dur="$3" effort="$4"
  local used=$(( 100 - remain ))
  cat <<JSON
{
  "cwd": "$PWD",
  "session_id": "test-session-0001",
  "transcript_path": "/tmp/transcript.jsonl",
  "version": "2.1.140",
  "model": { "id": "claude-opus-4-7", "display_name": "Opus 4.7" },
  "effort": { "level": "$effort" },
  "workspace": {
    "current_dir": "$PWD",
    "project_dir": "$PWD",
    "added_dirs": []
  },
  "cost": {
    "total_cost_usd": $cost,
    "total_duration_ms": $dur,
    "total_api_duration_ms": $dur,
    "total_lines_added": 0,
    "total_lines_removed": 0
  },
  "context_window": {
    "total_input_tokens": $(( used * 2000 )),
    "total_output_tokens": 0,
    "context_window_size": 200000,
    "used_percentage": $used,
    "remaining_percentage": $remain
  },
  "output_style": { "name": "default" }
}
JSON
}

# scenario name -> "remaining cost duration_ms effort"
typeset -A SCENARIOS=(
  fresh    "100 0      0       high"
  mid      "65  0.4231 192000  high"
  low      "35  1.8800 1500000 medium"
  critical "8   4.5500 4200000 max"
  empty    "0   0.0100 1500    low"
)
# Order to run them in (associative arrays are unordered).
ORDER=(fresh mid low critical empty)

run_one() {
  local name="$1"
  local args=(${=SCENARIOS[$name]})
  print -P "%F{244}── scenario: %F{255}${name}%F{244}  (remaining=${args[1]}%  cost=\$${args[2]}  ${args[3]}ms  effort=${args[4]}) ──%f"
  sample_json "${args[1]}" "${args[2]}" "${args[3]}" "${args[4]}" | "$SCRIPT"
  print
}

if [[ -n "$1" ]]; then
  [[ -z "${SCENARIOS[$1]}" ]] && { print -u2 "unknown scenario: $1"; print -u2 "choices: $ORDER"; exit 1 }
  run_one "$1"
else
  for name in $ORDER; do run_one "$name"; done
fi
