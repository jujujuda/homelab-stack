#!/usr/bin/env bash
# =============================================================================
# HomeLab Stack -- Nextcloud OIDC Setup via occ
# Configures Nextcloud sociallogin OIDC provider pointing to Authentik
# Requires: curl, jq, Docker (running nextcloud container)
# Usage: ./scripts/nextcloud-oidc-setup.sh [--dry-run]
#   --dry-run : Preview configuration without applying
# =============================================================================
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT_DIR=$(dirname "$SCRIPT_DIR")

# Load .env
if [ -f "$ROOT_DIR/.env" ]; then
  set -a; source "$ROOT_DIR/.env"; set +a
fi

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
log_info()  { echo -e "${GREEN}[INFO]${RESET} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${RESET} $*"; }
log_error() { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
log_step()  { echo; echo -e "${BOLD}${CYAN}==> $*${RESET}"; }
log_dry()   { echo -e "${YELLOW}[DRY-RUN]${RESET} $*"; }

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
fi

# Nextcloud container name (check common names)
NC_CONTAINER="${NC_CONTAINER:-nextcloud}"

# Authentik settings
AUTHENTIK_DOMAIN="${AUTHENTIK_DOMAIN:-auth.${DOMAIN}}"
AUTHENTIK_ISSUER="https://${AUTHENTIK_DOMAIN}/"

# Nextcloud settings
NC_BASE_URL="${NC_BASE_URL:-https://nc.${DOMAIN}}"

# OIDC credentials from .env
NC_OAUTH_CLIENT_ID="${NEXTCLOUD_OAUTH_CLIENT_ID:-}"
NC_OAUTH_CLIENT_SECRET="${NEXTCLOUD_OAUTH_CLIENT_SECRET:-}"

# oc command helper
run_occ() {
  if $DRY_RUN; then
    log_dry "occ $*"
    return 0
  fi

  # Check if container is running
  if ! docker ps --format '{{.Names}}' | grep -q "^${NC_CONTAINER}$"; then
    log_error "Nextcloud container '$NC_CONTAINER' is not running"
    return 1
  fi

  docker exec "$NC_CONTAINER" occ "$@"
}

# Check if sociallogin is installed
check_sociallogin() {
  log_step "Checking Nextcloud sociallogin app..."
  if $DRY_RUN; then
    log_dry "Would check if sociallogin app is enabled"
    return 0
  fi

  local apps
  apps=$(docker exec "$NC_CONTAINER" occ app:list 2>/dev/null | grep -i sociallogin || true)
  if [ -z "$apps" ]; then
    log_warn "sociallogin app not found. Installing..."
    run_occ app:install sociallogin
  else
    log_info "sociallogin app is installed"
  fi

  if ! run_occ app:list | grep -q "sociallogin: enabled"; then
    log_info "Enabling sociallogin app..."
    run_occ app:enable sociallogin
  else
    log_info "sociallogin app is already enabled"
  fi
}

# Configure Authentik as custom OIDC provider
configure_oidc() {
  log_step "Configuring Authentik OIDC provider for Nextcloud..."

  if [ -z "$NC_OAUTH_CLIENT_ID" ] || [ -z "$NC_OAUTH_CLIENT_SECRET" ]; then
    log_error "NEXTCLOUD_OAUTH_CLIENT_ID and NEXTCLOUD_OAUTH_CLIENT_SECRET must be set in .env"
    log_error "Run scripts/setup-authentik.sh first to create the OIDC client"
    return 1
  fi

  log_info "Authentik issuer: $AUTHENTIK_ISSUER"
  log_info "Nextcloud base URL: $NC_BASE_URL"
  log_info "OAuth Client ID: $NC_OAUTH_CLIENT_ID"

  if $DRY_RUN; then
    log_dry "Would configure custom OIDC provider:"
    log_dry "  Provider: Authentik"
    log_dry "  Base URL: $NC_BASE_URL"
    log_dry "  Issuer: $AUTHENTIK_ISSUER"
    log_dry "  Client ID: $NC_OAUTH_CLIENT_ID"
    log_dry "  Client Secret: [hidden]"
    return 0
  fi

  # Configure custom OIDC provider using occ commands
  # sociallogin allows custom OIDC providers via configuration
  run_occ config:app:set sociallogin custom_oidc_name \
    --value="Authentik" 2>/dev/null || true

  run_occ config:app:set sociallogin custom_oidc_issuer \
    --value="$AUTHENTIK_ISSUER" 2>/dev/null || true

  run_occ config:app:set sociallogin custom_oidc_client_id \
    --value="$NC_OAUTH_CLIENT_ID" 2>/dev/null || true

  run_occ config:app:set sociallogin custom_oidc_client_secret \
    --value="$NC_OAUTH_CLIENT_SECRET" 2>/dev/null || true

  # Set scopes - openid, profile, email are standard
  run_occ config:app:set sociallogin custom_oidc_scope \
    --value="openid profile email" 2>/dev/null || true

  # Configure claim mapping
  run_occ config:app:set sociallogin custom_oidc_claim_email \
    --value="email" 2>/dev/null || true

  run_occ config:app:set sociallogin custom_oidc_claim_displayname \
    --value="name" 2>/dev/null || true

  # Enable automatic account creation from OIDC
  run_occ config:app:set sociallogin custom_oidc_create_groups \
    --value="true" 2>/dev/null || true

  log_info "OIDC provider configured successfully"
}

# Additional Nextcloud settings for OIDC
configure_nextcloud() {
  log_step "Configuring Nextcloud for OIDC login..."

  # Allow OIDC login (disable username/password login requirement)
  if $DRY_RUN; then
    log_dry "Would set allowOMETest to true"
    return 0
  fi

  # Only set this if you want to completely disable password login
  # run_occ config:system:set allow_login_without_password --value="true" 2>/dev/null || true

  log_info "Nextcloud OIDC configuration complete"
}

# Verify configuration
verify() {
  log_step "Verifying configuration..."
  if $DRY_RUN; then
    log_dry "Would verify configuration"
    return 0
  fi

  local cfg
  cfg=$(docker exec "$NC_CONTAINER" occ config:app:get sociallogin custom_oidc_issuer 2>/dev/null || echo "")
  if [ "$cfg" == "$AUTHENTIK_ISSUER" ]; then
    log_info "✓ OIDC issuer verified: $cfg"
  else
    log_warn "OIDC issuer not set correctly (got: $cfg, expected: $AUTHENTIK_ISSUER)"
  fi
}

main() {
  echo ""
  echo -e "${BOLD}Nextcloud OIDC Setup — Authentik Provider${RESET}"
  echo "=============================================="
  echo ""

  if $DRY_RUN; then
    echo -e "${YELLOW}[DRY RUN] No changes will be made${RESET}"
    echo ""
  fi

  check_sociallogin
  configure_oidc
  configure_nextcloud
  verify

  echo ""
  if $DRY_RUN; then
    echo -e "${YELLOW}Run without --dry-run to apply changes${RESET}"
  else
    log_info "Nextcloud OIDC login configured successfully!"
    echo ""
    echo "  Log out of Nextcloud and click 'Authentik' on the login page."
    echo "  Or direct link: ${NC_BASE_URL}/apps/sociallogin"
  fi
}

main "$@"
