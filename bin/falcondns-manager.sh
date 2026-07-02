#!/usr/bin/env bash
#
# FalconDNS — Terminal Management UI
# Interactive TUI for managing users, sessions, and server
#
# Install: cp falcondns-manager.sh /usr/local/bin/falcondns && chmod +x /usr/local/bin/falcondns
# Usage:   falcondns
#

# ─── Colors & Styles ───────────────────────────────────────────────────────────
R='\033[0m'         # Reset
B='\033[1m'         # Bold
DIM='\033[2m'       # Dim
UL='\033[4m'        # Underline
BLINK='\033[5m'

# Foreground
BLK='\033[30m'      # Black
RED='\033[31m'
GRN='\033[32m'
YEL='\033[33m'
BLU='\033[34m'
MAG='\033[35m'
CYN='\033[36m'
WHT='\033[37m'

# Bright foreground
BRED='\033[91m'
BGRN='\033[92m'
BYEL='\033[93m'
BBLU='\033[94m'
BMAG='\033[95m'
BCYN='\033[96m'
BWHT='\033[97m'

# Backgrounds
BG_BLU='\033[44m'
BG_CYN='\033[46m'
BG_GRN='\033[42m'
BG_RED='\033[41m'
BG_MAG='\033[45m'
BG_DK='\033[48;5;236m'
BG_DKBLUE='\033[48;5;17m'

# ─── Paths ─────────────────────────────────────────────────────────────────────
DB_PATH="/var/lib/falcondns/falcon.db"
CONFIG_PATH="/etc/falcondns/engine.json"
SERVICE_NAME="falcondns"
BINARY_PATH="/usr/local/bin/falcon-dns-engine"

# ─── Helpers ───────────────────────────────────────────────────────────────────
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}${B}✗ This tool must be run as root.${R}"
        echo -e "  Use: ${CYN}sudo falcondns${R}"
        exit 1
    fi
}

check_deps() {
    if ! command -v sqlite3 &>/dev/null; then
        echo -e "${YEL}Installing sqlite3...${R}"
        apt-get update -qq && apt-get install -y -qq sqlite3 >/dev/null 2>&1
    fi
}

# Generate random hex string
rand_hex() {
    local len=${1:-32}
    head -c $((len/2)) /dev/urandom | xxd -p | tr -d '\n' | head -c "$len"
}

# Generate a subscription ID (8 chars)
gen_sub_id() {
    rand_hex 16 | head -c 8
}

# Generate a user key (64 hex = 32 bytes)
gen_user_key() {
    rand_hex 64
}

# Format bytes to human readable
format_bytes() {
    local bytes=$1
    if [[ $bytes -ge 1073741824 ]]; then
        echo "$(echo "scale=2; $bytes / 1073741824" | bc) GB"
    elif [[ $bytes -ge 1048576 ]]; then
        echo "$(echo "scale=1; $bytes / 1048576" | bc) MB"
    elif [[ $bytes -ge 1024 ]]; then
        echo "$(echo "scale=0; $bytes / 1024" | bc) KB"
    else
        echo "${bytes} B"
    fi
}

# ─── UI Components ─────────────────────────────────────────────────────────────

clear_screen() {
    clear
}

print_header() {
    echo ""
    echo -e "  ${BG_CYN}${BLK}${B}  FALCONDNS MANAGER  ${R} ${DIM}— DNS Tunneling VPN Engine${R}"
    echo ""
}

