#!/usr/bin/env bash
#
# FalconDNS — Terminal Management UI
# Interactive TUI for managing users, sessions, and server
#

# ─── Colors & Styles ───────────────────────────────────────────────────────────
R='\033[0m'         # Reset
B='\033[1m'         # Bold
DIM='\033[2m'       # Dim

# Foreground
RED='\033[31m'
GRN='\033[32m'
YEL='\033[33m'
BLU='\033[34m'
CYN='\033[36m'
WHT='\033[37m'

# Bright foreground
BRED='\033[91m'
BGRN='\033[92m'
BYEL='\033[93m'
BCYN='\033[96m'
BWHT='\033[97m'

# Backgrounds
BG_CYN='\033[46m'
BG_DK='\033[48;5;236m'

# ─── Paths ─────────────────────────────────────────────────────────────────────
DB_PATH="/var/lib/falcondns/falcon.db"
CONFIG_PATH="/etc/falcondns/engine.json"
SERVICE_NAME="falcondns"
BINARY_PATH="/usr/local/bin/falcon-dns-engine"

# ─── Helpers ───────────────────────────────────────────────────────────────────
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${BRED}✗ This tool must be run as root.${R}"
        exit 1
    fi
}

check_deps() {
    # The Rust engine uses the SQLite library internally, but to query the database 
    # from this bash panel, we need the actual 'sqlite3' command-line utility.
    if ! command -v sqlite3 &>/dev/null; then
        echo -e "${DIM}Installing sqlite3 command-line tool...${R}"
        apt-get update -qq && apt-get install -y -qq sqlite3 >/dev/null 2>&1
    fi
}

rand_hex() {
    local len=${1:-64}
    head -c $((len/2)) /dev/urandom | xxd -p | tr -d '\n' | head -c "$len"
}

gen_sub_id() {
    # Standard UUIDv4 just like the Rust engine (e.g. c4cbb27a-5851-4fd2-945c-dfb31183c0b7)
    cat /proc/sys/kernel/random/uuid
}

gen_user_key() {
    # 64-character hex key
    rand_hex 64
}

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
    echo -e "  ${BG_CYN} ${WHT}${B} FALCONDNS MANAGER ${R} ${DIM}— Control Panel${R}"
    echo ""
}

print_server_status() {
    local status
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        status="${BGRN}${B}● ONLINE${R}"
    else
        status="${BRED}${B}● OFFLINE${R}"
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
        user_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users;")
        active_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users WHERE status='active';")
        session_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM active_sessions;")
    fi

    echo -e "  ╭──────────────────────────────────────────────────────────╮"
    echo -e "  │  ${B}Server:${R} $status     ${B}Domain:${R} ${BCYN}$domain${R}"
    echo -e "  │  ${B}System:${R} ${vps_ip}     ${B}Users:${R}  ${BWHT}$user_count${R} (${BGRN}$active_count active${R})"
    echo -e "  │  ${B}Active Connections:${R} ${BYEL}$session_count${R}"
    echo -e "  ╰──────────────────────────────────────────────────────────╯"
    echo ""
}

print_menu() {
    echo -e "  ${BCYN}${B}❖ USER MANAGEMENT${R}"
    echo -e "     ${BWHT}${B}1${R} ${DIM}▶${R} ${WHT}Create New User${R}"
    echo -e "     ${BWHT}${B}2${R} ${DIM}▶${R} ${WHT}List All Users${R}"
    echo -e "     ${BWHT}${B}3${R} ${DIM}▶${R} ${WHT}Delete User${R}"
    echo -e "     ${BWHT}${B}4${R} ${DIM}▶${R} ${WHT}Toggle HWID Lock${R} ${DIM}(Reset Device)${R}"
    echo -e "     ${BWHT}${B}5${R} ${DIM}▶${R} ${WHT}Renew / Set Expiry Date${R}"
    echo -e "     ${BWHT}${B}6${R} ${DIM}▶${R} ${WHT}Reset Bandwidth Usage${R}"
    echo -e "     ${BWHT}${B}7${R} ${DIM}▶${R} ${WHT}Enable / Disable User${R}"
    echo ""
    echo -e "  ${BCYN}${B}❖ SERVER CONTROLS${R}"
    echo -e "     ${BWHT}${B}8${R} ${DIM}▶${R} ${WHT}View Active Sessions${R} ${DIM}(Online Users)${R}"
    echo -e "     ${BWHT}${B}9${R} ${DIM}▶${R} ${WHT}Server Logs & Health${R}"
    echo -e "    ${BWHT}${B}10${R} ${DIM}▶${R} ${WHT}Restart FalconDNS${R}"
    echo ""
    echo -e "  ${BRED}${B}❖ DANGER ZONE${R}"
    echo -e "    ${BWHT}${B}11${R} ${DIM}▶${R} ${BRED}Uninstall Server${R}"
    echo -e "     ${BWHT}${B}0${R} ${DIM}▶${R} ${DIM}Exit Panel${R}"
    echo ""
}

