#!/usr/bin/env bash
# =============================================================================
# HomeLab Stack -- Authentik SSO Setup Script
# Creates OIDC providers for Grafana, Gitea, Outline, Nextcloud, OpenWebUI, Portainer
# Requires: curl, jq
# Usage: ./scripts/setup-authentik.sh [--dry-run]
#   --dry-run : Preview all provider configurations without creating anything
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

AUTHENTIK_URL="https://${AUTHENTIK_DOMAIN:-auth.${DOMAIN}}"
API_URL="$AUTHENTIK_URL/api/v3"
TOKEN="${AUTHENTIK_BOOTSTRAP_TOKEN:-}"

get_default_flow() {
  local designation="$1"
  curl -sf "$API_URL/flows/instances/?designation=${designation}&ordering=slug" \
    -H "$AUTH_HEADER" | jq -r '.results[0].pk'
}

get_signing_key() {
  curl -sf "$API_URL/crypto/certificatekeypairs/?has_key=true&ordering=name" \
    -H "$AUTH_HEADER" | jq -r '.results[0].pk'
}

create_oidc_provider() {
  local name="$1"
  local redirect_uri="$2"
  local client_id_var="$3"
  local client_secret_var="$4"

  if $DRY_RUN; then
    log_dry "Would create OIDC provider: $name"
    log_dry "  Redirect URI : $redirect_uri"
    log_dry "  Env var      : ${client_id_var} / ${client_secret_var}"
    return 0
  fi

  log_step "Creating OIDC provider: $name"

  local flow_pk signing_key
  flow_pk=$(get_default_flow authorize)
  signing_key=$(get_signing_key)
  local slug
  slug=$(echo "$name" | tr '[:upper:]' '[:lower:]')

  local payload
  payload=$(jq -n \
    --arg name "${name} Provider" \
    --arg flow "$flow_pk" \
    --arg uri "$redirect_uri" \
    --arg key "$signing_key" \
    '{
      name: $name,
      authorization_flow: $flow,
      client_type: "confidential",
      redirect_uris: $uri,
      sub_mode: "hashed_user_id",
      include_claims_in_id_token: true,
      signing_key: $key
    }')

  local response
  response=$(curl -sf -X POST "$API_URL/providers/oauth2/" \
    -H "$AUTH_HEADER" \
    -H "Content-Type: application/json" \
    -d "$payload")

  local provider_pk client_id client_secret
  provider_pk=$(echo "$response" | jq -r '.pk')
  client_id=$(echo "$response" | jq -r '.client_id')
  client_secret=$(echo "$response" | jq -r '.client_secret')

  log_info "  Provider PK: $provider_pk"
  log_info "  Client ID:   $client_id"

  sed -i "s|^${client_id_var}=.*|${client_id_var}=${client_id}|" "$ROOT_DIR/.env" 2>/dev/null || true
  sed -i "s|^${client_secret_var}=.*|${client_secret_var}=${client_secret}|" "$ROOT_DIR/.env" 2>/dev/null || true

  local app_payload
  app_payload=$(jq -n \
    --arg name "$name" \
    --arg slug "$slug" \
    --argjson pk "$provider_pk" \
    '{name: $name, slug: $slug, provider: $pk}')

  curl -sf -X POST "$API_URL/core/applications/" \
    -H "$AUTH_HEADER" \
    -H "Content-Type: application/json" \
    -d "$app_payload" > /dev/null

  log_info "  Application created: $name"
}

# ------------------------------------------------------------------
# Main
# ------------------------------------------------------------------

if $DRY_RUN; then
  echo ""
  echo -e "${BOLD}${YELLOW}=== DRY RUN MODE — No changes will be made ===${RESET}"
  echo ""
fi

if [ -z "$TOKEN" ] && ! $DRY_RUN; then
  log_error "AUTHENTIK_BOOTSTRAP_TOKEN is not set in .env"
  log_error "Generate it from: Authentik UI → Settings → Bearer Tokens"
  exit 1
fi

AUTH_HEADER="Authorization: Bearer $TOKEN"

if ! $DRY_RUN; then
  # ------------------------------------------------------------------
  # Wait for Authentik to be ready
  # ------------------------------------------------------------------
  log_step "Waiting for Authentik API..."
  for i in $(seq 1 30); do
    if curl -sf "$AUTHENTIK_URL/-/health/ready/" -o /dev/null; then
      log_info "Authentik is ready"
      break
    fi
    if [ "$i" -eq 30 ]; then
      log_error "Authentik did not become ready in 150s"
      exit 1
    fi
    echo -n "."
    sleep 5
  done
fi

# ------------------------------------------------------------------
# Create providers (6 total)
# ------------------------------------------------------------------
log_step "Configuring OIDC providers..."

# 1. Grafana
create_oidc_provider \
  "Grafana" \
  "https://grafana.${DOMAIN}/login/generic_oauth" \
  "GRAFANA_OAUTH_CLIENT_ID" \
  "GRAFANA_OAUTH_CLIENT_SECRET"

# 2. Gitea
create_oidc_provider \
  "Gitea" \
  "https://git.${DOMAIN}/user/oauth2/Authentik/callback" \
  "GITEA_OAUTH_CLIENT_ID" \
  "GITEA_OAUTH_CLIENT_SECRET"

# 3. Outline
create_oidc_provider \
  "Outline" \
  "https://outline.${DOMAIN}/auth/oidc.callback" \
  "OUTLINE_OAUTH_CLIENT_ID" \
  "OUTLINE_OAUTH_CLIENT_SECRET"

# 4. Nextcloud
create_oidc_provider \
  "Nextcloud" \
  "https://nc.${DOMAIN}/apps/sociallogin/custom_oidc/Authentik" \
  "NEXTCLOUD_OAUTH_CLIENT_ID" \
  "NEXTCLOUD_OAUTH_CLIENT_SECRET"

# 5. Open WebUI
create_oidc_provider \
  "OpenWebUI" \
  "https://webui.${DOMAIN}/auth" \
  "WEBUI_OAUTH_CLIENT_ID" \
  "WEBUI_OAUTH_CLIENT_SECRET"

# 6. Portainer
create_oidc_provider \
  "Portainer" \
  "https://portainer.${DOMAIN}/" \
  "PORTAINER_OAUTH_CLIENT_ID" \
  "PORTAINER_OAUTH_CLIENT_SECRET"

if $DRY_RUN; then
  echo ""
  echo -e "${BOLD}${YELLOW}=== DRY RUN COMPLETE — No providers were created ===${RESET}"
  echo ""
  echo "Run without --dry-run to create all providers."
else
  log_step "All 6 providers created. Credentials written to .env"
  log_info "Authentik OIDC issuer: $AUTHENTIK_URL/application/o/<slug>/"
fi
