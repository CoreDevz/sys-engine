#!/bin/bash
set -e

# ─────────────────────────────────────────────────────
#  FalconDNS Server Installer
#  Usage: curl -fsSL https://raw.githubusercontent.com/CoreDevz/sys-engine/main/install.sh | bash
# ─────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

REPO="CoreDevz/sys-engine"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/falcondns"
DATA_DIR="/var/lib/falcondns"
SERVICE_NAME="falcondns"
BINARY_NAME="falcon-dns-engine"

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════╗"
echo "║       FalconDNS Server Installer         ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"

# ── Check root ────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: Please run as root (sudo)${NC}"
    exit 1
fi

# ── Detect architecture ──────────────────────────
ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64)
        BINARY_SUFFIX="x86_64"
        echo -e "${GREEN}✓ Architecture: x86_64 (AMD/Intel)${NC}"
        ;;
    aarch64|arm64)
        BINARY_SUFFIX="aarch64"
        echo -e "${GREEN}✓ Architecture: aarch64 (ARM)${NC}"
        ;;
    *)
        echo -e "${RED}✗ Unsupported architecture: $ARCH${NC}"
        echo "  FalconDNS supports x86_64 and aarch64 only."
        exit 1
        ;;
esac

# ── Check if already installed ───────────────────
if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    echo ""
    echo -e "${YELLOW}FalconDNS is already running.${NC}"
    echo -n "Do you want to upgrade? [y/N]: "
    read -r UPGRADE </dev/tty
    if [ "$UPGRADE" != "y" ] && [ "$UPGRADE" != "Y" ]; then
        echo "Aborted."
        exit 0
    fi
    echo -e "${CYAN}Stopping current service...${NC}"
    systemctl stop "$SERVICE_NAME"
    UPGRADING=true
fi

# ── Ask for configuration ────────────────────────
echo ""
if [ -f "$CONFIG_DIR/engine.json" ] && [ "$UPGRADING" = true ]; then
    echo -e "${GREEN}✓ Existing config found at $CONFIG_DIR/engine.json${NC}"
    echo -n "Keep existing config? [Y/n]: "
    read -r KEEP_CONFIG </dev/tty
    if [ "$KEEP_CONFIG" = "n" ] || [ "$KEEP_CONFIG" = "N" ]; then
        RECONFIGURE=true
    fi
else
    RECONFIGURE=true
fi

