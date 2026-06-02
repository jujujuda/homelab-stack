#!/usr/bin/env bash
# =============================================================================
# HomeLab Stack — Test Reporting Library
# Colored terminal output + JSON reporting for CI
# Usage: source tests/lib/report.sh
# =============================================================================

# Colors
export RESET='\033[0m'
export BOLD='\033[1m'
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export CYAN='\033[0;36m'
export MAGENTA='\033[0;35m'

# State
_REPORT_TESTS_RUN=0
_REPORT_TESTS_PASSED=0
_REPORT_TESTS_FAILED=0
_REPORT_TESTS_SKIPPED=0
_REPORT_JSON_OUTPUT=""
_REPORT_START_TIME=""

# Initialize report
report_init() {
  _REPORT_START_TIME=$(date +%s)
  _REPORT_TESTS_RUN=0
  _REPORT_TESTS_PASSED=0
  _REPORT_TESTS_FAILED=0
  _REPORT_TESTS_SKIPPED=0
  _REPORT_JSON_OUTPUT="{\"tests\":[],\"summary\":{\"passed\":0,\"failed\":0,\"skipped\":0,\"run\":0}}"
}

# Log functions
report_info()    { echo -e "${GREEN}[INFO]${RESET} $*"; }
report_warn()    { echo -e "${YELLOW}[WARN]${RESET} $*"; }
report_error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
report_debug()   { [[ "${REPORT_DEBUG:-0}" == "1" ]] && echo -e "${CYAN}[DEBUG]${RESET} $*" || true; }

# Test result logging
report_pass() {
  local name="$1"; local msg="${2:-}"
  ((_REPORT_TESTS_RUN++)); ((_REPORT_TESTS_PASSED++))
  echo -e "  ${GREEN}✓${RESET} ${BOLD}$name${RESET}${msg:+, $msg}"
  _report_json_add_result "pass" "$name" "$msg"
}

report_fail() {
  local name="$1"; local msg="${2:-}"; local details="${3:-}"
  ((_REPORT_TESTS_RUN++)); ((_REPORT_TESTS_FAILED++))
  echo -e "  ${RED}✗${RESET} ${BOLD}$name${RESET}${msg:+, $msg}"
  [[ -n "$details" ]] && echo -e "      ${RED}$details${RESET}" || true
  _report_json_add_result "fail" "$name" "$msg" "$details"
}

report_skip() {
  local name="$1"; local reason="${2:-}"
  ((_REPORT_TESTS_SKIPPED++))
  echo -e "  ${YELLOW}~${RESET} ${BOLD}$name${RESET}${reason:+, $reason} ${YELLOW}(skipped)${RESET}"
  _report_json_add_result "skip" "$name" "$reason"
}

# Group header
report_group() {
  local title="$1"
  echo ""
  echo -e "${BLUE}${BOLD}[$title]${RESET}"
}

# Internal JSON helper
_report_json_add_result() {
  local status="$1"; local name="$2"; local msg="${3:-}"; local details="${4:-}"
  local escaped_name=$(printf '%s' "$name" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))' 2>/dev/null | tr -d '"')
  local escaped_msg=$(printf '%s' "$msg" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))' 2>/dev/null | tr -d '"')
  local escaped_details=$(printf '%s' "$details" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))' 2>/dev/null | tr -d '"')

  local result="{\"status\":\"$status\",\"name\":\"$escaped_name\""
  [[ -n "$msg" ]] && result="$result,\"message\":\"$escaped_msg\""
  [[ -n "$details" ]] && result="$result,\"details\":\"$escaped_details\""
  result="$result,\"timestamp\":\"$(date -Iseconds)\"}"

  # Append to JSON
  _REPORT_JSON_OUTPUT=$(python3 -c "
import sys, json
data = json.loads('''${_REPORT_JSON_OUTPUT}''')
data['tests'].append(json.loads('''$result'''))
print(json.dumps(data))
" 2>/dev/null || echo "$_REPORT_JSON_OUTPUT")
}

# Print summary
report_summary() {
  local exit_code="${1:-0}"
  local duration=$(( $(date +%s) - ${_REPORT_START_TIME:-$(date +%s)} ))

  echo ""
  echo -e "${BOLD}========================================${RESET}"
  echo -e "  Test Results"
  echo -e "  ${GREEN}✓ $_REPORT_TESTS_PASSED passed${RESET}"
  echo -e "  ${RED}✗ $_REPORT_TESTS_FAILED failed${RESET}"
  echo -e "  ${YELLOW}~ $_REPORT_TESTS_SKIPPED skipped${RESET}"
  echo -e "  Duration: ${duration}s"
  echo -e "${BOLD}========================================${RESET}"

  # JSON summary
  if [[ "${REPORT_JSON:-0}" == "1" ]]; then
    python3 -c "
import sys, json
data = json.loads('''${_REPORT_JSON_OUTPUT}''')
data['summary'] = {
    'passed': $_REPORT_TESTS_PASSED,
    'failed': $_REPORT_TESTS_FAILED,
    'skipped': $_REPORT_TESTS_SKIPPED,
    'run': $_REPORT_TESTS_RUN,
    'duration_seconds': $duration,
    'exit_code': $exit_code
}
print(json.dumps(data, indent=2))
" 2>/dev/null || echo "$_REPORT_JSON_OUTPUT"
  fi

  return $exit_code
}

# Export for subshells
export -f report_pass report_fail report_skip report_info report_warn report_error report_group report_debug 2>/dev/null || true