# ─── Functions ─────────────────────────────────────────────────────────────────

create_user() {
    clear_screen
    echo -e "\n  ${BCYN}${B}✦ CREATE NEW USER ✦${R}\n"

    echo -ne "  ${B}Name${R} ${DIM}(optional)${R}: "
    read -r name

    echo -ne "  ${B}Subscription ID${R} ${DIM}(leave blank to auto-generate UUID)${R}: "
    read -r sub_id
    if [[ -z "$sub_id" ]]; then
        sub_id=$(gen_sub_id)
        echo -e "  ${DIM}↳ Generated UUID: ${BCYN}$sub_id${R}"
    fi

    local existing
    existing=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users WHERE sub_id='$sub_id';")
    if [[ "$existing" -gt 0 ]]; then
        echo -e "\n  ${BRED}✗ Error: User '$sub_id' already exists!${R}"
        press_enter
        return
    fi

    echo -ne "  ${B}Duration in days${R} ${DIM}(blank = never expires)${R}: "
    read -r days
    local expiry="Never"
    local expiry_sql="NULL"
    if [[ -n "$days" && "$days" =~ ^[0-9]+$ ]]; then
        expiry=$(date -d "+$days days" "+%Y-%m-%d" 2>/dev/null)
        expiry_sql="'$expiry'"
    elif [[ -n "$days" ]]; then
        echo -e "  ${BRED}↳ Invalid duration. Setting to Never.${R}"
    fi

    echo -ne "  ${B}Bandwidth Limit in GB${R} ${DIM}(default: 100)${R}: "
    read -r bw_gb
    if [[ -z "$bw_gb" ]]; then
        bw_gb=100
    fi
    local bw_bytes=$((bw_gb * 1073741824))

    # HWID lock is YES by default now
    echo -ne "  ${B}Enable HWID Lock?${R} ${DIM}(Y/n)${R}: "
    read -r hwid_choice
    hwid_choice=${hwid_choice:-Y}

    local user_key
    user_key=$(gen_user_key)

    # Insert user
    local name_sql="NULL"
    if [[ -n "$name" ]]; then
        name_sql="'$name'"
    fi

    sqlite3 "$DB_PATH" "INSERT INTO users (sub_id, user_key, status, bandwidth_allowed, bandwidth_used, expiry_date, name) VALUES ('$sub_id', '$user_key', 'active', $bw_bytes, 0, $expiry_sql, $name_sql);"

    if [[ "$hwid_choice" =~ ^[Yy] ]]; then
        # Default behavior: lock on first connection
        true
    else
        sqlite3 "$DB_PATH" "UPDATE users SET hardware_id = 'DISABLED' WHERE sub_id='$sub_id';"
    fi

    # Build Quick Connect Code
    local domain="N/A"
    local vps_ip="N/A"
    if [[ -f "$CONFIG_PATH" ]]; then
        domain=$(grep -oP '"domain"\s*:\s*"\K[^"]+' "$CONFIG_PATH" 2>/dev/null || echo "N/A")
        vps_ip=$(grep -oP '"server_ip"\s*:\s*"\K[^"]+' "$CONFIG_PATH" 2>/dev/null || echo "N/A")
    fi
    local json="{\"d\":\"$domain\",\"i\":\"$vps_ip\",\"s\":\"$sub_id\",\"k\":\"$user_key\"}"
    local b64=$(echo -n "$json" | base64 | tr -d '\n')

    echo ""
    echo -e "  ${BGRN}${B}✔ User successfully created!${R}"
    echo -e "  ╭───────────────────────────────────────────────────────────╮"
    echo -e "  │ ${B}Name:${R}       ${WHT}${name:-N/A}${R}"
    echo -e "  │ ${B}Sub ID:${R}     ${BCYN}$sub_id${R}"
    echo -e "  │ ${B}Key:${R}        ${BYEL}$user_key${R}"
    echo -e "  │ ${B}Expiry:${R}     ${WHT}$expiry${R}"
    echo -e "  │ ${B}Data Limit:${R} ${WHT}${bw_gb} GB${R}"
    echo -e "  │ ${B}HWID Lock:${R}  ${WHT}$(if [[ "$hwid_choice" =~ ^[Yy] ]]; then echo "Enabled"; else echo "${BYEL}Disabled${R}"; fi)${R}"
    echo -e "  ╰───────────────────────────────────────────────────────────╯"
    echo ""
    echo -e "  ${B}Quick Connect Code (Copy this):${R}"
    echo -e "  ${BG_DK} ${BCYN}falcon://${b64} ${R}"
    echo ""

    press_enter
}

