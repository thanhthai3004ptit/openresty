#!/usr/bin/env sh
set -eu

PROJECT_ROOT="${OPENRESTY_PROJECT_ROOT:-/home/ubuntu/openresty}"
LOG_DIR="${PROJECT_ROOT}/logs"
CONTAINER_NAME="${OPENRESTY_CONTAINER_NAME:-openresty-gateway-mvp}"

mkdir -p "$LOG_DIR"

domains="${RENEWED_DOMAINS:-unknown}"
primary_domain="$(printf '%s\n' "$domains" | awk '{print $1}')"
log_file="${LOG_DIR}/${primary_domain}.cert.log"

cert_log() {
    level="$1"
    shift
    printf '%s %s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$level" "$*" >> "$log_file"
}

cert_log "INFO" "renew cert success for domains: ${domains}"

if docker exec "$CONTAINER_NAME" openresty -t >> "$log_file" 2>&1; then
    cert_log "INFO" "openresty config test success after renew"
else
    cert_log "ERROR" "openresty config test failed after renew"
    exit 1
fi

if docker exec "$CONTAINER_NAME" openresty -s reload >> "$log_file" 2>&1; then
    cert_log "INFO" "openresty reload success after renew"
else
    cert_log "ERROR" "openresty reload failed after renew"
    exit 1
fi
