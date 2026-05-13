#!/bin/bash

# =================================================================
# Function: GOST HTTP2 Proxy - Setup, Maintenance & Management
# Supported: Ubuntu 22.04/24.04, Debian 11/12, CentOS Stream 8/9, RHEL 8/9
#
# Interactive:  sudo bash setup_gost.sh
# CLI mode:     sudo bash setup_gost.sh [install|renew|restart|renew-restart|status|uninstall]
# =================================================================

set -euo pipefail

# -- Constants -----------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
CONFIG_DIR="/etc/gost"
CONFIG_FILE="${CONFIG_DIR}/gost.env"
CERT_DIR="/etc/letsencrypt"
CONTAINER_NAME="gost"
LOG_FILE="/var/log/gost_$(date +%Y%m%d_%H%M%S).log"
RENEW_LOG="/var/log/gost_renew.log"

# -- Color output (disabled in non-interactive / cron mode) --------
if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; NC=''
fi

info()   { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()   { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()  { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
prompt() { echo -en "${CYAN}[INPUT]${NC} $*"; }
log_renew() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') [INFO]  $*" | tee -a "$RENEW_LOG"; }

# ===================================================================
#                       UTILITY FUNCTIONS
# ===================================================================

# -- Root check ----------------------------------------------------
require_root() {
    [[ $EUID -ne 0 ]] && error "Please run as root (sudo bash $0)"
}

# -- OS detection --------------------------------------------------
detect_os() {
    [[ -f /etc/os-release ]] || error "Cannot read /etc/os-release, unsupported distro"
    # shellcheck source=/dev/null
    source /etc/os-release

    VERSION_MAJOR="${VERSION_ID%%.*}"
    case "${ID}" in
        ubuntu)
            [[ "${VERSION_ID}" == "22.04" || "${VERSION_ID}" == "24.04" ]] \
                || error "Unsupported Ubuntu: ${VERSION_ID}. Supported: 22.04, 24.04"
            ;;
        debian)
            [[ "${VERSION_MAJOR}" == "11" || "${VERSION_MAJOR}" == "12" ]] \
                || error "Unsupported Debian: ${VERSION_ID}. Supported: 11, 12"
            ;;
        centos)
            [[ "${VERSION_MAJOR}" == "8" || "${VERSION_MAJOR}" == "9" ]] \
                || error "Unsupported CentOS: ${VERSION_ID}. Supported: Stream 8, 9"
            ;;
        rhel)
            [[ "${VERSION_MAJOR}" == "8" || "${VERSION_MAJOR}" == "9" ]] \
                || error "Unsupported RHEL: ${VERSION_ID}. Supported: 8, 9"
            ;;
        *)
            error "Unsupported distro: ${ID}. Supported: ubuntu, debian, centos, rhel"
            ;;
    esac

    if [[ "${ID}" =~ ^(ubuntu|debian)$ ]]; then
        PKG_MANAGER="apt"
    elif command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
    else
        PKG_MANAGER="yum"
    fi
}

# -- Check Docker --------------------------------------------------
require_docker() {
    command -v docker &>/dev/null || error "Docker is not installed. Please run install_docker.sh first."
    docker info &>/dev/null       || error "Docker daemon is not running."
}

# -- Load configuration -------------------------------------------
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error "Configuration not found: $CONFIG_FILE\nRun the install first (menu option 1)."
    fi
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
    for var in DOMAIN USER PASS PORT BIND_IP; do
        [[ -n "${!var:-}" ]] || error "Missing variable: $var in $CONFIG_FILE"
    done
    CERT="${CERT_DIR}/live/${DOMAIN}/fullchain.pem"
    KEY="${CERT_DIR}/live/${DOMAIN}/privkey.pem"
}

# -- Start GOST container (shared logic) --------------------------
start_gost_container() {
    docker run -d --name "$CONTAINER_NAME" \
        -v "${CERT_DIR}:${CERT_DIR}:ro" \
        --net=host ginuerzh/gost \
        -L "http2://${USER}:${PASS}@${BIND_IP}:${PORT}?cert=${CERT}&key=${KEY}&probe_resist=code:404"

    sleep 3
    if docker ps --format '{{.Names}}' | grep -qw "$CONTAINER_NAME"; then
        return 0
    else
        return 1
    fi
}

