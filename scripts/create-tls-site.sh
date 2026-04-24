#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE_FILE="${PROJECT_ROOT}/conf/templates/tls-site.conf.template"
CONF_DIR="${PROJECT_ROOT}/conf/conf.d"
SECRET_FILE="${PROJECT_ROOT}/.secrets/certbot/cloudflare.ini"
CONTAINER_NAME="${OPENRESTY_CONTAINER_NAME:-openresty-gateway-mvp}"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

prompt() {
    local label="$1"
    local default_value="${2:-}"
    local value

    if [ -n "$default_value" ]; then
        read -r -p "${label} [${default_value}]: " value
        printf '%s' "${value:-$default_value}"
    else
        read -r -p "${label}: " value
        printf '%s' "$value"
    fi
}

prompt_yes_no() {
    local label="$1"
    local default_value="${2:-n}"
    local value

    read -r -p "${label} [${default_value}]: " value
    value="${value:-$default_value}"

    case "$value" in
        y|Y|yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}

escape_sed_replacement() {
    printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Missing command: $1"
}

validate_domain() {
    local domain="$1"
    [[ "$domain" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$ ]] || fail "Invalid domain: ${domain}"
    [[ "$domain" == *.* ]] || fail "Domain must contain a dot: ${domain}"
}

validate_number() {
    local name="$1"
    local value="$2"
    [[ "$value" =~ ^[0-9]+$ ]] || fail "${name} must be a number"
}

render_config() {
    local target_file="$1"
    local domain="$2"
    local listen_port="$3"
    local upstream_url="$4"
    local upstream_host="$5"

    cp "$TEMPLATE_FILE" "$target_file"
    sed -i \
        -e "s/__DOMAIN__/$(escape_sed_replacement "$domain")/g" \
        -e "s/__LISTEN_PORT__/$(escape_sed_replacement "$listen_port")/g" \
        -e "s/__UPSTREAM_URL__/$(escape_sed_replacement "$upstream_url")/g" \
        -e "s/__UPSTREAM_HOST__/$(escape_sed_replacement "$upstream_host")/g" \
        "$target_file"
}

issue_cert() {
    local domain="$1"
    local email="$2"

    [ -f "$SECRET_FILE" ] || fail "Missing Cloudflare credential file: ${SECRET_FILE}. Copy .secrets/certbot/cloudflare.ini.example and fill the token."
    chmod 600 "$SECRET_FILE"

    if [ -f "/etc/letsencrypt/live/${domain}/fullchain.pem" ]; then
        if ! prompt_yes_no "Certificate already exists for ${domain}. Re-issue it?" "n"; then
            printf 'Skip certbot because certificate already exists.\n'
            return 0
        fi
    fi

    sudo certbot certonly \
        --dns-cloudflare \
        --dns-cloudflare-credentials "$SECRET_FILE" \
        --non-interactive \
        --agree-tos \
        --email "$email" \
        -d "$domain"
}

main() {
    require_command certbot
    require_command docker
    require_command sed

    [ -f "$TEMPLATE_FILE" ] || fail "Missing template: ${TEMPLATE_FILE}"
    mkdir -p "$CONF_DIR"

    local domain
    local email
    local listen_port
    local upstream_url
    local upstream_host
    local target_file
    local tmp_file
    local backup_file=""

    domain="$(prompt "Domain *" "")"
    validate_domain "$domain"

    email="$(prompt "Let's Encrypt email *" "")"
    [ -n "$email" ] || fail "Email is required for certbot registration"

    listen_port="$(prompt "Container listen port *" "8443")"
    validate_number "Container listen port" "$listen_port"

    upstream_url="$(prompt "Upstream URL *" "http://host.docker.internal:9001")"
    [ -n "$upstream_url" ] || fail "Upstream URL is required"

    upstream_host="$(prompt "Upstream Host header" "$domain")"
    if [ -z "$upstream_host" ]; then
        upstream_host='$host'
    fi

    target_file="${CONF_DIR}/${domain}.conf"
    tmp_file="$(mktemp "/tmp/${domain}.XXXXXX.conf")"

    render_config "$tmp_file" "$domain" "$listen_port" "$upstream_url" "$upstream_host"

    if [ -f "$target_file" ]; then
        if ! prompt_yes_no "Config ${target_file} already exists. Overwrite?" "n"; then
            rm -f "$tmp_file"
            fail "Stopped without overwriting existing config"
        fi
        backup_file="${target_file}.backup.$(date +%Y%m%d%H%M%S)"
    fi

    issue_cert "$domain" "$email"

    if [ -n "$backup_file" ]; then
        cp "$target_file" "$backup_file"
    fi
    mv "$tmp_file" "$target_file"
    printf 'Created config: %s\n' "$target_file"

    printf 'Testing OpenResty config in container %s...\n' "$CONTAINER_NAME"
    if ! docker exec "$CONTAINER_NAME" openresty -t; then
        printf 'OpenResty config test failed. Keeping generated config for manual fix: %s\n' "$target_file" >&2
        if [ -n "$backup_file" ] && [ -f "$backup_file" ]; then
            mv "$backup_file" "$target_file"
            printf 'Restored previous config from backup: %s\n' "$backup_file" >&2
        else
            rm -f "$target_file"
            printf 'Removed generated config so current OpenResty config remains usable.\n' >&2
        fi
        exit 1
    fi

    if [ -n "$backup_file" ]; then
        rm -f "$backup_file"
    fi

    printf 'Reloading OpenResty...\n'
    docker exec "$CONTAINER_NAME" openresty -s reload
    printf 'Done. Site %s is configured and OpenResty was reloaded.\n' "$domain"
}

main "$@"
