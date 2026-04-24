#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE_FILE="${PROJECT_ROOT}/conf/templates/tls-site.conf.template"
CONF_DIR="${PROJECT_ROOT}/conf/conf.d"
SECRET_FILE="${PROJECT_ROOT}/.secrets/certbot/cloudflare.ini"
LOG_DIR="${PROJECT_ROOT}/logs"
CONTAINER_NAME="${OPENRESTY_CONTAINER_NAME:-openresty-gateway-mvp}"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

cert_log() {
    local domain="$1"
    local level="$2"
    shift 2

    mkdir -p "$LOG_DIR"
    printf '%s %s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$level" "$*" >> "${LOG_DIR}/${domain}.cert.log"
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

find_domain_configs() {
    local domain="$1"

    grep -RslE "^[[:space:]]*server_name[[:space:]]+([^;[:space:]]+[[:space:]]+)*${domain}([[:space:];]|$)" "$CONF_DIR" 2>/dev/null || true
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
    local force_reissue="${3:-n}"

    if [ ! -f "$SECRET_FILE" ]; then
        cert_log "$domain" "ERROR" "missing Cloudflare credential file: ${SECRET_FILE}"
        fail "Missing Cloudflare credential file: ${SECRET_FILE}. Copy .secrets/certbot/cloudflare.ini.example and fill the token."
    fi
    chmod 600 "$SECRET_FILE"

    if [ -f "/etc/letsencrypt/live/${domain}/fullchain.pem" ]; then
        if [ "$force_reissue" != "y" ] && ! prompt_yes_no "Certificate already exists for ${domain}. Re-issue it?" "n"; then
            cert_log "$domain" "INFO" "skip gen cert because certificate already exists"
            printf 'Skip certbot because certificate already exists.\n'
            return 0
        fi
    fi

    cert_log "$domain" "INFO" "gen cert start"
    if ! sudo certbot certonly \
        --dns-cloudflare \
        --dns-cloudflare-credentials "$SECRET_FILE" \
        --non-interactive \
        --agree-tos \
        --email "$email" \
        -d "$domain"; then
        cert_log "$domain" "ERROR" "gen cert failed"
        return 1
    fi
    cert_log "$domain" "INFO" "gen cert success"
}

reload_openresty() {
    local domain="$1"

    printf 'Testing OpenResty config in container %s...\n' "$CONTAINER_NAME"
    if ! docker exec "$CONTAINER_NAME" openresty -t; then
        cert_log "$domain" "ERROR" "openresty config test failed"
        return 1
    fi
    cert_log "$domain" "INFO" "openresty config test success"

    printf 'Reloading OpenResty...\n'
    if ! docker exec "$CONTAINER_NAME" openresty -s reload; then
        cert_log "$domain" "ERROR" "openresty reload failed"
        return 1
    fi
    cert_log "$domain" "INFO" "openresty reload success"
}

create_ssl_and_config() {
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
    local existing_configs
    local tmp_file
    local backup_file=""
    local overwrite_existing="n"

    domain="$(prompt "Domain *" "")"
    validate_domain "$domain"
    cert_log "$domain" "INFO" "create tls site config start"

    target_file="${CONF_DIR}/${domain}.conf"
    existing_configs="$(find_domain_configs "$domain")"
    if [ -f "$target_file" ] || [ -n "$existing_configs" ]; then
        printf 'Domain %s already has config:\n' "$domain"
        if [ -f "$target_file" ]; then
            printf '  - %s\n' "$target_file"
        fi
        if [ -n "$existing_configs" ]; then
            printf '%s\n' "$existing_configs" | while IFS= read -r existing_file; do
                [ "$existing_file" = "$target_file" ] && continue
                printf '  - %s\n' "$existing_file"
            done
        fi

        if ! prompt_yes_no "Continue and overwrite ${target_file}?" "n"; then
            cert_log "$domain" "INFO" "stopped because domain already exists in config"
            fail "Stopped because domain already exists in config"
        fi
        overwrite_existing="y"
    fi

    email="$(prompt "Let's Encrypt email *" "")"
    [ -n "$email" ] || fail "Email is required for certbot registration"

    listen_port="$(prompt "Container listen port *" "")"
    validate_number "Container listen port" "$listen_port"

    upstream_url="$(prompt "Upstream URL *" "example: http://IP:port")"
    [ -n "$upstream_url" ] || fail "Upstream URL is required"

    upstream_host="$(prompt "Upstream Host header" "$domain")"
    if [ -z "$upstream_host" ]; then
        upstream_host='$host'
    fi

    tmp_file="$(mktemp "/tmp/${domain}.XXXXXX.conf")"

    render_config "$tmp_file" "$domain" "$listen_port" "$upstream_url" "$upstream_host"

    if [ -f "$target_file" ]; then
        if [ "$overwrite_existing" != "y" ]; then
            rm -f "$tmp_file"
            fail "Config ${target_file} already exists"
        fi
        backup_file="${target_file}.backup.$(date +%Y%m%d%H%M%S)"
    fi

    issue_cert "$domain" "$email"

    if [ -n "$backup_file" ]; then
        cp "$target_file" "$backup_file"
    fi
    mv "$tmp_file" "$target_file"
    printf 'Created config: %s\n' "$target_file"

    if ! reload_openresty "$domain"; then
        printf 'OpenResty test or reload failed. Keeping generated config for manual fix: %s\n' "$target_file" >&2
        if [ -n "$backup_file" ] && [ -f "$backup_file" ]; then
            mv "$backup_file" "$target_file"
            cert_log "$domain" "INFO" "restored previous config after failed test"
            printf 'Restored previous config from backup: %s\n' "$backup_file" >&2
        else
            rm -f "$target_file"
            cert_log "$domain" "INFO" "removed generated config after failed test"
            printf 'Removed generated config so current OpenResty config remains usable.\n' >&2
        fi
        exit 1
    fi

    if [ -n "$backup_file" ]; then
        rm -f "$backup_file"
    fi

    printf 'Done. Site %s is configured and OpenResty was reloaded.\n' "$domain"
}

renew_ssl_only() {
    require_command certbot
    require_command docker

    local domain
    local email

    domain="$(prompt "Domain *" "")"
    validate_domain "$domain"
    cert_log "$domain" "INFO" "renew ssl only start"

    if [ ! -f "/etc/letsencrypt/live/${domain}/fullchain.pem" ]; then
        cert_log "$domain" "ERROR" "cannot renew ssl only because certificate does not exist"
        fail "Certificate does not exist for ${domain}. Use option 1 to create SSL and config first."
    fi

    email="$(prompt "Let's Encrypt email *" "")"
    [ -n "$email" ] || fail "Email is required for certbot registration"

    issue_cert "$domain" "$email" "y"
    if ! reload_openresty "$domain"; then
        fail "OpenResty test or reload failed after re-issuing certificate"
    fi
    printf 'Done. Certificate for %s was re-issued and OpenResty was reloaded. Config was not changed.\n' "$domain"
}

main() {
    local choice

    printf '1) Create new SSL and config\n'
    printf '2) Re-issue SSL only, keep existing config\n'
    choice="$(prompt "Choose option *" "")"

    case "$choice" in
        1) create_ssl_and_config ;;
        2) renew_ssl_only ;;
        *) fail "Invalid option: ${choice}" ;;
    esac
}

main "$@"