# ===================================================================
#                       ACTION FUNCTIONS
# ===================================================================

# -- 1. Full install -----------------------------------------------
do_install() {
    exec > >(tee -a "$LOG_FILE") 2>&1
    require_root
    detect_os
    info "Detected: ${ID} ${VERSION_ID} (pkg: ${PKG_MANAGER})"

    # --- Docker check ---
    require_docker
    info "Docker: $(docker --version)"

    # --- Install certbot ---
    info "==> Checking certbot..."
    if ! command -v certbot &>/dev/null; then
        info "Installing certbot..."
        case "$PKG_MANAGER" in
            apt)
                apt-get update -qq
                apt-get install -y --no-install-recommends certbot
                ;;
            dnf)
                dnf install -y epel-release 2>/dev/null || true
                dnf install -y certbot
                ;;
            yum)
                yum install -y epel-release 2>/dev/null || true
                yum install -y certbot
                ;;
        esac
        command -v certbot &>/dev/null || error "Failed to install certbot."
        info "certbot installed: $(certbot --version 2>&1)"
    else
        info "certbot already installed: $(certbot --version 2>&1)"
    fi

    # --- Interactive configuration ---
    info "==> Collecting configuration..."
    USE_EXISTING=false
    if [[ -f "$CONFIG_FILE" ]]; then
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
        info "Found existing configuration:"
        info "  Domain:  ${DOMAIN:-<not set>}"
        info "  User:    ${USER:-<not set>}"
        info "  Port:    ${PORT:-<not set>}"
        info "  Bind IP: ${BIND_IP:-<not set>}"
        prompt "Use existing configuration? [Y/n]: "
        read -r answer
        [[ "${answer,,}" != "n" ]] && USE_EXISTING=true
    fi

    if [[ "$USE_EXISTING" == "false" ]]; then
        while true; do
            prompt "Domain name (e.g., example.com): "
            read -r DOMAIN
            [[ -n "$DOMAIN" ]] && break
            warn "Domain is required."
        done

        while true; do
            prompt "Proxy username: "
            read -r USER
            [[ -n "$USER" ]] && break
            warn "Username is required."
        done

        while true; do
            prompt "Proxy password: "
            read -rs PASS; echo
            if [[ -n "$PASS" ]]; then
                prompt "Confirm password: "
                read -rs PASS_CONFIRM; echo
                [[ "$PASS" == "$PASS_CONFIRM" ]] && break
                warn "Passwords do not match."
            else
                warn "Password is required."
            fi
        done

        prompt "Port [443]: "
        read -r PORT; PORT="${PORT:-443}"

        prompt "Bind IP [0.0.0.0]: "
        read -r BIND_IP; BIND_IP="${BIND_IP:-0.0.0.0}"
    fi

    CERT="${CERT_DIR}/live/${DOMAIN}/fullchain.pem"
    KEY="${CERT_DIR}/live/${DOMAIN}/privkey.pem"

    info "Configuration summary:"
    info "  Domain: $DOMAIN | User: $USER | Port: $PORT | Bind: $BIND_IP"
    prompt "Proceed? [Y/n]: "
    read -r answer
    [[ "${answer,,}" == "n" ]] && { info "Aborted."; return; }

    # --- SSL certificate ---
    info "==> Generating SSL certificate..."
    if [[ -f "$CERT" && -f "$KEY" ]]; then
        EXPIRY=$(openssl x509 -enddate -noout -in "$CERT" 2>/dev/null | cut -d= -f2)
        EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$EXPIRY" +%s 2>/dev/null || echo 0)
        NOW_EPOCH=$(date +%s)
        DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))

        if [[ $DAYS_LEFT -gt 30 ]]; then
            info "Valid certificate found. Expires: $EXPIRY ($DAYS_LEFT days). Skipping."
        else
            warn "Certificate expires in $DAYS_LEFT days. Renewing..."
            certbot renew --force-renewal
        fi
    else
        if ss -tlnp | grep -q ':80 '; then
            warn "Port 80 is in use. Certbot standalone requires port 80."
            prompt "Stop the service on port 80 and continue? [y/N]: "
            read -r answer
            [[ "${answer,,}" != "y" ]] && error "Free port 80 and try again."
        fi

        info "Requesting certificate for $DOMAIN..."
        certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos \
            --register-unsafely-without-email

        [[ -f "$CERT" && -f "$KEY" ]] || error "Certificate generation failed."
        EXPIRY=$(openssl x509 -enddate -noout -in "$CERT" | cut -d= -f2)
        info "Certificate generated. Expires: $EXPIRY"
    fi

    # --- Deploy container ---
    info "==> Deploying GOST container..."
    if docker ps -a --format '{{.Names}}' | grep -qw "$CONTAINER_NAME"; then
        info "Removing existing container..."
        docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1
    fi

    if start_gost_container; then
        info "GOST container started. ID: $(docker ps -q --filter name=$CONTAINER_NAME)"
    else
        error "GOST container failed to start. Check: docker logs $CONTAINER_NAME"
    fi

    # --- Save configuration ---
    info "==> Saving configuration..."
    install -m 0700 -d "$CONFIG_DIR"
    cat > "$CONFIG_FILE" <<EOF
