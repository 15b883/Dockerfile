#!/bin/bash

# =================================================================
# Function: Enable TCP BBR congestion control + Install Docker CE
# Supported: Ubuntu 22.04 LTS (jammy) / Ubuntu 24.04 LTS (noble)
# Usage: sudo bash setup_bbr_docker.sh
# =================================================================

set -euo pipefail

# -- Log output to file -------------------------------------------
LOG_FILE="/var/log/setup_bbr_docker_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

# -- Color output --------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# -- Pre-flight checks ---------------------------------------------
[[ $EUID -ne 0 ]] && error "Please run as root (sudo bash $0)"

# Validate distro (Ubuntu 22.04 / 24.04 only)
[[ -f /etc/os-release ]] || error "Cannot read /etc/os-release, unsupported distro"
# shellcheck source=/dev/null
source /etc/os-release
[[ "${ID}" == "ubuntu" ]] || error "Unsupported distro: ${ID}, only Ubuntu is supported"
[[ "${VERSION_ID}" == "22.04" || "${VERSION_ID}" == "24.04" ]] \
    || error "Unsupported Ubuntu version: ${VERSION_ID}, only 22.04 LTS and 24.04 LTS are supported"

# Ubuntu 24.04 uses UBUNTU_CODENAME; 22.04 uses VERSION_CODENAME
OS_CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
[[ -n "${OS_CODENAME}" ]] || error "Cannot determine release codename"
info "Detected system: Ubuntu ${VERSION_ID} LTS (${OS_CODENAME})"

# -- 1. Enable TCP BBR --------------------------------------------
info "==> 1. Checking and enabling TCP BBR..."

# Check if BBR module is available
if ! modinfo tcp_bbr &>/dev/null; then
    warn "tcp_bbr module not found, attempting to load..."
    modprobe tcp_bbr || error "Failed to load tcp_bbr module"
fi

# Persist BBR module loading across reboots
if [[ ! -f /etc/modules-load.d/bbr.conf ]] || ! grep -qF "tcp_bbr" /etc/modules-load.d/bbr.conf 2>/dev/null; then
    echo "tcp_bbr" > /etc/modules-load.d/bbr.conf
    info "BBR module persisted in /etc/modules-load.d/bbr.conf"
fi

# Idempotent sysctl configuration (avoids duplicate entries)
set_sysctl() {
    local key="$1" value="$2" file="/etc/sysctl.d/99-bbr.conf"
    touch "$file"
    # Use fixed-string grep to avoid regex issues with dots in key names
    if grep -qF "${key}" "$file" 2>/dev/null; then
        # Use awk for safe replacement without sed regex pitfalls
        awk -v k="$key" -v v="$value" '
            index($0, k) == 1 { print k " = " v; next }
            { print }
        ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
    else
        echo "${key} = ${value}" >> "$file"
    fi
}

set_sysctl "net.core.default_qdisc"        "fq"
set_sysctl "net.ipv4.tcp_congestion_control" "bbr"

# Load all sysctl configs (keep stderr visible for troubleshooting)
sysctl --system > /dev/null

# Verify
current_cc=$(sysctl -n net.ipv4.tcp_congestion_control)
if [[ "$current_cc" == "bbr" ]]; then
    info "BBR activated successfully (current congestion control: $current_cc)"
else
    error "BBR activation failed, current congestion control: $current_cc"
fi

# -- 2. Install Docker CE -----------------------------------------
info "==> 2. Installing Docker CE..."

# Check if Docker is already installed and functional
if command -v docker &>/dev/null && docker info > /dev/null 2>&1; then
    warn "Docker is already installed and running ($(docker --version)), skipping installation"
else
    # If docker binary exists but daemon is broken, warn the user
    if command -v docker &>/dev/null; then
        warn "Docker binary found but daemon is not running, proceeding with reinstallation..."
    fi

    # Network connectivity check
    info "Checking network connectivity to download.docker.com..."
    curl -fsS --connect-timeout 5 --max-time 10 "https://download.docker.com" > /dev/null \
        || error "Cannot connect to download.docker.com, please check network"

    # Configure GPG key
    KEYRING_DIR="/etc/apt/keyrings"
    KEYRING_FILE="${KEYRING_DIR}/docker.gpg"
    install -m 0755 -d "$KEYRING_DIR"

    # Download and dearmor GPG key (idempotent: overwrites existing key file)
    curl -fsSL --connect-timeout 10 --max-time 30 \
        "https://download.docker.com/linux/ubuntu/gpg" \
        | gpg --dearmor --yes -o "$KEYRING_FILE"
    chmod a+r "$KEYRING_FILE"

    # Verify GPG key fingerprint
    EXPECTED_FP="9DC858229FC7DD38854AE2D88D81803C0EBFCD88"
    actual_fp=$(gpg --no-default-keyring --keyring "$KEYRING_FILE" \
        --list-keys --with-colons 2>/dev/null | awk -F: '/^fpr/{print $10; exit}')
    if [[ "$actual_fp" != "$EXPECTED_FP" ]]; then
        rm -f "$KEYRING_FILE"
        error "Docker GPG key fingerprint mismatch! Expected: $EXPECTED_FP, Got: $actual_fp"
    fi
    info "Docker GPG key fingerprint verified"

    # Configure apt source
    ARCH=$(dpkg --print-architecture)
    echo "deb [arch=${ARCH} signed-by=${KEYRING_FILE}] \
https://download.docker.com/linux/ubuntu ${OS_CODENAME} stable" \
        > /etc/apt/sources.list.d/docker.list

    # Install dependencies and Docker components in a single apt-get update
    apt-get update -qq
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    # Clean apt cache
    apt-get clean
    rm -rf /var/lib/apt/lists/*

    # Enable and start Docker service
    systemctl enable --now docker

    # Verify Docker daemon is healthy
    if ! systemctl is-active --quiet docker; then
        error "Docker service failed to start"
    fi
    if ! docker info > /dev/null 2>&1; then
        error "Docker daemon is not responding"
    fi

    info "Docker installed successfully: $(docker --version)"
fi

# -- Done ---------------------------------------------------------
info "==> All tasks completed!"
info "BBR:    $(sysctl -n net.ipv4.tcp_congestion_control)"
info "Docker: $(docker --version)"
info "Log:    ${LOG_FILE}"

# Hint for non-root Docker usage
SUDO_USER="${SUDO_USER:-}"
if [[ -n "$SUDO_USER" ]]; then
    info "Hint: To allow user '${SUDO_USER}' to use Docker without sudo, run:"
    info "  sudo usermod -aG docker ${SUDO_USER} && newgrp docker"
else
    info "Hint: To allow non-root users to use Docker, run:"
    info "  sudo usermod -aG docker <username>"
fi
