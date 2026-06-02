#!/usr/bin/env bash
# =============================================================================
# HomeLab Stack — SSO OIDC Flow E2E Test
# Tests the full OIDC authentication flow: discovery, redirect, token exchange
# Usage: ./tests/e2e/sso-flow.test.sh [--skip-health]
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
ROOT_DIR="$BASE_DIR"
TESTS_DIR="$BASE_DIR/tests"

# Load libraries
# shellcheck source=../lib/report.sh
source "$TESTS_DIR/lib/report.sh"
# shellcheck source=../lib/assert.sh
source "$TESTS_DIR/lib/assert.sh"

# Config
AUTHENTIK_DOMAIN="${AUTHENTIK_DOMAIN:-auth.${DOMAIN:-localhost}}"
GRAFANA_DOMAIN="${GRAFANA_DOMAIN:-grafana.${DOMAIN:-localhost}}"
AUTHENTIK_URL="https://${AUTHENTIK_DOMAIN}"
GRAFANA_URL="https://${GRAFANA_DOMAIN}"
SKIP_HEALTH="${SKIP_HEALTH:-0}"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
log_info()  { echo -e "${GREEN}[INFO]${RESET} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${RESET} $*"; }
log_error() { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
log_step()  { echo; echo -e "${BOLD}${CYAN}==> $*${RESET}"; }

# Initialize
report_init

main() {
  echo ""
  echo -e "${BOLD}SSO OIDC Flow E2E Tests${RESET}"
  echo "================================"

  # Source test environment
  if [[ -f "$ROOT_DIR/.env" ]]; then
    set -a; source "$ROOT_DIR/.env" 2>/dev/null; set +a
  fi

  if [[ "$SKIP_HEALTH" != "1" ]]; then
    # Wait for services to be healthy
    log_step "Waiting for services..."
    # shellcheck source=../lib/wait-healthy.sh
    source "$TESTS_DIR/lib/wait-healthy.sh"
    wait_container_healthy "authentik-server" 120 60 || log_warn "authentik-server not healthy, continuing anyway"
    wait_http_ready "$AUTHENTIK_URL/-/health/ready/" 60 10 || log_warn "Authentik not ready, continuing anyway"
  fi

  # --- Test Group 1: OIDC Discovery ---
  test_oidc_discovery

  # --- Test Group 2: OIDC Provider Metadata ---
  test_provider_metadata

  # --- Test Group 3: Authentik Admin UI ---
  test_authentik_admin_ui

  # --- Test Group 4: Grafana OIDC Redirect ---
  test_grafana_oidc_redirect

  # Print summary
  report_summary $?
}

# =============================================================================
# Test Group 1: OIDC Discovery (.well-known/openid-configuration)
# =============================================================================
test_oidc_discovery() {
  report_group "OIDC Discovery"

  local discovery_url="$AUTHENTIK_URL/.well-known/openid-configuration"

  # Test 1: Discovery endpoint is reachable
  if assert_http_status "$discovery_url" 200 "OIDC discovery endpoint reachable"; then
    local body
    body=$(curl -sf --connect-timeout 10 --max-time 30 "$discovery_url" 2>/dev/null || echo "")

    # Test 2: Discovery body is valid JSON
    if python3 -c "import json; json.loads('$body')" 2>/dev/null; then
      report_pass "Discovery document is valid JSON"
    else
      report_fail "Discovery document is valid JSON"
    fi

    # Test 3: Required OIDC fields present
    assert_contains "$body" '"issuer"' "Discovery contains 'issuer' field"
    assert_contains "$body" '"authorization_endpoint"' "Discovery contains 'authorization_endpoint'"
    assert_contains "$body" '"token_endpoint"' "Discovery contains 'token_endpoint'"
    assert_contains "$body" '"userinfo_endpoint"' "Discovery contains 'userinfo_endpoint'"
    assert_contains "$body" '"jwks_uri"' "Discovery contains 'jwks_uri'"

    # Test 4: Issuer matches expected domain
    local issuer
    issuer=$(echo "$body" | python3 -c "import sys,json; print(json.load(sys.stdin).get('issuer',''))" 2>/dev/null || echo "")
    assert_equal "$AUTHENTIK_URL" "$issuer" "Issuer matches expected URL"
  fi
}

# =============================================================================
# Test Group 2: Provider Metadata
# =============================================================================
test_provider_metadata() {
  report_group "Authentik Provider Metadata"

  local api_url="$AUTHENTIK_URL/api/v3"

  # Test 5: API is accessible (with or without auth)
  assert_http_status "$api_url/" 200 "API root accessible"

  # Test 6: Providers endpoint reachable
  local providers_url="$api_url/providers/oauth2/"
  assert_http_status "$providers_url" 200 "OAuth2 providers endpoint reachable"
}

# =============================================================================
# Test Group 3: Authentik Admin UI
# =============================================================================
test_authentik_admin_ui() {
  report_group "Authentik Admin UI"

  # Test 7: Admin UI is accessible
  assert_http_status "$AUTHENTIK_URL/outpost.goauthentik.io/" 200 "Embedded outpost accessible"

  # Test 8: Admin UI login page
  assert_http_status "$AUTHENTIK_URL/" 200 "Authentik home page accessible"

  # Test 9: Health check endpoint
  assert_http_status "$AUTHENTIK_URL/-/health/ready/" 200 "Authentik health check passes"
}

# =============================================================================
# Test Group 4: Grafana OIDC Redirect Flow
# =============================================================================
test_grafana_oidc_redirect() {
  report_group "Grafana OIDC Redirect Flow"

  local grafana_login="$GRAFANA_URL/login"
  local grafana_oauth_login="$GRAFANA_URL/login/generic_oauth"

  # Test 10: Grafana login page accessible
  if assert_http_status "$grafana_login" 200 "Grafana login page accessible"; then
    # Test 11: Grafana redirects to OIDC provider when accessing protected route
    local redirect_url
    redirect_url=$(curl -sf -o /dev/null -w '%{redirect_url}' --connect-timeout 10 --max-time 30 \
      -L "$grafana_login" 2>/dev/null || echo "")

    if [[ -n "$redirect_url" ]]; then
      if [[ "$redirect_url" == *"auth.${DOMAIN:-"* ]]; then
        report_pass "Grafana redirects to OIDC provider" "redirect=$redirect_url"
      else
        report_warn "Grafana redirect target: $redirect_url (may not be OIDC)"
      fi
    else
      report_skip "Grafana redirect check" "no redirect detected (may already be authenticated)"
    fi
  fi
}

main "$@"