list_users() {
    clear_screen
    echo -e "\n  ${BCYN}${B}✦ ALL USERS ✦${R}\n"

    local count
    count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users;")

    if [[ "$count" -eq 0 ]]; then
        echo -e "  ${DIM}No users found.${R}"
        press_enter
        return
    fi

    printf "  ${B}${BCYN}%-38s %-12s %-8s %-12s %-14s %-8s %-5s${R}\n" \
        "SUB_ID (UUID)" "NAME" "STATUS" "EXPIRY" "BANDWIDTH" "HWID" "SESS"
    echo -e "  ${DIM}────────────────────────────────────────────────────────────────────────────────────────────────────${R}"

    sqlite3 -separator '|' "$DB_PATH" "
        SELECT u.sub_id, COALESCE(u.name,'—'), u.status, COALESCE(u.expiry_date,'Never'),
               u.bandwidth_used, u.bandwidth_allowed,
               CASE WHEN u.hardware_id IS NULL THEN 'Locked'
                    WHEN u.hardware_id = 'DISABLED' THEN 'Off'
                    ELSE 'Locked' END,
               (SELECT COUNT(*) FROM active_sessions a WHERE a.sub_id = u.sub_id)
        FROM users u ORDER BY u.created_at DESC;
    " | while IFS='|' read -r sid uname status expiry bw_used bw_allowed hwid sessions; do
        
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

        printf "  %-38s %-12s ${status_color}%-8s${R} %-12s %-14s ${hwid_color}%-8s${R} ${sess_color}%-5s${R}\n" \
            "$sid" "${uname:0:11}" "$status" "$expiry" "${bw_str:0:13}" "$hwid" "$sessions"
    done

    echo ""
    echo -e "  ${DIM}Total Database Entries: $count${R}"
    echo ""
    press_enter
}

delete_user() {
    clear_screen
    echo -e "\n  ${BCYN}${B}✦ DELETE USER ✦${R}\n"

    echo -ne "  ${B}Enter Sub ID (UUID) to delete${R}: "
    read -r sub_id

    if [[ -z "$sub_id" ]]; then return; fi

    local exists
    exists=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users WHERE sub_id='$sub_id';")
    if [[ "$exists" -eq 0 ]]; then
        echo -e "  ${BRED}✗ User '$sub_id' not found in database.${R}"
        press_enter
        return
    fi

    local name
    name=$(sqlite3 "$DB_PATH" "SELECT COALESCE(name, sub_id) FROM users WHERE sub_id='$sub_id';")

    echo -ne "  ${BRED}Are you sure you want to permanently delete '${name}'?${R} (y/N): "
    read -r confirm

    if [[ "$confirm" =~ ^[Yy] ]]; then
        sqlite3 "$DB_PATH" "DELETE FROM active_sessions WHERE sub_id='$sub_id';"
        sqlite3 "$DB_PATH" "DELETE FROM users WHERE sub_id='$sub_id';"
        echo -e "  ${BGRN}✔ User deleted successfully.${R}"
    else
        echo -e "  ${DIM}Cancelled.${R}"
    fi
    press_enter
}

