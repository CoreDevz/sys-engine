#!/bin/bash
set -e

# ─────────────────────────────────────────────────────
#  FalconDNS Server Uninstaller
#  Usage: curl -fsSL https://raw.githubusercontent.com/CoreDevz/sys-engine/main/uninstall.sh | bash
# ─────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

SERVICE_NAME="falcondns"
BINARY_PATH="/usr/local/bin/falcon-dns-engine"
CONFIG_DIR="/etc/falcondns"
DATA_DIR="/var/lib/falcondns"

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════╗"
echo "║      FalconDNS Server Uninstaller        ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"

# ── Check root ────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: Please run as root (sudo)${NC}"
    exit 1
fi

# ── Check if installed ───────────────────────────
if [ ! -f "$BINARY_PATH" ] && ! systemctl list-unit-files | grep -q "$SERVICE_NAME"; then
    echo -e "${YELLOW}FalconDNS does not appear to be installed.${NC}"
    exit 0
fi

# ── Confirm ──────────────────────────────────────
echo -e "${YELLOW}This will completely remove FalconDNS from this server.${NC}"
echo ""
echo "  The following will be deleted:"
echo "    • Service:  /etc/systemd/system/${SERVICE_NAME}.service"
echo "    • Binary:   $BINARY_PATH"
echo "    • Config:   $CONFIG_DIR/"
echo "    • Data:     $DATA_DIR/"
echo ""
echo -n "Are you sure? [y/N]: "
read -r CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "Aborted."
    exit 0
fi

# ── Stop and disable service ─────────────────────
echo ""
if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    echo -e "${CYAN}Stopping FalconDNS...${NC}"
    systemctl stop "$SERVICE_NAME"
    echo -e "${GREEN}✓ Service stopped${NC}"
fi

if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
    systemctl disable "$SERVICE_NAME" --quiet 2>/dev/null
    echo -e "${GREEN}✓ Service disabled${NC}"
fi

# ── Remove service file ──────────────────────────
if [ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]; then
    rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    systemctl daemon-reload
    echo -e "${GREEN}✓ Service file removed${NC}"
fi

# ── Remove binary ────────────────────────────────
if [ -f "$BINARY_PATH" ]; then
    rm -f "$BINARY_PATH"
    echo -e "${GREEN}✓ Binary removed${NC}"
fi

# ── Remove config ────────────────────────────────
if [ -d "$CONFIG_DIR" ]; then
    rm -rf "$CONFIG_DIR"
    echo -e "${GREEN}✓ Config removed${NC}"
fi

# ── Remove data ──────────────────────────────────
if [ -d "$DATA_DIR" ]; then
    rm -rf "$DATA_DIR"
    echo -e "${GREEN}✓ Data removed${NC}"
fi

# ── Remove TUN interface ─────────────────────────
if ip link show falcontun0 &>/dev/null; then
    ip link delete falcontun0 2>/dev/null || true
    echo -e "${GREEN}✓ TUN interface removed${NC}"
fi

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   FalconDNS completely uninstalled! ✓    ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
