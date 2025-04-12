#!/bin/bash

# Purpose: Install a specified or latest version of Docker and Docker Compose
# Compatible with Debian/Ubuntu systems
# Usage: ./install_docker.sh [docker_version]
# Example: ./install_docker.sh 23.0.6 or ./install_docker.sh (installs latest version)

# Check for root or sudo privileges
if [ "$(id -u)" != "0" ]; then
  echo "Error: This script must be run as root or with sudo!"
  exit 1
fi

# Determine Docker version (fetch latest if not specified)
if [ -z "$1" ]; then
  echo "No version specified, fetching latest Docker version..."
  DOCKER_VERSION=$(apt-cache madison docker-ce | head -n 1 | awk '{print $3}' | cut -d ':' -f 2 | cut -d '-' -f 1)
  if [ -z "$DOCKER_VERSION" ]; then
    echo "Error: Unable to fetch latest Docker version. Check network or try again later!"
    exit 1
  fi
  echo "Latest version: $DOCKER_VERSION"
else
  DOCKER_VERSION="$1"
fi

# Update system packages
echo "Updating system packages..."
apt-get update -y
apt-get upgrade -y

# Install required dependencies
echo "Installing Docker dependencies..."
apt-get install -y apt-transport-https ca-certificates curl software-properties-common gnupg lsb-release

# Add Docker official GPG key
echo "Adding Docker GPG key..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
if [ $? -ne 0 ]; then
  echo "Error: Failed to add GPG key!"
  exit 1
fi

# Add Docker repository
echo "Adding Docker repository..."
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

# Update package index
echo "Updating package index..."
apt-get update -y

# Verify specified version availability
echo "Checking availability of Docker version $DOCKER_VERSION..."
AVAILABLE_VERSION=$(apt-cache madison docker-ce | grep "$DOCKER_VERSION" | awk '{print $3}' | head -n 1)
if [ -z "$AVAILABLE_VERSION" ]; then
  echo "Error: Docker version $DOCKER_VERSION is not available!"
  echo "Available versions:"
  apt-cache madison docker-ce | awk '{print $3}' | head -n 5
  exit 1
fi

# Install specified Docker version
echo "Installing Docker version $DOCKER_VERSION..."
apt-get install -y docker-ce="$AVAILABLE_VERSION" docker-ce-cli="$AVAILABLE_VERSION" containerd.io
if [ $? -ne 0 ]; then
  echo "Error: Docker installation failed!"
  exit 1
fi

# Start Docker service and enable on boot
echo "Starting Docker service..."
systemctl start docker
systemctl enable docker

# Install latest Docker Compose
echo "Installing latest Docker Compose..."
DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep tag_name | cut -d '"' -f 4)
if [ -z "$DOCKER_COMPOSE_VERSION" ]; then
  echo "Error: Unable to fetch latest Docker Compose version!"
  exit 1
fi
curl -L "https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
if [ $? -ne 0 ]; then
  echo "Error: Docker Compose installation failed!"
  exit 1
fi

# Verify installations
echo "Verifying Docker installation..."
INSTALLED_DOCKER_VERSION=$(docker --version)
echo "$INSTALLED_DOCKER_VERSION"
echo "Verifying Docker Compose installation..."
INSTALLED_COMPOSE_VERSION=$(docker-compose --version)
echo "$INSTALLED_COMPOSE_VERSION"

# Check Docker service status
if systemctl is-active --quiet docker; then
  echo "Docker service is running!"
else
  echo "Error: Docker service is not running!"
  exit 1
fi

echo "Docker version $DOCKER_VERSION and Docker Compose $DOCKER_COMPOSE_VERSION installed successfully!"