print_server_status() {
    local status
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        status="${BGRN}${B}● RUNNING${R}"
    else
        status="${BRED}${B}● STOPPED${R}"
    fi

    local domain="N/A"
    local vps_ip="N/A"
    if [[ -f "$CONFIG_PATH" ]]; then
        domain=$(grep -oP '"domain"\s*:\s*"\K[^"]+' "$CONFIG_PATH" 2>/dev/null || echo "N/A")
        vps_ip=$(grep -oP '"server_ip"\s*:\s*"\K[^"]+' "$CONFIG_PATH" 2>/dev/null || echo "N/A")
    fi

    local user_count=0
    local active_count=0
    local session_count=0
    if [[ -f "$DB_PATH" ]]; then
        user_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users;" 2>/dev/null || echo 0)
        active_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users WHERE status='active';" 2>/dev/null || echo 0)
        session_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM active_sessions;" 2>/dev/null || echo 0)
    fi

    echo -e "  ${BG_DK} ${B}Server${R}${BG_DK}: $status ${BG_DK}  ${B}Domain${R}${BG_DK}: ${BCYN}$domain${R}${BG_DK}  ${B}IP${R}${BG_DK}: ${BCYN}$vps_ip${R}${BG_DK} ${R}"
    echo -e "  ${DIM}Users: ${BWHT}$user_count${R}${DIM} total, ${BGRN}$active_count${R}${DIM} active  │  Sessions: ${BYEL}$session_count${R}${DIM} online${R}"
    echo ""
}

print_menu() {
    echo -e "  ${BCYN}${B}─── USER MANAGEMENT ───────────────────────────────────${R}"
    echo -e "  ${BWHT}${B}  1${R} ${DIM}│${R} ${WHT}Create User${R}"
    echo -e "  ${BWHT}${B}  2${R} ${DIM}│${R} ${WHT}List Users${R}"
    echo -e "  ${BWHT}${B}  3${R} ${DIM}│${R} ${WHT}Delete User${R}"
    echo -e "  ${BWHT}${B}  4${R} ${DIM}│${R} ${WHT}Toggle HWID Lock${R}          ${DIM}(enable/disable device binding)${R}"
    echo -e "  ${BWHT}${B}  5${R} ${DIM}│${R} ${WHT}Set Expiry Date${R}"
    echo -e "  ${BWHT}${B}  6${R} ${DIM}│${R} ${WHT}Reset Bandwidth${R}"
    echo -e "  ${BWHT}${B}  7${R} ${DIM}│${R} ${WHT}Enable/Disable User${R}"
    echo ""
    echo -e "  ${BCYN}${B}─── SERVER CONTROL ────────────────────────────────────${R}"
    echo -e "  ${BWHT}${B}  8${R} ${DIM}│${R} ${WHT}Server Status & Logs${R}"
    echo -e "  ${BWHT}${B}  9${R} ${DIM}│${R} ${WHT}Restart Server${R}"
    echo -e "  ${BWHT}${B} 10${R} ${DIM}│${R} ${WHT}Online Users (Active Sessions)${R}"
    echo ""
    echo -e "  ${BCYN}${B}─── SYSTEM ────────────────────────────────────────────${R}"
    echo -e "  ${BWHT}${B} 11${R} ${DIM}│${R} ${BRED}Uninstall FalconDNS${R}"
    echo -e "  ${BWHT}${B}  0${R} ${DIM}│${R} ${DIM}Exit${R}"
    echo ""
}

# ─── Functions ─────────────────────────────────────────────────────────────────