toggle_hwid() {
    clear_screen
    echo -e "\n  ${BCYN}${B}✦ HWID LOCK SETTINGS ✦${R}\n"

    echo -ne "  ${B}Enter Sub ID${R}: "
    read -r sub_id
    if [[ -z "$sub_id" ]]; then return; fi

    local hwid
    hwid=$(sqlite3 "$DB_PATH" "SELECT hardware_id FROM users WHERE sub_id='$sub_id';")

    if [[ -z "$hwid" ]]; then
        local exists
        exists=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users WHERE sub_id='$sub_id';")
        if [[ "$exists" -eq 0 ]]; then
            echo -e "  ${BRED}✗ User not found.${R}"
            press_enter
            return
        fi
        echo -e "  ${DIM}Status:${R} ${BGRN}Enabled${R} ${DIM}(Will lock to the next device that connects)${R}"
    elif [[ "$hwid" == "DISABLED" ]]; then
        echo -e "  ${DIM}Status:${R} ${BYEL}Disabled${R} ${DIM}(Any device can use this account)${R}"
    else
        echo -e "  ${DIM}Status:${R} ${BGRN}Locked${R} ${DIM}(Bound to device: ${BCYN}${hwid:0:16}...${R}${DIM})${R}"
    fi

    echo ""
    echo -e "  ${BWHT}${B}1${R} ${DIM}▶${R} Reset & Enable Lock ${DIM}(Locks to the next device that connects)${R}"
    echo -e "  ${BWHT}${B}2${R} ${DIM}▶${R} Disable Lock completely ${DIM}(Multiple devices can share account)${R}"
    echo -e "  ${BWHT}${B}0${R} ${DIM}▶${R} Cancel"
    echo ""
    echo -ne "  ${B}Choice${R}: "
    read -r choice

    case $choice in
        1)
            sqlite3 "$DB_PATH" "UPDATE users SET hardware_id = NULL WHERE sub_id='$sub_id';"
            echo -e "  ${BGRN}✔ HWID reset. Ready to lock to a new device.${R}"
            ;;
        2)
            sqlite3 "$DB_PATH" "UPDATE users SET hardware_id = 'DISABLED' WHERE sub_id='$sub_id';"
            echo -e "  ${BYEL}✔ HWID disabled.${R}"
            ;;
    esac
    press_enter
}

set_expiry() {
    clear_screen
    echo -e "\n  ${BCYN}${B}✦ SET EXPIRY ✦${R}\n"

    echo -ne "  ${B}Enter Sub ID${R}: "
    read -r sub_id
    if [[ -z "$sub_id" ]]; then return; fi

    local exists
    exists=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users WHERE sub_id='$sub_id';")
    if [[ "$exists" -eq 0 ]]; then
        echo -e "  ${BRED}✗ User not found.${R}"
        press_enter
        return
    fi

    local current_expiry
    current_expiry=$(sqlite3 "$DB_PATH" "SELECT COALESCE(expiry_date, 'Never') FROM users WHERE sub_id='$sub_id';")
    echo -e "  ${DIM}Current Expiry:${R} ${BWHT}$current_expiry${R}"
    echo ""

    echo -ne "  ${B}Add how many days?${R} ${DIM}(e.g. 30, or blank to cancel, '0' to remove expiry)${R}: "
    read -r days

    if [[ "$days" == "0" ]]; then
        sqlite3 "$DB_PATH" "UPDATE users SET expiry_date = NULL, status = 'active' WHERE sub_id='$sub_id';"
        echo -e "  ${BGRN}✔ Expiry removed. User will never expire.${R}"
    elif [[ -n "$days" && "$days" =~ ^[0-9]+$ ]]; then
        local expiry
        expiry=$(date -d "+$days days" "+%Y-%m-%d" 2>/dev/null)
        sqlite3 "$DB_PATH" "UPDATE users SET expiry_date = '$expiry', status = 'active' WHERE sub_id='$sub_id';"
        echo -e "  ${BGRN}✔ Expiry updated to: ${BWHT}$expiry${R}"
    fi

    press_enter
}