# GOST Proxy Configuration
# Generated by setup_gost.sh on $(date '+%Y-%m-%d %H:%M:%S')
# WARNING: Contains credentials. Do not share.
DOMAIN="${DOMAIN}"
USER="${USER}"
PASS="${PASS}"
PORT="${PORT}"
BIND_IP="${BIND_IP}"
EOF
    chmod 600 "$CONFIG_FILE"
    info "Configuration saved to $CONFIG_FILE (mode 600)"

    # --- Cron jobs ---
    info "==> Setting up cron jobs..."
    CRON_TEMP=$(mktemp)
    crontab -l 2>/dev/null | grep -v "setup_gost.sh" > "$CRON_TEMP" || true
    cat >> "$CRON_TEMP" <<EOF
# GOST certificate renewal - auto-generated by setup_gost.sh
0 0 1 * * ${SCRIPT_PATH} renew >> ${RENEW_LOG} 2>&1
5 0 1 * * ${SCRIPT_PATH} restart >> ${RENEW_LOG} 2>&1
EOF
    crontab "$CRON_TEMP"
    rm -f "$CRON_TEMP"
    info "Cron jobs installed:"
    info "  0 0 1 * * - Renew certificate  (1st of month, 00:00)"
    info "  5 0 1 * * - Restart container   (1st of month, 00:05)"

    # --- Summary ---
    echo
    info "=========================================="
    info "  GOST proxy setup completed!"
    info "=========================================="
    info "  Protocol:  HTTP2 over TLS"
    info "  Domain:    $DOMAIN"
    info "  Port:      $PORT"
    info "  Bind IP:   $BIND_IP"
    info "  Container: $CONTAINER_NAME"
    info "  Config:    $CONFIG_FILE"
    info "  Log:       $LOG_FILE"
    info "=========================================="
}

# -- 2. Renew certificate ------------------------------------------
do_renew() {
    require_root
    load_config
    log_renew "=========================================="
    log_renew "Certificate renewal started for ${DOMAIN}"

    command -v certbot &>/dev/null || error "certbot is not installed."

    if [[ ! -f "$CERT" ]]; then
        log_renew "Certificate not found. Issuing new certificate..."
        certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos \
            --register-unsafely-without-email 2>&1 | tee -a "$RENEW_LOG"
    else
        certbot renew --force-renewal 2>&1 | tee -a "$RENEW_LOG"
    fi

    RENEW_EXIT=${PIPESTATUS[0]}
    [[ $RENEW_EXIT -ne 0 ]] && error "Certificate renewal failed (exit: $RENEW_EXIT)"

    if [[ -f "$CERT" ]]; then
        EXPIRY=$(openssl x509 -enddate -noout -in "$CERT" 2>/dev/null | cut -d= -f2)
        log_renew "Certificate renewed. Expires: $EXPIRY"
    else
        error "Certificate file not found after renewal."
    fi
    log_renew "=========================================="
}