create_user() {
    clear_screen
    echo -e "\n  ${BCYN}${B}═══ CREATE NEW USER ═══${R}\n"

    echo -ne "  ${CYN}Name ${DIM}(display name, optional)${R}: "
    read -r name

    echo -ne "  ${CYN}Subscription ID ${DIM}(leave blank for auto)${R}: "
    read -r sub_id
    if [[ -z "$sub_id" ]]; then
        sub_id=$(gen_sub_id)
        echo -e "  ${DIM}Generated: ${BCYN}$sub_id${R}"
    fi

    # Check if sub_id already exists
    local existing
    existing=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users WHERE sub_id='$sub_id';" 2>/dev/null)
    if [[ "$existing" -gt 0 ]]; then
        echo -e "\n  ${BRED}✗ User '$sub_id' already exists!${R}"
        press_enter
        return
    fi

    echo -ne "  ${CYN}User Key ${DIM}(leave blank for auto-generate)${R}: "
    read -r user_key
    if [[ -z "$user_key" ]]; then
        user_key=$(gen_user_key)
        echo -e "  ${DIM}Generated key${R}"
    fi

    echo -ne "  ${CYN}Duration in days ${DIM}(blank=never)${R}: "
    read -r days
    local expiry="Never"
    local expiry_sql="NULL"
    if [[ -n "$days" && "$days" =~ ^[0-9]+$ ]]; then
        expiry=$(date -d "+$days days" "+%Y-%m-%d" 2>/dev/null)
        expiry_sql="'$expiry'"
    elif [[ -n "$days" ]]; then
        echo -e "  ${BRED}Invalid days, setting to Never.${R}"
    fi

    echo -ne "  ${CYN}Bandwidth Limit ${DIM}(GB, default=10)${R}: "
    read -r bw_gb
    if [[ -z "$bw_gb" ]]; then
        bw_gb=10
    fi
    local bw_bytes=$((bw_gb * 1073741824))

    echo -ne "  ${CYN}Enable HWID Lock? ${DIM}(y/N)${R}: "
    read -r hwid_choice

    # Insert user
    local name_sql="NULL"
    if [[ -n "$name" ]]; then
        name_sql="'$name'"
    fi

    sqlite3 "$DB_PATH" "INSERT INTO users (sub_id, user_key, status, bandwidth_allowed, bandwidth_used, expiry_date, name) VALUES ('$sub_id', '$user_key', 'active', $bw_bytes, 0, $expiry_sql, $name_sql);"

    if [[ "$hwid_choice" =~ ^[Yy] ]]; then
        echo -e "  ${DIM}HWID lock will activate on first connection${R}"
    else
        # Set a special marker to skip HWID enforcement
        sqlite3 "$DB_PATH" "UPDATE users SET hardware_id = 'DISABLED' WHERE sub_id='$sub_id';"
    fi

    echo ""
    echo -e "  ${BGRN}${B}╔════════════════════════════════════════════╗${R}"
    echo -e "  ${BGRN}${B}║${R}  ${BGRN}✓ User created successfully!${R}               ${BGRN}${B}║${R}"
    echo -e "  ${BGRN}${B}╚════════════════════════════════════════════╝${R}"
    echo ""
    echo -e "  ${B}Subscription ID${R} : ${BCYN}$sub_id${R}"
    echo -e "  ${B}User Key${R}        : ${BYEL}$user_key${R}"
    echo -e "  ${B}Name${R}            : ${WHT}${name:-N/A}${R}"
    echo -e "  ${B}Expiry${R}          : ${WHT}${expiry:-Never}${R}"
    echo -e "  ${B}Bandwidth${R}       : ${WHT}${bw_gb} GB${R}"
    echo -e "  ${B}HWID Lock${R}       : ${WHT}$(if [[ "$hwid_choice" =~ ^[Yy] ]]; then echo "Enabled"; else echo "${BYEL}Disabled${R}"; fi)${R}"
    echo ""
    local domain="N/A"
    local vps_ip="N/A"
    if [[ -f "$CONFIG_PATH" ]]; then
        domain=$(grep -oP '"domain"\s*:\s*"\K[^"]+' "$CONFIG_PATH" 2>/dev/null || echo "N/A")
        vps_ip=$(grep -oP '"server_ip"\s*:\s*"\K[^"]+' "$CONFIG_PATH" 2>/dev/null || echo "N/A")
    fi
    local json="{\"d\":\"$domain\",\"i\":\"$vps_ip\",\"s\":\"$sub_id\",\"k\":\"$user_key\"}"
    local b64=$(echo -n "$json" | base64 | tr -d '\n')

    echo -e "  ${DIM}Share these credentials with your client:${R}"
    echo -e "  ${BG_DK} Sub ID: ${BCYN}${B}$sub_id${R}${BG_DK}  Key: ${BYEL}${B}$user_key${R}${BG_DK} ${R}"
    echo ""
    echo -e "  ${B}Quick Connect Code:${R}"
    echo -e "  ${BCYN}falcon://${b64}${R}"
    echo ""

    press_enter
}

