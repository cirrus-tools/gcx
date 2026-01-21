#!/bin/bash

# gcx-sql.sh
# Cloud SQL instance management for gcx
# This file is sourced by gcx when running 'gcx sql'

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

sql_list() {
    local project=$(gcloud config get-value project 2>/dev/null)
    local tmpfile=$(mktemp)

    gum spin --spinner dot --title "Loading Cloud SQL instances..." -- \
        sh -c "gcloud sql instances list --quiet --format='table(name,databaseVersion,gceZone,settings.tier,state,ipAddresses[0].ipAddress)' > '$tmpfile' 2>&1"
    local exit_code=$?

    local result=$(cat "$tmpfile")
    rm -f "$tmpfile"

    if [ $exit_code -ne 0 ] || echo "$result" | grep -q "ERROR\|PERMISSION_DENIED"; then
        if echo "$result" | grep -q "API.*not enabled\|PERMISSION_DENIED"; then
            echo -e "${RED}Error: Cloud SQL Admin API not enabled or no permission${NC}"
            echo -e "${YELLOW}Enable it at: https://console.cloud.google.com/apis/library/sqladmin.googleapis.com${NC}"
        else
            echo -e "${RED}Error: $result${NC}"
        fi
        return 1
    fi

    if [ -z "$result" ] || echo "$result" | grep -q "Listed 0 items"; then
        echo -e "${YELLOW}No Cloud SQL instances found in project ${project}${NC}"
        return 0
    fi

    echo "$result"
    echo ""
}

sql_select() {
    local project=$(gcloud config get-value project 2>/dev/null)
    local tmpfile=$(mktemp)

    gum spin --spinner dot --title "Loading Cloud SQL instances..." -- \
        sh -c "gcloud sql instances list --quiet --format='value(name,databaseVersion,state,settings.tier,ipAddresses[0].ipAddress)' > '$tmpfile' 2>&1"
    local exit_code=$?

    local instances=$(cat "$tmpfile")
    rm -f "$tmpfile"

    if [ $exit_code -ne 0 ] || echo "$instances" | grep -q "ERROR\|PERMISSION_DENIED"; then
        if echo "$instances" | grep -q "API.*not enabled\|PERMISSION_DENIED"; then
            echo -e "${RED}Error: Cloud SQL Admin API not enabled or no permission${NC}"
            echo -e "${YELLOW}Enable it at: https://console.cloud.google.com/apis/library/sqladmin.googleapis.com${NC}"
        else
            echo -e "${RED}Error loading instances${NC}"
        fi
        return 1
    fi

    if [ -z "$instances" ]; then
        echo -e "${YELLOW}No Cloud SQL instances found in project ${project}${NC}"
        return 1
    fi

    local options=""
    while IFS=$'\t' read -r name version state tier ip; do
        local icon="⚪"
        [ "$state" = "RUNNABLE" ] && icon="🟢"
        [ "$state" = "STOPPED" ] && icon="🔴"
        [ "$state" = "PENDING_CREATE" ] && icon="🟡"
        [ "$state" = "MAINTENANCE" ] && icon="🟠"

        local db_icon="🐘"
        [[ "$version" == *"MYSQL"* ]] && db_icon="🐬"
        [[ "$version" == *"SQLSERVER"* ]] && db_icon="🪟"

        options="${options}${icon} ${db_icon} ${name} | ${version} | ${tier} | ${ip:-no-ip}\n"
    done <<< "$instances"

    local choice=$(echo -e "$options" | gum filter --placeholder="Search instance..." --header="Select Cloud SQL instance:" --header.foreground="4")

    if [ -z "$choice" ]; then
        echo "Cancelled."
        return 0
    fi

    local selected_name=$(echo "$choice" | sed 's/^[^ ]* [^ ]* //' | cut -d'|' -f1 | xargs)

    echo ""
    echo -e "${GREEN}Selected: ${selected_name}${NC}"
    echo ""

    sql_actions "$selected_name"
}