# -- 3. Restart container ------------------------------------------
do_restart() {
    require_root
    load_config
    require_docker
    log_renew "=========================================="
    log_renew "Restarting GOST container..."

    if docker ps -a --format '{{.Names}}' | grep -qw "$CONTAINER_NAME"; then
        docker restart "$CONTAINER_NAME" 2>&1 | tee -a "$RENEW_LOG"
        RESTART_EXIT=${PIPESTATUS[0]}
        [[ $RESTART_EXIT -ne 0 ]] && error "Container restart failed (exit: $RESTART_EXIT)"

        sleep 3
        if docker ps --format '{{.Names}}' | grep -qw "$CONTAINER_NAME"; then
            log_renew "GOST container restarted successfully."
        else
            warn "Container exited after restart. Recreating..."
            docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
            if start_gost_container; then
                log_renew "GOST container recreated."
            else
                error "Failed to start GOST container. Check: docker logs $CONTAINER_NAME"
            fi
        fi
    else
        warn "Container '$CONTAINER_NAME' not found. Creating..."
        if start_gost_container; then
            log_renew "GOST container created and started."
        else
            error "Failed to start GOST container. Check: docker logs $CONTAINER_NAME"
        fi
    fi
    log_renew "=========================================="
}

# -- 4. Renew + restart --------------------------------------------
do_renew_restart() {
    do_renew
    do_restart
}

# -- 5. Show status ------------------------------------------------
do_status() {
    require_root

    echo -e "\n${BOLD}=== GOST Proxy Status ===${NC}\n"

    # Configuration
    if [[ -f "$CONFIG_FILE" ]]; then
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
        echo -e "${GREEN}Configuration:${NC} $CONFIG_FILE"
        echo -e "  Domain:  ${DOMAIN:-<not set>}"
        echo -e "  User:    ${USER:-<not set>}"
        echo -e "  Port:    ${PORT:-<not set>}"
        echo -e "  Bind IP: ${BIND_IP:-<not set>}"
    else
        echo -e "${YELLOW}Configuration:${NC} Not found ($CONFIG_FILE)"
    fi

    echo

    # Certificate
    CERT="${CERT_DIR}/live/${DOMAIN:-unknown}/fullchain.pem"
    if [[ -f "$CERT" ]]; then
        EXPIRY=$(openssl x509 -enddate -noout -in "$CERT" 2>/dev/null | cut -d= -f2)
        EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$EXPIRY" +%s 2>/dev/null || echo 0)
        NOW_EPOCH=$(date +%s)
        DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))

        if [[ $DAYS_LEFT -gt 30 ]]; then
            echo -e "${GREEN}Certificate:${NC} Valid ($DAYS_LEFT days remaining, expires: $EXPIRY)"
        elif [[ $DAYS_LEFT -gt 0 ]]; then
            echo -e "${YELLOW}Certificate:${NC} Expiring soon ($DAYS_LEFT days remaining, expires: $EXPIRY)"
        else
            echo -e "${RED}Certificate:${NC} EXPIRED ($EXPIRY)"
        fi
    else
        echo -e "${YELLOW}Certificate:${NC} Not found"
    fi

    echo

    # Docker container
    if command -v docker &>/dev/null && docker info &>/dev/null; then
        if docker ps --format '{{.Names}}' | grep -qw "$CONTAINER_NAME"; then
            CONTAINER_STATUS=$(docker ps --filter name="$CONTAINER_NAME" --format "{{.Status}}")
            echo -e "${GREEN}Container:${NC} Running ($CONTAINER_STATUS)"
        elif docker ps -a --format '{{.Names}}' | grep -qw "$CONTAINER_NAME"; then
            CONTAINER_STATUS=$(docker ps -a --filter name="$CONTAINER_NAME" --format "{{.Status}}")
            echo -e "${RED}Container:${NC} Stopped ($CONTAINER_STATUS)"
        else
            echo -e "${YELLOW}Container:${NC} Not found"
        fi
    else
        echo -e "${RED}Docker:${NC} Not available"
    fi

    echo

    # Cron jobs
    if crontab -l 2>/dev/null | grep -q "setup_gost.sh"; then
        echo -e "${GREEN}Cron jobs:${NC}"
        crontab -l 2>/dev/null | grep "setup_gost.sh" | while read -r line; do
            echo "  $line"
        done
    else
        echo -e "${YELLOW}Cron jobs:${NC} Not configured"
    fi

    echo
}