list_users() {
    clear_screen
    echo -e "\n  ${BCYN}${B}═══ ALL USERS ═══${R}\n"

    local count
    count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users;")

    if [[ "$count" -eq 0 ]]; then
        echo -e "  ${DIM}No users found. Create one from the main menu.${R}"
        press_enter
        return
    fi

    # Header
    printf "  ${B}${BCYN}%-10s %-14s %-8s %-12s %-12s %-10s %-6s${R}\n" \
        "SUB_ID" "NAME" "STATUS" "EXPIRY" "BANDWIDTH" "HWID" "SESS"

    echo -e "  ${DIM}──────────────────────────────────────────────────────────────────────────────${R}"

    # Rows
    sqlite3 -separator '|' "$DB_PATH" "
        SELECT u.sub_id, COALESCE(u.name,'—'), u.status, COALESCE(u.expiry_date,'Never'),
               u.bandwidth_used, u.bandwidth_allowed,
               CASE WHEN u.hardware_id IS NULL THEN 'Locked'
                    WHEN u.hardware_id = 'DISABLED' THEN 'Off'
                    ELSE 'Locked' END,
               (SELECT COUNT(*) FROM active_sessions a WHERE a.sub_id = u.sub_id)
        FROM users u ORDER BY u.created_at DESC;
    " 2>/dev/null | while IFS='|' read -r sid uname status expiry bw_used bw_allowed hwid sessions; do
        local status_color="${BGRN}"
        if [[ "$status" == "disabled" ]] || [[ "$status" == "expired" ]]; then
            status_color="${BRED}"
        fi

        local hwid_color="${DIM}"
        if [[ "$hwid" == "Off" ]]; then
            hwid_color="${BYEL}"
        fi

        local bw_str
        bw_str="$(format_bytes "$bw_used")/$(format_bytes "$bw_allowed")"

        local sess_color="${DIM}"
        if [[ "$sessions" -gt 0 ]]; then
            sess_color="${BGRN}"
        fi

        printf "  %-10s %-14s ${status_color}%-8s${R} %-12s %-12s ${hwid_color}%-10s${R} ${sess_color}%-6s${R}\n" \
            "$sid" "${uname:0:13}" "$status" "$expiry" "${bw_str:0:11}" "$hwid" "$sessions"
    done

    echo ""
    echo -e "  ${DIM}Total: $count users${R}"
    echo ""
    press_enter
}

delete_user() {
    clear_screen
    echo -e "\n  ${BCYN}${B}═══ DELETE USER ═══${R}\n"

    echo -ne "  ${CYN}Enter Sub ID to delete${R}: "
    read -r sub_id

    if [[ -z "$sub_id" ]]; then
        echo -e "  ${BRED}✗ Sub ID cannot be empty${R}"
        press_enter
        return
    fi

    local exists
    exists=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users WHERE sub_id='$sub_id';" 2>/dev/null)
    if [[ "$exists" -eq 0 ]]; then
        echo -e "  ${BRED}✗ User '$sub_id' not found${R}"
        press_enter
        return
    fi

    local name
    name=$(sqlite3 "$DB_PATH" "SELECT COALESCE(name, sub_id) FROM users WHERE sub_id='$sub_id';" 2>/dev/null)

    echo -ne "  ${BRED}${B}Are you sure you want to delete '${name}'?${R} (y/N): "
    read -r confirm

    if [[ "$confirm" =~ ^[Yy] ]]; then
        sqlite3 "$DB_PATH" "DELETE FROM active_sessions WHERE sub_id='$sub_id';"
        sqlite3 "$DB_PATH" "DELETE FROM users WHERE sub_id='$sub_id';"
        echo -e "  ${BGRN}✓ User '$name' deleted${R}"
    else
        echo -e "  ${DIM}Cancelled${R}"
    fi

    press_enter
}

