#!/bin/bash
set -e
trap 'error_exit "Failed at stage: $STAGE"' ERR

error_exit() {
    echo "Error: $1" >&2
    exit 1
}

REPO_URL="https://github.com/Reward0/tunex_server"
INSTALL_DIR="/opt/tunex"
LOG_DIR="/var/log/tunex"
CONFIG_DIR="/etc/tunex"
SERVICE_USER="tunex"

# ─────────────────────────────────────────────
STAGE="Checking root privileges"
if [ "$EUID" -ne 0 ]; then
    error_exit "$STAGE - run the script as root or via sudo"
fi

# ─────────────────────────────────────────────
STAGE="Detecting Debian OS"
if [ -f /etc/debian_version ]; then
    OS="debian"
    echo "Debian-based OS detected"
else
    error_exit "$STAGE - only Debian-based systems are supported"
fi

# ─────────────────────────────────────────────
STAGE="Checking existing installation"
echo "Checking for existing tunex installation..."
ALREADY_INSTALLED=0
[ -d "$INSTALL_DIR/.git" ] && ALREADY_INSTALLED=1
[ -f /etc/systemd/system/tunex.service ] && ALREADY_INSTALLED=1
id "$SERVICE_USER" &>/dev/null && ALREADY_INSTALLED=1

if [ "$ALREADY_INSTALLED" -eq 1 ]; then
    echo ""
    echo "Tunex agent is already installed on this server."
    echo ""
    echo "  Install dir:  $INSTALL_DIR"
    echo "  Service:      systemctl status tunex"
    echo ""
    read -rp "Do you want to reinstall? This will overwrite existing files. [y/N]: " CONFIRM
    case "$CONFIRM" in
        [yY][eE][sS]|[yY])
            echo "Proceeding with reinstallation..."
            systemctl stop tunex 2>/dev/null || true
            ;;
        *)
            echo "Installation aborted."
            exit 0
            ;;
    esac
fi

# ─────────────────────────────────────────────
STAGE="Updating system packages"
echo "Updating packages..."
apt update -y
apt install -y python3 python3-pip python3-venv curl wget git ufw

# ─────────────────────────────────────────────
STAGE="Creating directories"
echo "Creating necessary directories..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$LOG_DIR"
mkdir -p "$CONFIG_DIR"

# ─────────────────────────────────────────────
STAGE="Setting up tunex user"
echo "Creating system user $SERVICE_USER..."
if ! id "$SERVICE_USER" &>/dev/null; then
    useradd -r -s /usr/sbin/nologin -d "$INSTALL_DIR" "$SERVICE_USER"
fi
mkdir -p /var/lib/tunex
chown -R "$SERVICE_USER":"$SERVICE_USER" /var/lib/tunex "$LOG_DIR"

# ─────────────────────────────────────────────
#STAGE="Installing tunex from GitHub"
#echo "Cloning repository..."
#if [ -d "$INSTALL_DIR/.git" ]; then
#    echo "Repository already exists, pulling latest changes..."
#    git -C "$INSTALL_DIR" pull
#else
#    GIT_TERMINAL_PROMPT=0 git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
#fi

# ─────────────────────────────────────────────
STAGE="Installing Python dependencies"
echo "Installing Python dependencies..."
python3 -m venv "$INSTALL_DIR/.venv"
"$INSTALL_DIR/.venv/bin/pip" install --upgrade pip
if [ -f "$INSTALL_DIR/requirements.txt" ]; then
    "$INSTALL_DIR/.venv/bin/pip" install -r "$INSTALL_DIR/requirements.txt"
else
    echo "Warning: requirements.txt not found, skipping"
fi

# ─────────────────────────────────────────────
STAGE="Enabling IP forwarding"
echo "Enabling IP forwarding..."
sysctl -w net.ipv4.ip_forward=1
if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi
sysctl -p

# ─────────────────────────────────────────────
STAGE="Configuring UFW firewall"
echo "Configuring UFW firewall..."
if systemctl is-active --quiet ufw; then
    ufw allow 22/tcp
    ufw allow 443/tcp
    ufw allow 443/udp
    echo "UFW rules added"
else
    echo "Warning: UFW is not running, skipping firewall rules"
fi

# ─────────────────────────────────────────────
STAGE="Installing systemd service"
echo "Installing systemd service..."
cat > /etc/systemd/system/tunex.service <<EOF
[Unit]
Description=Tunex Agent
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/.venv/bin/python3 $INSTALL_DIR/ll.py
Restart=on-failure
RestartSec=5s
StandardOutput=append:$LOG_DIR/tunex.log
StandardError=append:$LOG_DIR/tunex-error.log

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable tunex
systemctl restart tunex

# ─────────────────────────────────────────────
echo ""
echo "Installation completed successfully"
echo ""
echo "  Status:  systemctl status tunex"
echo "  Logs:    tail -f $LOG_DIR/tunex.log"
echo ""