sql_actions() {
    local name="$1"

    local status=$(gcloud sql instances describe "$name" --format="value(state)" 2>/dev/null)

    local actions=""
    if [ "$status" = "RUNNABLE" ]; then
        actions="📋 Show details\n🔌 Connect (cloud_sql_proxy)\n📊 List databases\n👤 List users\n🛑 Stop\n🔄 Restart\n❌ Cancel"
    else
        actions="📋 Show details\n▶️  Start\n❌ Cancel"
    fi

    local action=$(echo -e "$actions" | gum choose --header="Action for ${name}:" --header.foreground="4")

    case "$action" in
        *"Show details"*)
            sql_describe "$name"
            ;;
        *"Connect"*)
            sql_connect "$name"
            ;;
        *"List databases"*)
            sql_databases "$name"
            ;;
        *"List users"*)
            sql_users "$name"
            ;;
        *"Start"*)
            sql_start "$name"
            ;;
        *"Stop"*)
            sql_stop "$name"
            ;;
        *"Restart"*)
            sql_restart "$name"
            ;;
        *"Cancel"*)
            echo "Cancelled."
            ;;
    esac
}

sql_describe() {
    local name="$1"
    local tmpfile=$(mktemp)

    gum spin --spinner dot --title "Loading details..." -- \
        sh -c "gcloud sql instances describe '$name' --quiet --format='value(name,databaseVersion,gceZone,settings.tier,state,settings.dataDiskSizeGb,ipAddresses[0].ipAddress,connectionName,createTime)' > '$tmpfile' 2>&1"

    local info=$(cat "$tmpfile")
    rm -f "$tmpfile"

    IFS=$'\t' read -r inst_name version zone tier state disk_size ip connection_name created <<< "$info"

    local status_icon="⚪"
    [ "$state" = "RUNNABLE" ] && status_icon="🟢"
    [ "$state" = "STOPPED" ] && status_icon="🔴"

    echo ""
    gum style --border rounded --padding "1 2" --border-foreground 4 \
        "${status_icon} ${inst_name}" \
        "" \
        "Version:    ${version}" \
        "Zone:       ${zone}" \
        "Tier:       ${tier}" \
        "Status:     ${state}" \
        "Disk:       ${disk_size}GB" \
        "IP:         ${ip:-none}" \
        "Connection: ${connection_name}" \
        "Created:    ${created%T*}"
    echo ""
}

sql_databases() {
    local name="$1"
    local tmpfile=$(mktemp)

    gum spin --spinner dot --title "Loading databases..." -- \
        sh -c "gcloud sql databases list --instance='$name' --quiet --format='table(name,charset,collation)' > '$tmpfile' 2>&1"

    local result=$(cat "$tmpfile")
    rm -f "$tmpfile"

    if [ -z "$result" ]; then
        echo -e "${YELLOW}No databases found${NC}"
        return 0
    fi

    echo "$result"
    echo ""
}

sql_users() {
    local name="$1"
    local tmpfile=$(mktemp)

    gum spin --spinner dot --title "Loading users..." -- \
        sh -c "gcloud sql users list --instance='$name' --quiet --format='table(name,host,type)' > '$tmpfile' 2>&1"

    local result=$(cat "$tmpfile")
    rm -f "$tmpfile"

    if [ -z "$result" ]; then
        echo -e "${YELLOW}No users found${NC}"
        return 0
    fi

    echo "$result"
    echo ""
}