toggle_hwid() {
    clear_screen
    echo -e "\n  ${BCYN}${B}═══ TOGGLE HWID LOCK ═══${R}\n"

    echo -ne "  ${CYN}Enter Sub ID${R}: "
    read -r sub_id

    if [[ -z "$sub_id" ]]; then
        echo -e "  ${BRED}✗ Sub ID cannot be empty${R}"
        press_enter
        return
    fi

    local hwid
    hwid=$(sqlite3 "$DB_PATH" "SELECT hardware_id FROM users WHERE sub_id='$sub_id';" 2>/dev/null)

    if [[ -z "$hwid" ]]; then
        # Check if user exists at all
        local exists
        exists=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users WHERE sub_id='$sub_id';" 2>/dev/null)
        if [[ "$exists" -eq 0 ]]; then
            echo -e "  ${BRED}✗ User '$sub_id' not found${R}"
            press_enter
            return
        fi
        echo -e "  ${DIM}Current HWID: ${BGRN}Enabled${R} ${DIM}(will lock on first connect)${R}"
    elif [[ "$hwid" == "DISABLED" ]]; then
        echo -e "  ${DIM}Current HWID: ${BYEL}Disabled${R} ${DIM}(any device can connect)${R}"
    else
        echo -e "  ${DIM}Current HWID: ${BGRN}Locked${R} ${DIM}(bound to: ${BCYN}${hwid:0:16}...${R}${DIM})${R}"
    fi

    echo ""
    echo -e "  ${B}1${R} ${DIM}│${R} Enable HWID Lock ${DIM}(reset — locks on next connect)${R}"
    echo -e "  ${B}2${R} ${DIM}│${R} Disable HWID Lock ${DIM}(anyone can use this account)${R}"
    echo -e "  ${B}0${R} ${DIM}│${R} Cancel"
    echo ""
    echo -ne "  ${CYN}Choice${R}: "
    read -r choice

    case $choice in
        1)
            sqlite3 "$DB_PATH" "UPDATE users SET hardware_id = NULL WHERE sub_id='$sub_id';"
            echo -e "  ${BGRN}✓ HWID lock enabled — will lock on next connection${R}"
            ;;
        2)
            sqlite3 "$DB_PATH" "UPDATE users SET hardware_id = 'DISABLED' WHERE sub_id='$sub_id';"
            echo -e "  ${BYEL}✓ HWID lock disabled — any device can connect${R}"
            ;;
        *)
            echo -e "  ${DIM}Cancelled${R}"
            ;;
    esac

    press_enter
}