# -- 6. Uninstall --------------------------------------------------
do_uninstall() {
    require_root
    info "==> Uninstalling GOST proxy..."

    # Container
    if command -v docker &>/dev/null; then
        if docker ps -a --format '{{.Names}}' | grep -qw "$CONTAINER_NAME"; then
            docker rm -f "$CONTAINER_NAME"
            info "Container '$CONTAINER_NAME' removed."
        else
            warn "Container '$CONTAINER_NAME' not found."
        fi
    fi

    # Cron jobs
    if crontab -l 2>/dev/null | grep -q "setup_gost.sh"; then
        crontab -l 2>/dev/null | grep -v "setup_gost.sh" | crontab -
        info "Cron jobs removed."
    fi

    # Config
    prompt "Remove configuration ($CONFIG_DIR)? [y/N]: "
    read -r answer
    if [[ "${answer,,}" == "y" ]]; then
        rm -rf "$CONFIG_DIR"
        info "Configuration removed."
    fi

    # Certificates
    prompt "Remove certificates ($CERT_DIR)? [y/N]: "
    read -r answer
    if [[ "${answer,,}" == "y" ]]; then
        rm -rf "$CERT_DIR"
        info "Certificates removed."
    fi

    info "Uninstall completed."
}

# ===================================================================
#                       MENU / ENTRY POINT
# ===================================================================

show_help() {
    cat <<'HELP'
Usage: sudo bash setup_gost.sh [COMMAND]

GOST HTTP2 Proxy - Setup, Maintenance & Management

Commands (for CLI / cron usage):
  install          Full installation (interactive)
  renew            Renew SSL certificate only
  restart          Restart GOST container only
  renew-restart    Renew certificate + restart container
  status           Show current service status
  uninstall        Remove GOST proxy
  help             Show this help message

Without a command, an interactive menu is displayed.

Cron example:
  0 0 1 * * /path/to/setup_gost.sh renew
  5 0 1 * * /path/to/setup_gost.sh restart
HELP
}

show_menu() {
    echo
    echo -e "${BOLD}========================================${NC}"
    echo -e "${BOLD}   GOST HTTP2 Proxy Manager${NC}"
    echo -e "${BOLD}========================================${NC}"
    echo
    echo -e "  ${GREEN}1)${NC} Install      - Full setup (certbot + cert + container + cron)"
    echo -e "  ${GREEN}2)${NC} Renew Cert   - Renew SSL certificate"
    echo -e "  ${GREEN}3)${NC} Restart      - Restart GOST container"
    echo -e "  ${GREEN}4)${NC} Renew + Restart - Renew certificate and restart container"
    echo -e "  ${GREEN}5)${NC} Status       - Show service status"
    echo -e "  ${GREEN}6)${NC} Uninstall    - Remove GOST proxy"
    echo -e "  ${GREEN}0)${NC} Exit"
    echo
    prompt "Select [0-6]: "
}

# -- CLI argument dispatch -----------------------------------------
case "${1:-}" in
    install)        do_install;        exit 0 ;;
    renew)          do_renew;          exit 0 ;;
    restart)        do_restart;        exit 0 ;;
    renew-restart)  do_renew_restart;  exit 0 ;;
    status)         do_status;         exit 0 ;;
    uninstall)      do_uninstall;      exit 0 ;;
    help|--help|-h) show_help;         exit 0 ;;
    "")             ;; # fall through to menu
    *)              error "Unknown command: $1. Use 'help' for usage." ;;
esac

# -- Interactive menu loop -----------------------------------------
while true; do
    show_menu
    read -r choice
    echo

    case "$choice" in
        1) do_install ;;
        2) do_renew ;;
        3) do_restart ;;
        4) do_renew_restart ;;
        5) do_status ;;
        6) do_uninstall ;;
        0)
            info "Bye!"
            exit 0
            ;;
        *)
            warn "Invalid selection. Please enter 0-6."
            ;;
    esac

    echo
    prompt "Press Enter to return to menu..."
    read -r
done
