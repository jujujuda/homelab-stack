#!/usr/bin/env bash
# =============================================================================
# HomeLab Stack — Dashboard Stack Tests
# Tests Homarr and Homepage dashboard services
# Usage: ./tests/dashboard.test.sh [--skip-health]
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TESTS_DIR="$BASE_DIR/tests"

source "$TESTS_DIR/lib/report.sh"
source "$TESTS_DIR/lib/assert.sh"

DOMAIN="${DOMAIN:-localhost}"
HOMARR_DOMAIN="${HOMARR_DOMAIN:-dashboard.${DOMAIN}}"
HOMEPAGE_DOMAIN="${HOMEPAGE_DOMAIN:-home.${DOMAIN}}"
SKIP_HEALTH="${SKIP_HEALTH:-0}"

report_init

main() {
  echo -e "${BOLD}Dashboard Stack Tests${RESET}"
  echo "========================="

  if [[ "$SKIP_HEALTH" != "1" ]]; then
    source "$TESTS_DIR/lib/wait-healthy.sh"
  fi

  test_homarr
  test_homepage

  report_summary $?
}

test_homarr() {
  report_group "Homarr"

  assert_container_running "homarr" "Homarr container is running"
  assert_container_healthy "homarr" "Homarr container is healthy"

  local url="https://${HOMARR_DOMAIN}/"
  assert_http_status "$url" 200 "Homarr root accessible"
  assert_http_body_contains "$url" "homarr" "Homarr page contains 'homarr'" 2>/dev/null || true
}

test_homepage() {
  report_group "Homepage"

  assert_container_running "homepage" "Homepage container is running"
  assert_container_healthy "homepage" "Homepage container is healthy"

  local url="https://${HOMEPAGE_DOMAIN}/"
  assert_http_status "$url" 200 "Homepage root accessible"
}

main "$@"