set_expiry() {
    clear_screen
    echo -e "\n  ${BCYN}${B}═══ SET EXPIRY DATE ═══${R}\n"

    echo -ne "  ${CYN}Enter Sub ID${R}: "
    read -r sub_id

    local exists
    exists=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users WHERE sub_id='$sub_id';" 2>/dev/null)
    if [[ "$exists" -eq 0 ]]; then
        echo -e "  ${BRED}✗ User '$sub_id' not found${R}"
        press_enter
        return
    fi

    local current_expiry
    current_expiry=$(sqlite3 "$DB_PATH" "SELECT COALESCE(expiry_date, 'Never') FROM users WHERE sub_id='$sub_id';" 2>/dev/null)
    echo -e "  ${DIM}Current expiry: ${BWHT}$current_expiry${R}"
    echo ""

    echo -e "  ${B}1${R} ${DIM}│${R} Set to ${BWHT}30 days${R} from now"
    echo -e "  ${B}2${R} ${DIM}│${R} Set to ${BWHT}60 days${R} from now"
    echo -e "  ${B}3${R} ${DIM}│${R} Set to ${BWHT}90 days${R} from now"
    echo -e "  ${B}4${R} ${DIM}│${R} Set ${BWHT}custom date${R} (YYYY-MM-DD)"
    echo -e "  ${B}5${R} ${DIM}│${R} Remove expiry ${DIM}(never expires)${R}"
    echo -e "  ${B}0${R} ${DIM}│${R} Cancel"
    echo ""
    echo -ne "  ${CYN}Choice${R}: "
    read -r choice

    case $choice in
        1) expiry=$(date -d "+30 days" "+%Y-%m-%d" 2>/dev/null) ;;
        2) expiry=$(date -d "+60 days" "+%Y-%m-%d" 2>/dev/null) ;;
        3) expiry=$(date -d "+90 days" "+%Y-%m-%d" 2>/dev/null) ;;
        4)
            echo -ne "  ${CYN}Enter date (YYYY-MM-DD)${R}: "
            read -r expiry
            ;;
        5)
            sqlite3 "$DB_PATH" "UPDATE users SET expiry_date = NULL, status = 'active' WHERE sub_id='$sub_id';"
            echo -e "  ${BGRN}✓ Expiry removed — user never expires${R}"
            press_enter
            return
            ;;
        *)
            echo -e "  ${DIM}Cancelled${R}"
            press_enter
            return
            ;;
    esac

    if [[ -n "$expiry" ]]; then
        sqlite3 "$DB_PATH" "UPDATE users SET expiry_date = '$expiry', status = 'active' WHERE sub_id='$sub_id';"
        echo -e "  ${BGRN}✓ Expiry set to: ${BWHT}$expiry${R}"
    fi

    press_enter
}

reset_bandwidth() {
    clear_screen
    echo -e "\n  ${BCYN}${B}═══ RESET BANDWIDTH ═══${R}\n"

    echo -ne "  ${CYN}Enter Sub ID (or 'all' for all users)${R}: "
    read -r sub_id

    if [[ "$sub_id" == "all" ]]; then
        echo -ne "  ${BYEL}Reset bandwidth for ALL users?${R} (y/N): "
        read -r confirm
        if [[ "$confirm" =~ ^[Yy] ]]; then
            sqlite3 "$DB_PATH" "UPDATE users SET bandwidth_used = 0;"
            echo -e "  ${BGRN}✓ Bandwidth reset for all users${R}"
        fi
    else
        local exists
        exists=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users WHERE sub_id='$sub_id';" 2>/dev/null)
        if [[ "$exists" -eq 0 ]]; then
            echo -e "  ${BRED}✗ User '$sub_id' not found${R}"
        else
            sqlite3 "$DB_PATH" "UPDATE users SET bandwidth_used = 0 WHERE sub_id='$sub_id';"
            echo -e "  ${BGRN}✓ Bandwidth reset for $sub_id${R}"
        fi
    fi

    press_enter
}

toggle_user_status() {
    clear_screen
    echo -e "\n  ${BCYN}${B}═══ ENABLE/DISABLE USER ═══${R}\n"

    echo -ne "  ${CYN}Enter Sub ID${R}: "
    read -r sub_id

    local current
    current=$(sqlite3 "$DB_PATH" "SELECT status FROM users WHERE sub_id='$sub_id';" 2>/dev/null)

    if [[ -z "$current" ]]; then
        echo -e "  ${BRED}✗ User '$sub_id' not found${R}"
        press_enter
        return
    fi

    echo -e "  ${DIM}Current status: ${BWHT}$current${R}"
    echo ""

    if [[ "$current" == "active" ]]; then
        echo -ne "  ${BYEL}Disable this user?${R} (y/N): "
        read -r confirm
        if [[ "$confirm" =~ ^[Yy] ]]; then
            sqlite3 "$DB_PATH" "UPDATE users SET status = 'disabled' WHERE sub_id='$sub_id';"
            sqlite3 "$DB_PATH" "DELETE FROM active_sessions WHERE sub_id='$sub_id';"
            echo -e "  ${BRED}✓ User disabled and sessions cleared${R}"
        fi
    else
        echo -ne "  ${BGRN}Enable this user?${R} (y/N): "
        read -r confirm
        if [[ "$confirm" =~ ^[Yy] ]]; then
            sqlite3 "$DB_PATH" "UPDATE users SET status = 'active' WHERE sub_id='$sub_id';"
            echo -e "  ${BGRN}✓ User enabled${R}"
        fi
    fi

    press_enter
}

