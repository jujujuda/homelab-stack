#!/usr/bin/env bash
# =============================================================================
# HomeLab Stack — Assertion Library (15+ functions)
# Provides reusable assertions for test scripts
# Usage: source tests/lib/assert.sh
# =============================================================================

# Track test results for summary
ASSERT_PASSED=0
ASSERT_FAILED=0
ASSERT_SKIPPED=0

# --- Core assertion engine ---
_assert_result() {
  local status="$1"; local msg="$2"; local details="${3:-}"
  ((ASSERT_PASSED++))
  echo -e "  ${GREEN}✓${RESET} $msg"
  return 0
}

_assert_fail() {
  local msg="$1"; local details="${2:-}"
  ((ASSERT_FAILED++))
  echo -e "  ${RED}✗${RESET} $msg"
  [[ -n "$details" ]] && echo -e "      ${RED}Details: $details${RESET}" || true
  return 1
}

# ---------------------------------------------------------------------------
# 1. assert_equal - Assert two values are equal
# ---------------------------------------------------------------------------
assert_equal() {
  local expected="$1"; local actual="$2"; local msg="${3:-Values should be equal}"
  if [[ "$expected" == "$actual" ]]; then
    _assert_result "pass" "$msg" "expected='$expected', got='$actual'"
    return 0
  else
    _assert_fail "$msg" "expected='$expected', got='$actual'"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# 2. assert_not_equal - Assert two values are different
# ---------------------------------------------------------------------------
assert_not_equal() {
  local expected="$1"; local actual="$2"; local msg="${3:-Values should differ}"
  if [[ "$expected" != "$actual" ]]; then
    _assert_result "pass" "$msg" "value='$actual'"
    return 0
  else
    _assert_fail "$msg" "values should differ but both are '$expected'"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# 3. assert_contains - Assert string contains substring
# ---------------------------------------------------------------------------
assert_contains() {
  local haystack="$1"; local needle="$2"; local msg="${3:-String should contain substring}"
  if [[ "$haystack" == *"$needle"* ]]; then
    _assert_result "pass" "$msg" "haystack contains '$needle'"
    return 0
  else
    _assert_fail "$msg" "haystack='$haystack' does not contain '$needle'"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# 4. assert_not_contains - Assert string does not contain substring
# ---------------------------------------------------------------------------
assert_not_contains() {
  local haystack="$1"; local needle="$2"; local msg="${3:-String should not contain substring}"
  if [[ "$haystack" != *"$needle"* ]]; then
    _assert_result "pass" "$msg" "haystack does not contain '$needle'"
    return 0
  else
    _assert_fail "$msg" "haystack='$haystack' should not contain '$needle'"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# 5. assert_empty - Assert value is empty
# ---------------------------------------------------------------------------
assert_empty() {
  local value="$1"; local msg="${2:-Value should be empty}"
  if [[ -z "$value" ]]; then
    _assert_result "pass" "$msg" "value is empty"
    return 0
  else
    _assert_fail "$msg" "value is not empty: '$value'"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# 6. assert_not_empty - Assert value is not empty
# ---------------------------------------------------------------------------
assert_not_empty() {
  local value="$1"; local msg="${2:-Value should not be empty}"
  if [[ -n "$value" ]]; then
    _assert_result "pass" "$msg" "value='$value'"
    return 0
  else
    _assert_fail "$msg" "value is empty"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# 7. assert_file_exists - Assert file exists
# ---------------------------------------------------------------------------
assert_file_exists() {
  local file="$1"; local msg="${2:-File should exist}"
  if [[ -f "$file" ]]; then
    _assert_result "pass" "$msg" "file='$file'"
    return 0
  else
    _assert_fail "$msg" "file does not exist: '$file'"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# 8. assert_file_not_exists - Assert file does not exist
# ---------------------------------------------------------------------------
assert_file_not_exists() {
  local file="$1"; local msg="${2:-File should not exist}"
  if [[ ! -f "$file" ]]; then
    _assert_result "pass" "$msg" "file does not exist"
    return 0
  else
    _assert_fail "$msg" "file exists: '$file'"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# 9. assert_dir_exists - Assert directory exists
# ---------------------------------------------------------------------------
assert_dir_exists() {
  local dir="$1"; local msg="${2:-Directory should exist}"
  if [[ -d "$dir" ]]; then
    _assert_result "pass" "$msg" "dir='$dir'"
    return 0
  else
    _assert_fail "$msg" "directory does not exist: '$dir'"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# 10. assert_http_status - Assert HTTP response status code
# ---------------------------------------------------------------------------
assert_http_status() {
  local url="$1"; local expected="${2:-200}"; local msg="${3:-HTTP request should succeed}"
  local code
  code=$(curl -sf -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 30 "$url" 2>/dev/null || echo "000")
  if [[ "$code" == "$expected" ]] || [[ "$code" =~ ^${expected:0:1}[0-9]$ ]]; then
    _assert_result "pass" "$msg" "HTTP $code == expected $expected"
    return 0
  else
    _assert_fail "$msg" "HTTP $code != expected $expected (url=$url)"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# 11. assert_http_body_contains - Assert HTTP response body contains text
# ---------------------------------------------------------------------------
assert_http_body_contains() {
  local url="$1"; local expected="$2"; local msg="${3:-HTTP body should contain text}"
  local body
  body=$(curl -sf --connect-timeout 10 --max-time 30 "$url" 2>/dev/null || echo "")
  if [[ "$body" == *"$expected"* ]]; then
    _assert_result "pass" "$msg" "body contains '$expected'"
    return 0
  else
    _assert_fail "$msg" "body does not contain '$expected' (url=$url)"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# 12. assert_container_running - Assert Docker container is running
# ---------------------------------------------------------------------------
assert_container_running() {
  local container="$1"; local msg="${2:-Container should be running}"
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${container}$"; then
    local health
    health=$(docker inspect --format '{{.State.Health.Status}}' "$container" 2>/dev/null || echo "no-healthcheck")
    _assert_result "pass" "$msg" "container=$container health=$health"
    return 0
  else
    _assert_fail "$msg" "container '$container' is not running"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# 13. assert_container_healthy - Assert Docker container is healthy
# ---------------------------------------------------------------------------
assert_container_healthy() {
  local container="$1"; local msg="${2:-Container should be healthy}"
  local status
  status=$(docker inspect --format '{{.State.Health.Status}}' "$container" 2>/dev/null || echo "unknown")
  if [[ "$status" == "healthy" ]]; then
    _assert_result "pass" "$msg" "container=$container status=healthy"
    return 0
  else
    _assert_fail "$msg" "container '$container' status=$status (expected healthy)"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# 14. assert_port_open - Assert TCP port is open
# ---------------------------------------------------------------------------
assert_port_open() {
  local host="$1"; local port="$2"; local msg="${3:-Port should be open}"
  if nc -z -w5 "$host" "$port" 2>/dev/null; then
    _assert_result "pass" "$msg" "$host:$port is open"
    return 0
  else
    _assert_fail "$msg" "$host:$port is not reachable"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# 15. assert_regex - Assert value matches regex pattern
# ---------------------------------------------------------------------------
assert_regex() {
  local pattern="$1"; local value="$2"; local msg="${3:-Value should match regex}"
  if [[ "$value" =~ $pattern ]]; then
    _assert_result "pass" "$msg" "value='$value' matches pattern='$pattern'"
    return 0
  else
    _assert_fail "$msg" "value='$value' does not match pattern='$pattern'"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# 16. assert_docker_image_exists - Assert Docker image is present locally
# ---------------------------------------------------------------------------
assert_docker_image_exists() {
  local image="$1"; local msg="${2:-Docker image should exist locally}"
  if docker image inspect "$image" >/dev/null 2>&1; then
    _assert_result "pass" "$msg" "image=$image"
    return 0
  else
    _assert_fail "$msg" "image not found locally: '$image'"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# 17. assert_env_var_set - Assert environment variable is set and non-empty
# ---------------------------------------------------------------------------
assert_env_var_set() {
  local var_name="$1"; local msg="${2:-Environment variable should be set}"
  local value
  eval "value=\${$var_name:-}"
  if [[ -n "$value" ]]; then
    _assert_result "pass" "$msg" "${var_name}='$value'"
    return 0
  else
    _assert_fail "$msg" "environment variable '$var_name' is not set or empty"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# 18. assert_json_field - Assert JSON field equals expected value
# ---------------------------------------------------------------------------
assert_json_field() {
  local json="$1"; local field="$2"; local expected="$3"; local msg="${4:-JSON field should match}"
  local actual
  actual=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('$field', ''))" 2>/dev/null || echo "")
  if [[ "$actual" == "$expected" ]]; then
    _assert_result "pass" "$msg" "field '$field'='$actual'"
    return 0
  else
    _assert_fail "$msg" "field '$field'='$actual' (expected '$expected')"
    return 1
  fi
}

# Summary
assert_summary() {
  local failed=$((ASSERT_FAILED))
  echo ""
  echo "Assertions: ${GREEN}${ASSERT_PASSED} passed${RESET} | ${RED}${failed} failed${RESET} | ${YELLOW}${ASSERT_SKIPPED} skipped${RESET}"
  return $failed
}

export -f assert_equal assert_not_equal assert_contains assert_not_contains \
  assert_empty assert_not_empty assert_file_exists assert_file_not_exists \
  assert_dir_exists assert_http_status assert_http_body_contains \
  assert_container_running assert_container_healthy assert_port_open \
  assert_regex assert_docker_image_exists assert_env_var_set assert_json_field \
  assert_summary 2>/dev/null || true