reset_bandwidth() {
    clear_screen
    echo -e "\n  ${BCYN}${B}✦ RESET BANDWIDTH ✦${R}\n"

    echo -ne "  ${B}Enter Sub ID${R} ${DIM}('all' for everyone)${R}: "
    read -r sub_id
    if [[ -z "$sub_id" ]]; then return; fi

    if [[ "$sub_id" == "all" ]]; then
        echo -ne "  ${BRED}Reset bandwidth for ALL users?${R} (y/N): "
        read -r confirm
        if [[ "$confirm" =~ ^[Yy] ]]; then
            sqlite3 "$DB_PATH" "UPDATE users SET bandwidth_used = 0;"
            echo -e "  ${BGRN}✔ Bandwidth reset globally.${R}"
        fi
    else
        local exists
        exists=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users WHERE sub_id='$sub_id';")
        if [[ "$exists" -eq 0 ]]; then
            echo -e "  ${BRED}✗ User not found.${R}"
        else
            sqlite3 "$DB_PATH" "UPDATE users SET bandwidth_used = 0 WHERE sub_id='$sub_id';"
            echo -e "  ${BGRN}✔ Bandwidth reset for user.${R}"
        fi
    fi
    press_enter
}

toggle_user_status() {
    clear_screen
    echo -e "\n  ${BCYN}${B}✦ ENABLE / DISABLE USER ✦${R}\n"

    echo -ne "  ${B}Enter Sub ID${R}: "
    read -r sub_id
    if [[ -z "$sub_id" ]]; then return; fi

    local current
    current=$(sqlite3 "$DB_PATH" "SELECT status FROM users WHERE sub_id='$sub_id';")

    if [[ -z "$current" ]]; then
        echo -e "  ${BRED}✗ User not found.${R}"
        press_enter
        return
    fi

    echo -e "  ${DIM}Current Status:${R} ${BWHT}$current${R}"
    echo ""

    if [[ "$current" == "active" ]]; then
        sqlite3 "$DB_PATH" "UPDATE users SET status = 'disabled' WHERE sub_id='$sub_id';"
        sqlite3 "$DB_PATH" "DELETE FROM active_sessions WHERE sub_id='$sub_id';"
        echo -e "  ${BYEL}✔ User disabled. Sessions terminated.${R}"
    else
        sqlite3 "$DB_PATH" "UPDATE users SET status = 'active' WHERE sub_id='$sub_id';"
        echo -e "  ${BGRN}✔ User re-enabled.${R}"
    fi

    press_enter
}

online_users() {
    clear_screen
    echo -e "\n  ${BCYN}${B}✦ ACTIVE SESSIONS ✦${R}\n"

    local count
    count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM active_sessions;")

    if [[ "$count" -eq 0 ]]; then
        echo -e "  ${DIM}No active sessions right now.${R}"
        press_enter
        return
    fi

    printf "  ${B}${BCYN}%-38s %-12s %-16s %-20s${R}\n" "SUB_ID" "NAME" "VIRTUAL_IP" "LAST_SEEN"
    echo -e "  ${DIM}────────────────────────────────────────────────────────────────────────────────────────${R}"

    sqlite3 -separator '|' "$DB_PATH" "
        SELECT a.sub_id, COALESCE(u.name, '—'), a.assigned_virtual_ip, a.last_seen
        FROM active_sessions a LEFT JOIN users u ON a.sub_id = u.sub_id ORDER BY a.last_seen DESC;
    " | while IFS='|' read -r sid uname vip last_seen; do
        printf "  ${BGRN}%-38s${R} %-12s %-16s ${DIM}%-20s${R}\n" "$sid" "${uname:0:11}" "$vip" "$last_seen"
    done

    echo ""
    press_enter
}

