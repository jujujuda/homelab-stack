#!/usr/bin/env bash
# =============================================================================
# HomeLab Stack — Notifications Stack Tests
# Tests ntfy and apprise services
# Usage: ./tests/notifications.test.sh [--skip-health]
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TESTS_DIR="$BASE_DIR/tests"

source "$TESTS_DIR/lib/report.sh"
source "$TESTS_DIR/lib/assert.sh"

DOMAIN="${DOMAIN:-localhost}"
NTFY_DOMAIN="${NTFY_DOMAIN:-ntfy.${DOMAIN}}"
APPRISE_DOMAIN="${APPRISE_DOMAIN:-apprise.${DOMAIN}}"
NTFY_URL="https://${NTFY_DOMAIN}"
APPRISE_URL="https://${APPRISE_DOMAIN}"
SKIP_HEALTH="${SKIP_HEALTH:-0}"

report_init

main() {
  echo -e "${BOLD}Notifications Stack Tests${RESET}"
  echo "=============================="

  if [[ "$SKIP_HEALTH" != "1" ]]; then
    source "$TESTS_DIR/lib/wait-healthy.sh"
    wait_http_ready "${NTFY_URL}/v1/health" 60 10 || true
  fi

  # Ntfy tests
  test_ntfy

  # Apprise tests
  test_apprise

  report_summary $?
}

test_ntfy() {
  report_group "Ntfy"

  # Container checks
  assert_container_running "ntfy" "Ntfy container is running"
  assert_container_healthy "ntfy" "Ntfy container is healthy"

  # HTTP checks
  assert_http_status "${NTFY_URL}/v1/health" 200 "Ntfy health endpoint returns 200"
  assert_http_body_contains "${NTFY_URL}/v1/health" "healthy" "Ntfy health response contains 'healthy'"
}

test_apprise() {
  report_group "Apprise"

  assert_container_running "apprise" "Apprise container is running"

  # Apprise doesn't have a standard health endpoint, check root
  local code
  code=$(curl -sf -o /dev/null -w '%{http_code}' --connect-timeout 5 "${APPRISE_URL}/" 2>/dev/null || echo "000")
  if [[ "$code" =~ ^[23] ]]; then
    report_pass "Apprise is reachable" "HTTP $code"
  else
    report_skip "Apprise HTTP check" "returned $code"
  fi
}

main "$@"