server_status() {
    clear_screen
    echo -e "\n  ${BCYN}${B}═══ SERVER STATUS ═══${R}\n"

    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        echo -e "  ${BGRN}${B}● Service is RUNNING${R}"
    else
        echo -e "  ${BRED}${B}● Service is STOPPED${R}"
    fi
    echo ""

    echo -e "  ${B}${CYN}System Info:${R}"
    echo -e "  ${DIM}Uptime       :${R} $(uptime -p 2>/dev/null || echo 'N/A')"
    echo -e "  ${DIM}Memory       :${R} $(free -h 2>/dev/null | awk '/^Mem:/ {print $3 " / " $2}' || echo 'N/A')"
    echo -e "  ${DIM}Load Average :${R} $(cat /proc/loadavg 2>/dev/null | awk '{print $1, $2, $3}' || echo 'N/A')"

    local pid
    pid=$(pgrep -f falcon-dns-engine 2>/dev/null | head -1)
    if [[ -n "$pid" ]]; then
        echo -e "  ${DIM}Process PID  :${R} $pid"
        echo -e "  ${DIM}Process Mem  :${R} $(ps -p "$pid" -o rss= 2>/dev/null | awk '{printf "%.1f MB", $1/1024}' || echo 'N/A')"
    fi

    echo ""
    echo -e "  ${B}${CYN}Recent Logs (last 20 lines):${R}"
    echo -e "  ${DIM}────────────────────────────────────────${R}"
    journalctl -u "$SERVICE_NAME" --no-pager -n 20 2>/dev/null | while read -r line; do
        echo -e "  ${DIM}$line${R}"
    done

    echo ""
    press_enter
}

restart_server() {
    echo ""
    echo -ne "  ${BYEL}Restart FalconDNS server?${R} (y/N): "
    read -r confirm

    if [[ "$confirm" =~ ^[Yy] ]]; then
        echo -e "  ${DIM}Restarting...${R}"
        systemctl restart "$SERVICE_NAME" 2>/dev/null
        sleep 2
        if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
            echo -e "  ${BGRN}${B}✓ Server restarted successfully${R}"
        else
            echo -e "  ${BRED}${B}✗ Server failed to start${R}"
            echo -e "  ${DIM}Check logs: journalctl -u $SERVICE_NAME -n 30${R}"
        fi
    else
        echo -e "  ${DIM}Cancelled${R}"
    fi

    press_enter
}

online_users() {
    clear_screen
    echo -e "\n  ${BCYN}${B}═══ ONLINE USERS (Active Sessions) ═══${R}\n"

    local count
    count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM active_sessions;" 2>/dev/null)

    if [[ "$count" -eq 0 ]]; then
        echo -e "  ${DIM}No active sessions.${R}"
        press_enter
        return
    fi

    printf "  ${B}${BCYN}%-10s %-14s %-16s %-20s${R}\n" \
        "SUB_ID" "NAME" "VIRTUAL_IP" "LAST_SEEN"

    echo -e "  ${DIM}────────────────────────────────────────────────────────────────${R}"

    sqlite3 -separator '|' "$DB_PATH" "
        SELECT a.sub_id, COALESCE(u.name, '—'), a.assigned_virtual_ip, a.last_seen
        FROM active_sessions a
        LEFT JOIN users u ON a.sub_id = u.sub_id
        ORDER BY a.last_seen DESC;
    " 2>/dev/null | while IFS='|' read -r sid uname vip last_seen; do
        printf "  ${BGRN}%-10s${R} %-14s %-16s ${DIM}%-20s${R}\n" \
            "$sid" "${uname:0:13}" "$vip" "$last_seen"
    done

    echo ""
    echo -e "  ${DIM}Total sessions: $count${R}"
    echo ""
    press_enter
}