sql_connect() {
    local name="$1"

    local connection_name=$(gcloud sql instances describe "$name" --format="value(connectionName)" 2>/dev/null)

    if [ -z "$connection_name" ]; then
        echo -e "${RED}Could not get connection name${NC}"
        return 1
    fi

    if ! command -v cloud_sql_proxy &>/dev/null && ! command -v cloud-sql-proxy &>/dev/null; then
        echo -e "${RED}cloud_sql_proxy not found${NC}"
        echo -e "${YELLOW}Install it: https://cloud.google.com/sql/docs/mysql/sql-proxy${NC}"
        echo ""
        echo "Or use gcloud directly:"
        echo -e "${CYAN}gcloud sql connect ${name} --user=root${NC}"
        return 1
    fi

    echo -e "${BLUE}Connection name: ${connection_name}${NC}"
    echo ""
    echo "To connect, run:"
    echo -e "${CYAN}cloud-sql-proxy ${connection_name}${NC}"
    echo ""
    echo "Then connect to localhost with your SQL client."

    if gum confirm "Start cloud-sql-proxy now?"; then
        echo -e "${BLUE}Starting proxy (Ctrl+C to stop)...${NC}"
        if command -v cloud-sql-proxy &>/dev/null; then
            cloud-sql-proxy "$connection_name"
        else
            cloud_sql_proxy -instances="$connection_name=tcp:3306"
        fi
    fi
}

sql_start() {
    local name="$1"

    echo -e "${BLUE}Starting ${name}...${NC}"
    if gcloud sql instances patch "$name" --activation-policy=ALWAYS --quiet; then
        echo -e "${GREEN}Started ${name}${NC}"
    else
        echo -e "${RED}Failed to start instance${NC}"
    fi
}

sql_stop() {
    local name="$1"

    echo -e "${RED}WARNING: Stopping the instance will make it inaccessible${NC}"

    if gum confirm "Stop Cloud SQL instance ${name}?"; then
        echo -e "${BLUE}Stopping ${name}...${NC}"
        if gcloud sql instances patch "$name" --activation-policy=NEVER --quiet; then
            echo -e "${GREEN}Stopped ${name}${NC}"
        else
            echo -e "${RED}Failed to stop instance${NC}"
        fi
    else
        echo "Cancelled."
    fi
}

sql_restart() {
    local name="$1"

    if gum confirm "Restart Cloud SQL instance ${name}?"; then
        echo -e "${BLUE}Restarting ${name}...${NC}"
        if gcloud sql instances restart "$name" --quiet; then
            echo -e "${GREEN}Restarted ${name}${NC}"
        else
            echo -e "${RED}Failed to restart instance${NC}"
        fi
    else
        echo "Cancelled."
    fi
}

show_sql_help() {
    cat << EOF
gcx sql - Cloud SQL instance management

Usage: gcx sql [command] [args]

Commands:
  (no args)       Interactive instance selector
  list, ls        List all instances
  databases <n>   List databases in instance
  users <name>    List users in instance
  connect <name>  Show connection info / start proxy
  start <name>    Start instance
  stop <name>     Stop instance
  restart <name>  Restart instance
  help            Show this help

Examples:
  gcx sql                     Interactive mode
  gcx sql list                List all instances
  gcx sql databases mydb      List databases
  gcx sql connect mydb        Connect to instance
EOF
}

sql_main() {
    case "${1:-}" in
        list|ls)
            sql_list
            ;;
        databases|db)
            if [ -n "$2" ]; then
                sql_databases "$2"
            else
                echo -e "${RED}Usage: gcx sql databases <instance>${NC}"
                exit 1
            fi
            ;;
        users)
            if [ -n "$2" ]; then
                sql_users "$2"
            else
                echo -e "${RED}Usage: gcx sql users <instance>${NC}"
                exit 1
            fi
            ;;
        connect)
            if [ -n "$2" ]; then
                sql_connect "$2"
            else
                sql_select
            fi
            ;;
        start)
            if [ -n "$2" ]; then
                sql_start "$2"
            else
                echo -e "${RED}Usage: gcx sql start <instance>${NC}"
                exit 1
            fi
            ;;
        stop)
            if [ -n "$2" ]; then
                sql_stop "$2"
            else
                echo -e "${RED}Usage: gcx sql stop <instance>${NC}"
                exit 1
            fi
            ;;
        restart)
            if [ -n "$2" ]; then
                sql_restart "$2"
            else
                echo -e "${RED}Usage: gcx sql restart <instance>${NC}"
                exit 1
            fi
            ;;
        help|--help|-h)
            show_sql_help
            ;;
        "")
            sql_select
            ;;
        *)
            sql_describe "$1"
            ;;
    esac
}
