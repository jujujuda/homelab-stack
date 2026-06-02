#!/usr/bin/env bash
# =============================================================================
# HomeLab Stack — Health Check Waiter for CI
# Waits for services to become healthy before proceeding with tests
# Usage: source tests/lib/wait-healthy.sh
# =============================================================================

# Default timeouts (can be overridden)
DEFAULT_INTERVAL="${HEALTH_INTERVAL:-10}"
DEFAULT_TIMEOUT="${HEALTH_TIMEOUT:-300}"
DEFAULT_START_PERIOD="${HEALTH_START_PERIOD:-60}"

# Log with coloring
_health_log() {
  local level="$1"; shift
  echo -e "[$level] $*"
}

# Wait for a Docker container to be healthy
wait_container_healthy() {
  local container="$1"
  local timeout="${2:-$DEFAULT_TIMEOUT}"
  local start_period="${3:-$DEFAULT_START_PERIOD}"
  local interval="${4:-$DEFAULT_INTERVAL}"

  local elapsed=0
  local check_count=0

  # First check: wait for start_period (grace period for containers starting up)
  _health_log "INFO" "Waiting for $container to start (up to ${start_period}s)..."
  while [[ $elapsed -lt $start_period ]]; do
    if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
      break
    fi
    sleep 2
    ((elapsed += 2))
  done

  if ! docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
    _health_log "ERROR" "$container is not running"
    return 1
  fi

  # Wait for healthy status
  _health_log "INFO" "Waiting for $container to be healthy (timeout: ${timeout}s)..."
  elapsed=0
  while [[ $elapsed -lt $timeout ]]; do
    local status
    status=$(docker inspect --format '{{.State.Health.Status}}' "$container" 2>/dev/null || echo "no-healthcheck")

    if [[ "$status" == "healthy" ]]; then
      _health_log "INFO" "$container is healthy"
      return 0
    fi

    if [[ "$status" == "unhealthy" ]]; then
      local logs
      logs=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Log}}{{end}}' "$container" 2>/dev/null | tail -3 || echo "no logs")
      _health_log "ERROR" "$container is unhealthy: $logs"
      return 1
    fi

    # Also check if container is running at all
    if ! docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
      _health_log "ERROR" "$container stopped running"
      return 1
    fi

    sleep $interval
    ((elapsed += interval))
    ((check_count++))
    if [[ $((check_count % 6)) -eq 0 ]]; then
      _health_log "INFO" "$container still waiting... (${elapsed}s)"
    fi
  done

  _health_log "ERROR" "$container did not become healthy within ${timeout}s"
  return 1
}

# Wait for multiple containers
wait_all_healthy() {
  local containers=("$@")
  local failed=0

  for container in "${containers[@]}"; do
    if ! wait_container_healthy "$container"; then
      ((failed++))
    fi
  done

  return $failed
}

# Wait for HTTP endpoint to be ready
wait_http_ready() {
  local url="$1"
  local timeout="${2:-60}"
  local interval="${3:-5}"

  local elapsed=0
  _health_log "INFO" "Waiting for HTTP endpoint: $url (timeout: ${timeout}s)..."

  while [[ $elapsed -lt $timeout ]]; do
    local code
    code=$(curl -sf -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 10 "$url" 2>/dev/null || echo "000")

    if [[ "$code" =~ ^[23] ]]; then
      _health_log "INFO" "HTTP endpoint $url is ready (HTTP $code)"
      return 0
    fi

    sleep $interval
    ((elapsed += interval))
  done

  _health_log "ERROR" "HTTP endpoint $url not ready within ${timeout}s"
  return 1
}

# Wait for port to be open
wait_port_open() {
  local host="$1"; local port="$2"
  local timeout="${3:-30}"

  local elapsed=0
  _health_log "INFO" "Waiting for $host:$port to be open (timeout: ${timeout}s)..."

  while [[ $elapsed -lt $timeout ]]; do
    if nc -z -w2 "$host" "$port" 2>/dev/null; then
      _health_log "INFO" "$host:$port is open"
      return 0
    fi
    sleep 2
    ((elapsed += 2))
  done

  _health_log "ERROR" "$host:$port not open within ${timeout}s"
  return 1
}

# Generic waiter with custom command
wait_for() {
  local name="$1"; local cmd="$2"; local timeout="${3:-60}"

  local elapsed=0
  _health_log "INFO" "Waiting for $name (timeout: ${timeout}s)..."

  while [[ $elapsed -lt $timeout ]]; do
    if eval "$cmd" >/dev/null 2>&1; then
      _health_log "INFO" "$name is ready"
      return 0
    fi
    sleep 5
    ((elapsed += 5))
  done

  _health_log "ERROR" "$name not ready within ${timeout}s"
  return 1
}

export -f wait_container_healthy wait_all_healthy wait_http_ready wait_port_open wait_for 2>/dev/null || true
