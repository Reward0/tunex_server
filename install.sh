#!/bin/bash
set -e

trap 'error_exit "Failed at stage: $STAGE"' ERR

error_exit() {
  echo "exit with error: $1" >&2
  exit 1
}

STAGE="Checking root privileges"
if [ "$EUID" -ne 0 ]; then
  error_exit "$STAGE"
fi

STAGE="Detecting Debian OS"
if [ -f /etc/debian_version ]; then
    OS="debian"
    echo "✓ Debian-based OS detected"
else
    error_exit "$STAGE - Only Debian-based systems supported"
fi

#STAGE="Installing tunex from GitHub"
#echo "Installing tunex from GitHub"
#git clone 


STAGE="Updating system packages"
echo "Installing dependencies"
apt update -y
apt install -y python3 python3-pip curl wget git ufw

STAGE="Enabling IP forwarding"
echo "Enabling IP forwarding..."
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

STAGE="Creating directories"
echo "Creating necessary directories"
mkdir -p /opt/tunex
mkdir -p /var/log/tunex
mkdir -p /etc/tunex

STAGE="Setting up tunex user"
echo "Creating tunex user and setting permissions"
useradd -r -s /usr/sbin/nologin tunex || true
mkdir -p /etc/tunex
mkdir -p /var/lib/tunex
chown -R tunex:tunex /var/lib/tunex

STAGE="Configuring UFW firewall"
echo "Setting up UFW firewall rules"
if systemctl is-active --quiet ufw; then
    ufw allow 22/tcp
    ufw allow 443/tcp
    ufw allow 443/udp
else
    echo "UFW is not running, skipping firewall rules"
fi

echo "Installation completed successfully"
