#!/bin/bash

# =================================================================
# Function: Install Docker CE + Docker Compose Plugin
# Supported: Ubuntu 22.04/24.04, Debian 11/12, CentOS Stream 8/9, RHEL 8/9
# Usage: sudo bash install_docker.sh
# =================================================================

set -euo pipefail

# -- Log output to file -------------------------------------------
LOG_FILE="/var/log/install_docker_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

# -- Color output --------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# -- Pre-flight checks ---------------------------------------------
[[ $EUID -ne 0 ]] && error "Please run as root (sudo bash $0)"

[[ -f /etc/os-release ]] || error "Cannot read /etc/os-release, unsupported distro"
# shellcheck source=/dev/null
source /etc/os-release

# Supported distro + version matrix
VERSION_MAJOR="${VERSION_ID%%.*}"
case "${ID}" in
    ubuntu)
        [[ "${VERSION_ID}" == "22.04" || "${VERSION_ID}" == "24.04" ]] \
            || error "Unsupported Ubuntu version: ${VERSION_ID}. Supported: 22.04, 24.04"
        ;;
    debian)
        [[ "${VERSION_MAJOR}" == "11" || "${VERSION_MAJOR}" == "12" ]] \
            || error "Unsupported Debian version: ${VERSION_ID}. Supported: 11, 12"
        ;;
    centos)
        [[ "${VERSION_MAJOR}" == "8" || "${VERSION_MAJOR}" == "9" ]] \
            || error "Unsupported CentOS version: ${VERSION_ID}. Supported: Stream 8, Stream 9"
        ;;
    rhel)
        [[ "${VERSION_MAJOR}" == "8" || "${VERSION_MAJOR}" == "9" ]] \
            || error "Unsupported RHEL version: ${VERSION_ID}. Supported: 8, 9"
        ;;
    *)
        error "Unsupported distro: ${ID}. Supported: ubuntu, debian, centos, rhel"
        ;;
esac

# Detect package manager family
if [[ "${ID}" =~ ^(ubuntu|debian)$ ]]; then
    PKG_MANAGER="apt"
elif command -v dnf &>/dev/null; then
    PKG_MANAGER="dnf"
else
    PKG_MANAGER="yum"
fi

# Determine OS codename (apt-based only)
if [[ "$PKG_MANAGER" == "apt" ]]; then
    OS_CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
    [[ -n "${OS_CODENAME}" ]] || error "Cannot determine release codename"
fi

# Docker repo distro identifier (RHEL uses centos repo)
if [[ "${ID}" == "rhel" ]]; then
    DOCKER_REPO_ID="centos"
else
    DOCKER_REPO_ID="${ID}"
fi

info "Detected system: ${ID} ${VERSION_ID} (pkg: ${PKG_MANAGER}, repo: ${DOCKER_REPO_ID})"

# -- Network connectivity check ------------------------------------
info "Checking network connectivity..."
curl -fsS --connect-timeout 5 --max-time 10 "https://download.docker.com" > /dev/null \
    || error "Cannot connect to download.docker.com, please check network"

# -- Idempotent: skip if Docker is already healthy -----------------
if command -v docker &>/dev/null && docker info > /dev/null 2>&1; then
    warn "Docker is already installed and running:"
    warn "  Docker:  $(docker --version)"
    warn "  Compose: $(docker compose version 2>/dev/null || echo 'not installed')"
    warn "Skipping installation. To reinstall, remove Docker first."
    exit 0
fi

if command -v docker &>/dev/null; then
    warn "Docker binary found but daemon is not running, proceeding with reinstallation..."
fi

# -- Remove conflicting packages -----------------------------------
info "Removing conflicting packages..."
if [[ "$PKG_MANAGER" == "apt" ]]; then
    # Suppress errors for packages that may not exist
    apt-get remove -y docker.io docker-doc docker-compose \
        podman-docker containerd runc 2>/dev/null || true
else
    $PKG_MANAGER remove -y docker docker-client docker-client-latest \
        docker-common docker-latest docker-latest-logrotate \
        docker-logrotate docker-engine podman runc 2>/dev/null || true