uninstall_server() {
    clear_screen
    echo -e "\n  ${BRED}${B}═══ UNINSTALL FALCONDNS ═══${R}\n"
    echo -e "  ${BRED}This will:${R}"
    echo -e "  ${DIM} • Stop and disable the service${R}"
    echo -e "  ${DIM} • Remove the binary${R}"
    echo -e "  ${DIM} • Delete all configuration${R}"
    echo -e "  ${DIM} • Delete the user database${R}"
    echo -e "  ${DIM} • Remove TUN interfaces${R}"
    echo -e "  ${DIM} • Remove this management tool${R}"
    echo ""

    echo -ne "  ${BRED}${B}Type 'UNINSTALL' to confirm${R}: "
    read -r confirm

    if [[ "$confirm" == "UNINSTALL" ]]; then
        echo ""
        echo -e "  ${DIM}Stopping service...${R}"
        systemctl stop "$SERVICE_NAME" 2>/dev/null || true
        systemctl disable "$SERVICE_NAME" 2>/dev/null || true
        rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
        pkill -f falcon-dns-engine 2>/dev/null || true
        systemctl daemon-reload

        echo -e "  ${DIM}Removing binaries...${R}"
        rm -f "$BINARY_PATH"

        echo -e "  ${DIM}Removing config and data...${R}"
        rm -rf /etc/falcondns
        rm -rf /var/lib/falcondns
        rm -rf /opt/falcondns

        echo -e "  ${DIM}Cleaning TUN interfaces...${R}"
        ip link delete falcontun0 2>/dev/null || true
        ip link delete tun0 2>/dev/null || true

        echo -e "  ${DIM}Removing manager tool...${R}"
        local self_path
        self_path=$(readlink -f "$0" 2>/dev/null || echo "/usr/local/bin/falcondns")

        echo ""
        echo -e "  ${BGRN}${B}╔════════════════════════════════════════════╗${R}"
        echo -e "  ${BGRN}${B}║${R}  ${BGRN}✓ FalconDNS has been fully uninstalled${R}    ${BGRN}${B}║${R}"
        echo -e "  ${BGRN}${B}╚════════════════════════════════════════════╝${R}"
        echo ""

        # Remove self last
        rm -f "$self_path" 2>/dev/null || true
        exit 0
    else
        echo -e "  ${DIM}Cancelled${R}"
    fi

    press_enter
}

press_enter() {
    echo -ne "  ${DIM}Press Enter to continue...${R}"
    read -r
}

# ─── Main Loop ─────────────────────────────────────────────────────────────────

main() {
    check_root
    check_deps

    while true; do
        clear_screen
        print_header
        print_server_status
        print_menu

        echo -ne "  ${BCYN}${B}❯${R} "
        read -r choice

        case $choice in
            1)  create_user ;;
            2)  list_users ;;
            3)  delete_user ;;
            4)  toggle_hwid ;;
            5)  set_expiry ;;
            6)  reset_bandwidth ;;
            7)  toggle_user_status ;;
            8)  server_status ;;
            9)  restart_server ;;
            10) online_users ;;
            11) uninstall_server ;;
            0|q|exit) 
                echo -e "\n  ${DIM}Goodbye! 👋${R}\n"
                exit 0
                ;;
            *)
                echo -e "  ${BRED}Invalid option${R}"
                sleep 0.5
                ;;
        esac
    done
}

main "$@"