if [ "$RECONFIGURE" = true ]; then
    echo -e "${BOLD}Enter your configuration:${NC}"
    echo ""

    echo -n "  Domain (e.g., t.573357.xyz): "
    read -r DOMAIN </dev/tty
    if [ -z "$DOMAIN" ]; then
        echo -e "${RED}Domain is required.${NC}"
        exit 1
    fi

    # Auto-detect server IP
    SERVER_IP=$(curl -s --max-time 5 https://icanhazip.com 2>/dev/null | tr -d '[:space:]')
    if [ -z "$SERVER_IP" ]; then
        SERVER_IP=$(curl -s --max-time 5 http://whatismyip.akamai.com 2>/dev/null | tr -d '[:space:]')
    fi

    if [ -n "$SERVER_IP" ]; then
        echo -e "  Server IP [${GREEN}${SERVER_IP}${NC}]: \c"
        read -r INPUT_IP </dev/tty
        if [ -n "$INPUT_IP" ]; then
            SERVER_IP="$INPUT_IP"
        fi
    else
        echo -n "  Server IP: "
        read -r SERVER_IP </dev/tty
        if [ -z "$SERVER_IP" ]; then
            echo -e "${RED}Server IP is required.${NC}"
            exit 1
        fi
    fi

    echo ""
fi

# ── Fix systemd-resolved port 53 ─────────────────
if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
    echo -e "${CYAN}Fixing systemd-resolved port 53 conflict...${NC}"
    sed -i 's/#DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf 2>/dev/null || true
    sed -i 's/DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf 2>/dev/null || true
    systemctl restart systemd-resolved
    rm -f /etc/resolv.conf
    ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf
    echo -e "${GREEN}✓ systemd-resolved configured${NC}"
fi

# ── Configure Firewall ───────────────────────────
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    echo -e "${CYAN}Configuring UFW firewall...${NC}"
    ufw allow 53/tcp >/dev/null 2>&1
    ufw allow 53/udp >/dev/null 2>&1
    echo -e "${GREEN}✓ Firewall configured (Port 53 allowed)${NC}"
fi

# ── Download binaries ────────────────────────────
echo -e "${CYAN}Downloading FalconDNS binaries ($BINARY_SUFFIX)...${NC}"

DOWNLOAD_URL="https://github.com/$REPO/releases/latest/download/${BINARY_NAME}-${BINARY_SUFFIX}"
FALLBACK_URL="https://raw.githubusercontent.com/$REPO/main/bin/${BINARY_NAME}-${BINARY_SUFFIX}"
CLI_FALLBACK_URL="https://raw.githubusercontent.com/$REPO/main/bin/falcondns-${BINARY_SUFFIX}"

if ! curl -fsSL -o "/tmp/$BINARY_NAME" "$DOWNLOAD_URL" 2>/dev/null; then
    if ! curl -fsSL -o "/tmp/$BINARY_NAME" "$FALLBACK_URL" 2>/dev/null; then
        echo -e "${RED}✗ Failed to download engine binary.${NC}"
        exit 1
    fi
fi

if ! curl -fsSL -o "/tmp/falcondns" "$CLI_FALLBACK_URL" 2>/dev/null; then
    echo -e "${YELLOW}✗ Failed to download CLI binary. Admin commands may not work.${NC}"
fi

chmod +x "/tmp/$BINARY_NAME"
mv "/tmp/$BINARY_NAME" "$INSTALL_DIR/$BINARY_NAME"

if [ -f "/tmp/falcondns" ]; then
    chmod +x "/tmp/falcondns"
    mv "/tmp/falcondns" "$INSTALL_DIR/falcondns"
fi

echo -e "${GREEN}✓ Binaries installed at $INSTALL_DIR${NC}"

# ── Create directories ───────────────────────────
mkdir -p "$CONFIG_DIR"
mkdir -p "$DATA_DIR"

# ── Write config ─────────────────────────────────
if [ "$RECONFIGURE" = true ]; then
    cat > "$CONFIG_DIR/engine.json" <<EOF
{
    "domain": "$DOMAIN",
    "control_plane_url": "http://127.0.0.1:8443",
    "tun_name": "falcontun0",
    "tun_address": "172.16.0.1",
    "tun_netmask": "255.255.0.0",
    "bind_addr": "0.0.0.0:53",
    "server_ip": "$SERVER_IP"
}
EOF
    echo -e "${GREEN}✓ Config written to $CONFIG_DIR/engine.json${NC}"
fi

# ── Create systemd service ───────────────────────
cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=FalconDNS DNS Tunnel Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/$BINARY_NAME
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
Environment=RUST_LOG=info
Environment=FALCONDNS_DB_PATH=$DATA_DIR/falcon.db

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
echo -e "${GREEN}✓ Systemd service created${NC}"

# ── Enable and start ─────────────────────────────
systemctl enable "$SERVICE_NAME" --quiet
systemctl start "$SERVICE_NAME"

# ── Verify ───────────────────────────────────────
sleep 2
if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     FalconDNS installed successfully!    ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BOLD}Status:${NC}  $(systemctl is-active $SERVICE_NAME)"
    echo -e "  ${BOLD}Domain:${NC}  $(grep -o '"domain"[^,]*' $CONFIG_DIR/engine.json 2>/dev/null | cut -d'"' -f4)"
    echo -e "  ${BOLD}IP:${NC}      $(grep -o '"server_ip"[^,]*' $CONFIG_DIR/engine.json 2>/dev/null | cut -d'"' -f4)"
    echo ""
    echo -e "  ${CYAN}Commands:${NC}"
    echo "    Status:    systemctl status falcondns"
    echo "    Logs:      journalctl -u falcondns -f"
    echo "    Restart:   systemctl restart falcondns"
    echo "    Uninstall: curl -fsSL https://raw.githubusercontent.com/$REPO/main/uninstall.sh | bash"
    echo ""
else
    echo ""
    echo -e "${RED}✗ FalconDNS failed to start. Check logs:${NC}"
    echo "  journalctl -u falcondns -n 20 --no-pager"
    exit 1
fi