fi

# -- Install dependencies -----------------------------------------
info "Installing dependencies..."
if [[ "$PKG_MANAGER" == "apt" ]]; then
    apt-get update -qq
    apt-get install -y --no-install-recommends ca-certificates curl gnupg
else
    $PKG_MANAGER install -y yum-utils ca-certificates curl
fi

# -- Configure Docker repository -----------------------------------
info "Configuring Docker repository..."

DOCKER_GPG_FP="9DC858229FC7DD38854AE2D88D81803C0EBFCD88"

if [[ "$PKG_MANAGER" == "apt" ]]; then
    # GPG key
    KEYRING_DIR="/etc/apt/keyrings"
    KEYRING_FILE="${KEYRING_DIR}/docker.gpg"
    install -m 0755 -d "$KEYRING_DIR"

    curl -fsSL --connect-timeout 10 --max-time 30 \
        "https://download.docker.com/linux/${DOCKER_REPO_ID}/gpg" \
        | gpg --dearmor --yes -o "$KEYRING_FILE"
    chmod a+r "$KEYRING_FILE"

    # Verify GPG key fingerprint
    actual_fp=$(gpg --no-default-keyring --keyring "$KEYRING_FILE" \
        --list-keys --with-colons 2>/dev/null | awk -F: '/^fpr/{print $10; exit}')
    if [[ "$actual_fp" != "$DOCKER_GPG_FP" ]]; then
        rm -f "$KEYRING_FILE"
        error "Docker GPG key fingerprint mismatch! Expected: $DOCKER_GPG_FP, Got: $actual_fp"
    fi
    info "Docker GPG key fingerprint verified"

    # Apt source
    ARCH=$(dpkg --print-architecture)
    echo "deb [arch=${ARCH} signed-by=${KEYRING_FILE}] \
https://download.docker.com/linux/${DOCKER_REPO_ID} ${OS_CODENAME} stable" \
        > /etc/apt/sources.list.d/docker.list

    apt-get update -qq
else
    # RPM repo (yum-config-manager works for both yum and dnf)
    REPO_URL="https://download.docker.com/linux/${DOCKER_REPO_ID}/docker-ce.repo"
    yum-config-manager --add-repo "$REPO_URL"

    # Verify GPG key from repo metadata
    info "Docker repository configured: ${REPO_URL}"
fi

# -- Install Docker CE ---------------------------------------------
info "Installing Docker CE..."
DOCKER_PACKAGES=(
    docker-ce
    docker-ce-cli
    containerd.io
    docker-buildx-plugin
    docker-compose-plugin
)

if [[ "$PKG_MANAGER" == "apt" ]]; then
    apt-get install -y --no-install-recommends "${DOCKER_PACKAGES[@]}"
else
    $PKG_MANAGER install -y "${DOCKER_PACKAGES[@]}"
fi

# -- Enable and start Docker service -------------------------------
info "Enabling and starting Docker service..."
systemctl enable --now docker

# -- Health verification -------------------------------------------
if ! systemctl is-active --quiet docker; then
    error "Docker service failed to start"
fi
if ! docker info > /dev/null 2>&1; then
    error "Docker daemon is not responding"
fi

# -- Clean package cache -------------------------------------------
info "Cleaning package cache..."
if [[ "$PKG_MANAGER" == "apt" ]]; then
    apt-get clean
    rm -rf /var/lib/apt/lists/*
else
    $PKG_MANAGER clean all
fi

# -- Done ----------------------------------------------------------
info "==> Installation completed successfully!"
info "Docker:  $(docker --version)"
info "Compose: $(docker compose version)"
info "Log:     ${LOG_FILE}"

# Hint for non-root Docker usage
SUDO_USER="${SUDO_USER:-}"
if [[ -n "$SUDO_USER" ]]; then
    info "Hint: To allow user '${SUDO_USER}' to use Docker without sudo, run:"
    info "  sudo usermod -aG docker ${SUDO_USER} && newgrp docker"
else
    info "Hint: To allow non-root users to use Docker, run:"
    info "  sudo usermod -aG docker <username>"
fi
