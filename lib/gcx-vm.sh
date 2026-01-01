#!/bin/bash

# gcx-vm.sh
# VM instance management for gcx
# This file is sourced by gcx when running 'gcx vm'

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# =============================================================================
# VM List
# =============================================================================

vm_list() {
    local project=$(gcloud config get-value project 2>/dev/null)
    echo -e "${BLUE}Loading VMs for project: ${project}${NC}"
    echo ""

    local vms=$(gcloud compute instances list --format="table(name,zone,machineType.basename(),status,networkInterfaces[0].networkIP,networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null)

    if [ -z "$vms" ]; then
        echo -e "${YELLOW}No VMs found in project ${project}${NC}"
        return 0
    fi

    echo "$vms"
    echo ""
}

# =============================================================================
# VM Select (Interactive)
# =============================================================================

vm_select() {
    local project=$(gcloud config get-value project 2>/dev/null)
    echo -e "${BLUE}Loading VMs...${NC}"

    local vms=$(gcloud compute instances list --format="value(name,zone,status)" 2>/dev/null)

    if [ -z "$vms" ]; then
        echo -e "${YELLOW}No VMs found in project ${project}${NC}"
        return 1
    fi

    # Build selection list
    local options=""
    while IFS=$'\t' read -r name zone status; do
        local icon="⚪"
        [ "$status" = "RUNNING" ] && icon="🟢"
        [ "$status" = "TERMINATED" ] && icon="🔴"
        [ "$status" = "STOPPED" ] && icon="🔴"
        [ "$status" = "SUSPENDED" ] && icon="🟡"
        options="${options}${icon} ${name} (${zone##*/}) [${status}]\n"
    done <<< "$vms"

    local choice=$(echo -e "$options" | gum choose --header="Select VM:" --header.foreground="4")

    if [ -z "$choice" ]; then
        echo "Cancelled."
        return 0
    fi

    # Extract VM name and zone
    local selected_name=$(echo "$choice" | sed 's/^[^ ]* //' | cut -d' ' -f1)
    local selected_zone=$(echo "$choice" | grep -o '([^)]*' | sed 's/(//')

    echo ""
    echo -e "${GREEN}Selected: ${selected_name} (${selected_zone})${NC}"
    echo ""

    # Show action menu
    vm_actions "$selected_name" "$selected_zone"
}

# =============================================================================
# VM Actions
# =============================================================================

vm_actions() {
    local name="$1"
    local zone="$2"

    local status=$(gcloud compute instances describe "$name" --zone="$zone" --format="value(status)" 2>/dev/null)

    local actions=""
    if [ "$status" = "RUNNING" ]; then
        actions="🔌 SSH\n📋 Show details\n🛑 Stop\n🔄 Reset\n❌ Cancel"
    else
        actions="▶️  Start\n📋 Show details\n❌ Cancel"
    fi

    local action=$(echo -e "$actions" | gum choose --header="Action for ${name}:" --header.foreground="4")

    case "$action" in
        *"SSH"*)
            vm_ssh "$name" "$zone"
            ;;
        *"Show details"*)
            vm_describe "$name" "$zone"
            ;;
        *"Start"*)
            vm_start "$name" "$zone"
            ;;
        *"Stop"*)
            vm_stop "$name" "$zone"
            ;;
        *"Reset"*)
            vm_reset "$name" "$zone"
            ;;
        *"Cancel"*)
            echo "Cancelled."
            ;;
    esac
}

vm_ssh() {
    local name="$1"
    local zone="$2"

    echo -e "${BLUE}Connecting to ${name}...${NC}"
    gcloud compute ssh "$name" --zone="$zone"
}

vm_describe() {
    local name="$1"
    local zone="$2"

    echo -e "${BLUE}=== VM Details: ${name} ===${NC}"
    echo ""
    gcloud compute instances describe "$name" --zone="$zone" --format="yaml(name,zone,machineType,status,networkInterfaces,disks[].source,metadata.items)"
}

vm_start() {
    local name="$1"
    local zone="$2"

    echo -e "${BLUE}Starting ${name}...${NC}"
    gcloud compute instances start "$name" --zone="$zone"
    echo -e "${GREEN}Started ${name}${NC}"
}

vm_stop() {
    local name="$1"
    local zone="$2"

    if gum confirm "Stop VM ${name}?"; then
        echo -e "${BLUE}Stopping ${name}...${NC}"
        gcloud compute instances stop "$name" --zone="$zone"
        echo -e "${GREEN}Stopped ${name}${NC}"
    else
        echo "Cancelled."
    fi
}