server_status() {
    clear_screen
    echo -e "\n  ${BCYN}${B}✦ SERVER LOGS & HEALTH ✦${R}\n"

    echo -e "  ${B}System Metrics:${R}"
    echo -e "  ${DIM}Uptime       :${R} $(uptime -p 2>/dev/null || echo 'N/A')"
    echo -e "  ${DIM}Memory Usage :${R} $(free -h 2>/dev/null | awk '/^Mem:/ {print $3 " / " $2}' || echo 'N/A')"
    
    local pid
    pid=$(pgrep -f falcon-dns-engine | head -1)
    if [[ -n "$pid" ]]; then
        echo -e "  ${DIM}Engine RAM   :${R} $(ps -p "$pid" -o rss= 2>/dev/null | awk '{printf "%.1f MB", $1/1024}')"
    fi

    echo ""
    echo -e "  ${B}Recent Logs:${R}"
    echo -e "  ${DIM}────────────────────────────────────────────────────────────────${R}"
    journalctl -u "$SERVICE_NAME" --no-pager -n 20 2>/dev/null | sed 's/^/  /'
    echo ""
    press_enter
}

restart_server() {
    echo ""
    echo -ne "  ${BRED}Restart FalconDNS Service?${R} (y/N): "
    read -r confirm
    if [[ "$confirm" =~ ^[Yy] ]]; then
        echo -e "  ${DIM}Restarting...${R}"
        systemctl restart "$SERVICE_NAME"
        sleep 1
        if systemctl is-active --quiet "$SERVICE_NAME"; then
            echo -e "  ${BGRN}✔ Server restarted successfully.${R}"
        else
            echo -e "  ${BRED}✗ Server failed to start! Check logs.${R}"
        fi
    fi
    press_enter
}

uninstall_server() {
    clear_screen
    echo -e "\n  ${BRED}${B}✦ UNINSTALL FALCONDNS ✦${R}\n"
    echo -e "  ${BRED}WARNING:${R} This will permanently delete the server, database, and all users."
    echo -e "  Type ${BRED}UNINSTALL${R} to confirm: \c"
    read -r confirm

    if [[ "$confirm" == "UNINSTALL" ]]; then
        echo -e "\n  ${DIM}Stopping service...${R}"
        systemctl stop "$SERVICE_NAME" 2>/dev/null || true
        systemctl disable "$SERVICE_NAME" 2>/dev/null || true
        rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
        pkill -f falcon-dns-engine 2>/dev/null || true
        systemctl daemon-reload

        echo -e "  ${DIM}Removing files & database...${R}"
        rm -f "$BINARY_PATH"
        rm -rf /etc/falcondns
        rm -rf /var/lib/falcondns

        echo -e "  ${DIM}Cleaning network...${R}"
        ip link delete falcontun0 2>/dev/null || true

        local self_path
        self_path=$(readlink -f "$0" 2>/dev/null || echo "/usr/local/bin/falcondns")

        echo -e "\n  ${BGRN}✔ FalconDNS completely removed from server.${R}\n"
        rm -f "$self_path" 2>/dev/null || true
        exit 0
    else
        echo -e "  ${DIM}Uninstall cancelled.${R}"
    fi
    press_enter
}

press_enter() {
    echo -ne "  ${DIM}Press Enter to return...${R}"
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
            1) create_user ;;
            2) list_users ;;
            3) delete_user ;;
            4) toggle_hwid ;;
            5) set_expiry ;;
            6) reset_bandwidth ;;
            7) toggle_user_status ;;
            8) online_users ;;
            9) server_status ;;
            10) restart_server ;;
            11) uninstall_server ;;
            0|q|exit) 
                clear_screen
                exit 0 ;;
            *) sleep 0.5 ;;
        esac
    done
}

main "$@"