vm_reset() {
    local name="$1"
    local zone="$2"

    if gum confirm "Reset VM ${name}? This will restart the instance."; then
        echo -e "${BLUE}Resetting ${name}...${NC}"
        gcloud compute instances reset "$name" --zone="$zone"
        echo -e "${GREEN}Reset ${name}${NC}"
    else
        echo "Cancelled."
    fi
}

# =============================================================================
# Direct SSH
# =============================================================================

vm_ssh_direct() {
    local query="$1"
    local project=$(gcloud config get-value project 2>/dev/null)

    # Find VM by name (partial match)
    local matches=$(gcloud compute instances list --format="value(name,zone)" --filter="name~${query}" 2>/dev/null)
    local count=$(echo "$matches" | grep -c "." || echo "0")

    if [ "$count" -eq 0 ]; then
        echo -e "${RED}No VM found matching: ${query}${NC}"
        return 1
    elif [ "$count" -eq 1 ]; then
        local name=$(echo "$matches" | cut -f1)
        local zone=$(echo "$matches" | cut -f2)
        zone="${zone##*/}"
        vm_ssh "$name" "$zone"
    else
        echo -e "${YELLOW}Multiple VMs match '${query}':${NC}"
        local options=""
        while IFS=$'\t' read -r name zone; do
            options="${options}${name} (${zone##*/})\n"
        done <<< "$matches"

        local choice=$(echo -e "$options" | gum choose --header="Select VM:" --header.foreground="4")
        if [ -n "$choice" ]; then
            local selected_name=$(echo "$choice" | cut -d' ' -f1)
            local selected_zone=$(echo "$choice" | grep -o '([^)]*' | sed 's/(//')
            vm_ssh "$selected_name" "$selected_zone"
        fi
    fi
}

# =============================================================================
# Help
# =============================================================================

show_vm_help() {
    cat << EOF
gcx vm - VM instance management

Usage: gcx vm [command] [args]

Commands:
  (no args)     Interactive VM selector
  list, ls      List all VMs
  ssh <name>    SSH to VM (partial name match)
  start <name>  Start VM
  stop <name>   Stop VM
  help          Show this help

Examples:
  gcx vm                  Interactive mode
  gcx vm list             List all VMs
  gcx vm ssh web          SSH to VM matching 'web'
  gcx vm start my-vm      Start my-vm
  gcx vm stop my-vm       Stop my-vm
EOF
}

# =============================================================================
# Direct Start/Stop
# =============================================================================

vm_start_by_name() {
    local query="$1"
    local matches=$(gcloud compute instances list --format="value(name,zone)" --filter="name~${query}" 2>/dev/null)
    local count=$(echo "$matches" | grep -c "." || echo "0")

    if [ "$count" -eq 0 ]; then
        echo -e "${RED}No VM found matching: ${query}${NC}"
        return 1
    elif [ "$count" -eq 1 ]; then
        local name=$(echo "$matches" | cut -f1)
        local zone=$(echo "$matches" | cut -f2)
        zone="${zone##*/}"
        vm_start "$name" "$zone"
    else
        echo -e "${RED}Multiple VMs match '${query}'. Be more specific.${NC}"
        return 1
    fi
}

vm_stop_by_name() {
    local query="$1"
    local matches=$(gcloud compute instances list --format="value(name,zone)" --filter="name~${query}" 2>/dev/null)
    local count=$(echo "$matches" | grep -c "." || echo "0")

    if [ "$count" -eq 0 ]; then
        echo -e "${RED}No VM found matching: ${query}${NC}"
        return 1
    elif [ "$count" -eq 1 ]; then
        local name=$(echo "$matches" | cut -f1)
        local zone=$(echo "$matches" | cut -f2)
        zone="${zone##*/}"
        vm_stop "$name" "$zone"
    else
        echo -e "${RED}Multiple VMs match '${query}'. Be more specific.${NC}"
        return 1
    fi
}

# =============================================================================
# Main
# =============================================================================

vm_main() {
    case "${1:-}" in
        list|ls)
            vm_list
            ;;
        ssh)
            if [ -n "$2" ]; then
                vm_ssh_direct "$2"
            else
                vm_select
            fi
            ;;
        start)
            if [ -n "$2" ]; then
                vm_start_by_name "$2"
            else
                echo -e "${RED}Usage: gcx vm start <name>${NC}"
                exit 1
            fi
            ;;
        stop)
            if [ -n "$2" ]; then
                vm_stop_by_name "$2"
            else
                echo -e "${RED}Usage: gcx vm stop <name>${NC}"
                exit 1
            fi
            ;;
        help|--help|-h)
            show_vm_help
            ;;
        "")
            vm_select
            ;;
        *)
            # Treat as SSH shortcut
            vm_ssh_direct "$1"
            ;;
    esac
}
