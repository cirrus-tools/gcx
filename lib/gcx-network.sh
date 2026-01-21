#!/bin/bash

# gcx-network.sh
# Network/VPC/IP address management for gcx
# This file is sourced by gcx when running 'gcx network'

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# =============================================================================
# Network List
# =============================================================================

network_list() {
    local project=$(gcloud config get-value project 2>/dev/null)
    local tmpfile=$(mktemp)

    gum spin --spinner dot --title "Loading networks..." -- \
        sh -c "gcloud compute networks list --quiet --format='table(name,SUBNET_MODE,BGP_ROUTING_MODE,IPv4_RANGE)' > '$tmpfile' 2>&1"
    local exit_code=$?

    local result=$(cat "$tmpfile")
    rm -f "$tmpfile"

    if [ $exit_code -ne 0 ] || echo "$result" | grep -q "ERROR\|PERMISSION_DENIED"; then
        if echo "$result" | grep -q "API.*not enabled\|PERMISSION_DENIED"; then
            echo -e "${RED}Error: Compute API not enabled or no permission${NC}"
            echo -e "${YELLOW}Enable it at: https://console.cloud.google.com/apis/library/compute.googleapis.com${NC}"
        else
            echo -e "${RED}Error: $result${NC}"
        fi
        return 1
    fi

    if [ -z "$result" ] || echo "$result" | grep -q "Listed 0 items"; then
        echo -e "${YELLOW}No networks found in project ${project}${NC}"
        return 0
    fi

    echo "$result"
    echo ""
}

# =============================================================================
# Subnets List
# =============================================================================

subnet_list() {
    local network="$1"
    local project=$(gcloud config get-value project 2>/dev/null)
    local tmpfile=$(mktemp)

    local filter=""
    [ -n "$network" ] && filter="--filter=network~${network}"

    gum spin --spinner dot --title "Loading subnets..." -- \
        sh -c "gcloud compute networks subnets list --quiet $filter --format='table(name,region.basename(),network.basename(),RANGE,STACK_TYPE)' > '$tmpfile' 2>&1"
    local exit_code=$?

    local result=$(cat "$tmpfile")
    rm -f "$tmpfile"

    if [ $exit_code -ne 0 ] || echo "$result" | grep -q "ERROR\|PERMISSION_DENIED"; then
        echo -e "${RED}Error: $result${NC}"
        return 1
    fi

    if [ -z "$result" ] || echo "$result" | grep -q "Listed 0 items"; then
        echo -e "${YELLOW}No subnets found${NC}"
        return 0
    fi

    echo "$result"
    echo ""
}

# =============================================================================
# IP Addresses List
# =============================================================================

ip_list() {
    local project=$(gcloud config get-value project 2>/dev/null)
    local tmpfile=$(mktemp)

    gum spin --spinner dot --title "Loading IP addresses..." -- \
        sh -c "gcloud compute addresses list --quiet --format='table(name,address,region.basename(),status,addressType,purpose)' > '$tmpfile' 2>&1"
    local exit_code=$?

    local result=$(cat "$tmpfile")
    rm -f "$tmpfile"

    if [ $exit_code -ne 0 ] || echo "$result" | grep -q "ERROR\|PERMISSION_DENIED"; then
        echo -e "${RED}Error: $result${NC}"
        return 1
    fi

    if [ -z "$result" ] || echo "$result" | grep -q "Listed 0 items"; then
        echo -e "${YELLOW}No reserved IP addresses in project ${project}${NC}"
        return 0
    fi

    echo "$result"
    echo ""
}

# =============================================================================
# Interactive Network Select
# =============================================================================

network_select() {
    local project=$(gcloud config get-value project 2>/dev/null)
    local tmpfile=$(mktemp)

    gum spin --spinner dot --title "Loading networks..." -- \
        sh -c "gcloud compute networks list --quiet --format='value(name,SUBNET_MODE,x_gcloud_bgp_routing_mode)' > '$tmpfile' 2>&1"
    local exit_code=$?

    local networks=$(cat "$tmpfile")
    rm -f "$tmpfile"

    if [ $exit_code -ne 0 ] || echo "$networks" | grep -q "ERROR\|PERMISSION_DENIED"; then
        echo -e "${RED}Error loading networks${NC}"
        return 1
    fi

    if [ -z "$networks" ]; then
        echo -e "${YELLOW}No networks found in project ${project}${NC}"
        return 1
    fi

    # Build selection list
    local options=""
    while IFS=$'\t' read -r name subnet_mode routing_mode; do
        local icon="🌐"
        [ "$subnet_mode" = "AUTO" ] && icon="🔄"
        [ "$subnet_mode" = "CUSTOM" ] && icon="⚙️"
        options="${options}${icon} ${name} | ${subnet_mode} | ${routing_mode:-REGIONAL}\n"
    done <<< "$networks"

    local choice=$(echo -e "$options" | gum filter --placeholder="Search network..." --header="Select network (type to filter):" --header.foreground="4")

    if [ -z "$choice" ]; then
        echo "Cancelled."
        return 0
    fi

    local selected_name=$(echo "$choice" | sed 's/^[^ ]* //' | cut -d'|' -f1 | xargs)

    echo ""
    echo -e "${GREEN}Selected: ${selected_name}${NC}"
    echo ""

    network_actions "$selected_name"
}

# =============================================================================
# Network Actions
# =============================================================================

network_actions() {
    local name="$1"

    local actions="📋 Show details\n🔌 List subnets\n🌐 List IP addresses\n🔧 Add subnet\n❌ Cancel"

    local action=$(echo -e "$actions" | gum choose --header="Action for ${name}:" --header.foreground="4")

    case "$action" in
        *"Show details"*)
            network_describe "$name"
            ;;
        *"List subnets"*)
            subnet_list "$name"
            ;;
        *"List IP addresses"*)
            ip_list
            ;;
        *"Add subnet"*)
            subnet_create "$name"
            ;;
        *"Cancel"*)
            echo "Cancelled."
            ;;
    esac
}

network_describe() {
    local name="$1"
    local tmpfile=$(mktemp)

    gum spin --spinner dot --title "Loading details..." -- \
        sh -c "gcloud compute networks describe '$name' --quiet --format='value(name,autoCreateSubnetworks,routingConfig.routingMode,subnetworks.len(),creationTimestamp)' > '$tmpfile' 2>&1"

    local info=$(cat "$tmpfile")
    rm -f "$tmpfile"

    IFS=$'\t' read -r net_name auto_create routing_mode subnet_count created <<< "$info"

    local mode="CUSTOM"
    [ "$auto_create" = "True" ] && mode="AUTO"

    echo ""
    gum style --border rounded --padding "1 2" --border-foreground 4 \
        "🌐 ${net_name}" \
        "" \
        "Mode:         ${mode}" \
        "Routing:      ${routing_mode:-REGIONAL}" \
        "Subnets:      ${subnet_count:-0}" \
        "Created:      ${created%T*}"
    echo ""
}

# =============================================================================
# Interactive IP Address Select
# =============================================================================

ip_select() {
    local project=$(gcloud config get-value project 2>/dev/null)
    local tmpfile=$(mktemp)

    gum spin --spinner dot --title "Loading IP addresses..." -- \
        sh -c "gcloud compute addresses list --quiet --format='value(name,address,region.basename(),status,addressType)' > '$tmpfile' 2>&1"
    local exit_code=$?

    local addresses=$(cat "$tmpfile")
    rm -f "$tmpfile"

    if [ $exit_code -ne 0 ] || echo "$addresses" | grep -q "ERROR\|PERMISSION_DENIED"; then
        echo -e "${RED}Error loading IP addresses${NC}"
        return 1
    fi

    if [ -z "$addresses" ]; then
        echo -e "${YELLOW}No reserved IP addresses in project ${project}${NC}"
        echo ""
        if gum confirm "Reserve a new IP address?"; then
            ip_reserve
        fi
        return 0
    fi

    # Build selection list
    local options=""
    while IFS=$'\t' read -r name address region status addr_type; do
        local icon="📍"
        [ "$status" = "IN_USE" ] && icon="🟢"
        [ "$status" = "RESERVED" ] && icon="🟡"
        [ "$addr_type" = "INTERNAL" ] && icon="🔒"
        local region_short="${region:-global}"
        options="${options}${icon} ${name} | ${address} | ${region_short} | ${status}\n"
    done <<< "$addresses"

    options="${options}➕ Reserve new IP address"

    local choice=$(echo -e "$options" | gum filter --placeholder="Search IP..." --header="Select IP address:" --header.foreground="4")

    if [ -z "$choice" ]; then
        echo "Cancelled."
        return 0
    fi

    if [[ "$choice" == *"Reserve new"* ]]; then
        ip_reserve
        return 0
    fi

    local selected_name=$(echo "$choice" | sed 's/^[^ ]* //' | cut -d'|' -f1 | xargs)
    local selected_ip=$(echo "$choice" | cut -d'|' -f2 | xargs)

    echo ""
    echo -e "${GREEN}Selected: ${selected_name} (${selected_ip})${NC}"
    echo ""

    ip_actions "$selected_name"
}

# =============================================================================
# IP Address Actions
# =============================================================================

ip_actions() {
    local name="$1"

    # Get IP details
    local tmpfile=$(mktemp)
    gcloud compute addresses describe "$name" --format="value(address,region.basename(),status,addressType)" > "$tmpfile" 2>/dev/null
    local info=$(cat "$tmpfile")
    rm -f "$tmpfile"

    IFS=$'\t' read -r address region status addr_type <<< "$info"

    local actions="📋 Show details\n📋 Copy IP to clipboard"
    [ "$status" = "RESERVED" ] && actions="${actions}\n🗑️  Release (delete)"
    actions="${actions}\n❌ Cancel"

    local action=$(echo -e "$actions" | gum choose --header="Action for ${name} (${address}):" --header.foreground="4")

    case "$action" in
        *"Show details"*)
            ip_describe "$name" "$region"
            ;;
        *"Copy IP"*)
            echo -n "$address" | pbcopy
            echo -e "${GREEN}Copied ${address} to clipboard${NC}"
            ;;
        *"Release"*)
            ip_release "$name" "$region"
            ;;
        *"Cancel"*)
            echo "Cancelled."
            ;;
    esac
}

ip_describe() {
    local name="$1"
    local region="$2"
    local tmpfile=$(mktemp)

    local region_flag=""
    [ -n "$region" ] && region_flag="--region=$region"

    gum spin --spinner dot --title "Loading details..." -- \
        sh -c "gcloud compute addresses describe '$name' $region_flag --quiet --format='value(name,address,region.basename(),status,addressType,subnetwork.basename(),users[0].basename(),creationTimestamp)' > '$tmpfile' 2>&1"

    local info=$(cat "$tmpfile")
    rm -f "$tmpfile"

    IFS=$'\t' read -r ip_name address ip_region status addr_type subnet user created <<< "$info"

    local status_icon="🟡"
    [ "$status" = "IN_USE" ] && status_icon="🟢"

    echo ""
    gum style --border rounded --padding "1 2" --border-foreground 4 \
        "${status_icon} ${ip_name}" \
        "" \
        "Address:   ${address}" \
        "Region:    ${ip_region:-global}" \
        "Status:    ${status}" \
        "Type:      ${addr_type}" \
        "Subnet:    ${subnet:-N/A}" \
        "Used by:   ${user:-none}" \
        "Created:   ${created%T*}"
    echo ""
}

ip_reserve() {
    echo ""
    echo -e "${BLUE}Reserve a new IP address${NC}"
    echo ""

    # Name
    local name=$(gum input --placeholder "my-ip-address" --header="IP name:")
    [ -z "$name" ] && { echo "Cancelled."; return 0; }

    # Type
    local addr_type=$(echo -e "EXTERNAL\nINTERNAL" | gum choose --header="Address type:")
    [ -z "$addr_type" ] && { echo "Cancelled."; return 0; }

    # Region
    local regions=$(gcloud compute regions list --format="value(name)" 2>/dev/null)
    local region=$(echo "$regions" | gum filter --placeholder="Select region..." --header="Region:")
    [ -z "$region" ] && { echo "Cancelled."; return 0; }

    # For internal, need network and subnet
    local extra_flags=""
    if [ "$addr_type" = "INTERNAL" ]; then
        # Get subnets in this region
        local subnets=$(gcloud compute networks subnets list --filter="region:${region}" --format="value(name)" 2>/dev/null)
        if [ -z "$subnets" ]; then
            echo -e "${RED}No subnets found in region ${region}${NC}"
            return 1
        fi
        local subnet=$(echo "$subnets" | gum filter --placeholder="Select subnet..." --header="Subnet:")
        [ -z "$subnet" ] && { echo "Cancelled."; return 0; }
        extra_flags="--subnet=${subnet}"
    fi

    echo ""
    echo -e "${BLUE}Reserving IP address...${NC}"
    if gcloud compute addresses create "$name" --region="$region" --address-type="$addr_type" $extra_flags; then
        local new_ip=$(gcloud compute addresses describe "$name" --region="$region" --format="value(address)" 2>/dev/null)
        echo -e "${GREEN}Reserved: ${new_ip}${NC}"
    else
        echo -e "${RED}Failed to reserve IP address${NC}"
    fi
}

ip_release() {
    local name="$1"
    local region="$2"

    echo -e "${RED}WARNING: This will release (delete) the IP address ${name}${NC}"
    echo -e "${YELLOW}The IP may be assigned to someone else and you cannot get it back.${NC}"
    echo ""

    if gum confirm "Release IP address ${name}?"; then
        local region_flag=""
        [ -n "$region" ] && region_flag="--region=$region"

        echo -e "${BLUE}Releasing ${name}...${NC}"
        if gcloud compute addresses delete "$name" $region_flag --quiet; then
            echo -e "${GREEN}Released ${name}${NC}"
        else
            echo -e "${RED}Failed to release IP address${NC}"
        fi
    else
        echo "Cancelled."
    fi
}

# =============================================================================
# Subnet Create
# =============================================================================

subnet_create() {
    local network="$1"

    echo ""
    echo -e "${BLUE}Create a new subnet in ${network}${NC}"
    echo ""

    # Name
    local name=$(gum input --placeholder "my-subnet" --header="Subnet name:")
    [ -z "$name" ] && { echo "Cancelled."; return 0; }

    # Region
    local regions=$(gcloud compute regions list --format="value(name)" 2>/dev/null)
    local region=$(echo "$regions" | gum filter --placeholder="Select region..." --header="Region:")
    [ -z "$region" ] && { echo "Cancelled."; return 0; }

    # IP Range
    local range=$(gum input --placeholder "10.0.0.0/24" --header="IP range (CIDR):")
    [ -z "$range" ] && { echo "Cancelled."; return 0; }

    echo ""
    echo -e "${BLUE}Creating subnet...${NC}"
    if gcloud compute networks subnets create "$name" \
        --network="$network" \
        --region="$region" \
        --range="$range"; then
        echo -e "${GREEN}Created subnet ${name}${NC}"
    else
        echo -e "${RED}Failed to create subnet${NC}"
    fi
}

# =============================================================================
# Firewall List (Quick view)
# =============================================================================

firewall_list() {
    local network="$1"
    local project=$(gcloud config get-value project 2>/dev/null)
    local tmpfile=$(mktemp)

    local filter=""
    [ -n "$network" ] && filter="--filter=network~${network}"

    gum spin --spinner dot --title "Loading firewall rules..." -- \
        sh -c "gcloud compute firewall-rules list --quiet $filter --format='table(name,network.basename(),direction,priority,sourceRanges.list():label=SRC_RANGES,allowed[].map().firewall_rule().list():label=ALLOW)' > '$tmpfile' 2>&1"
    local exit_code=$?

    local result=$(cat "$tmpfile")
    rm -f "$tmpfile"

    if [ $exit_code -ne 0 ] || echo "$result" | grep -q "ERROR\|PERMISSION_DENIED"; then
        echo -e "${RED}Error: $result${NC}"
        return 1
    fi

    if [ -z "$result" ] || echo "$result" | grep -q "Listed 0 items"; then
        echo -e "${YELLOW}No firewall rules found${NC}"
        return 0
    fi

    echo "$result"
    echo ""
}

# =============================================================================
# Main Menu
# =============================================================================

network_menu() {
    local options="🌐 Networks (VPC)\n📍 IP Addresses\n🔌 Subnets\n🛡️  Firewall Rules\n❌ Cancel"

    local choice=$(echo -e "$options" | gum choose --header="Network resources:" --header.foreground="4")

    case "$choice" in
        *"Networks"*)
            network_select
            ;;
        *"IP Addresses"*)
            ip_select
            ;;
        *"Subnets"*)
            subnet_list
            ;;
        *"Firewall"*)
            firewall_list
            ;;
        *"Cancel"*)
            echo "Cancelled."
            ;;
    esac
}

# =============================================================================
# Help
# =============================================================================

show_network_help() {
    cat << EOF
gcx network - Network/VPC/IP management

Usage: gcx network [command] [args]

Commands:
  (no args)       Interactive menu
  list, ls        List all VPC networks
  subnets         List all subnets
  ip              List/manage IP addresses
  ip list         List reserved IP addresses
  ip reserve      Reserve a new IP address
  firewall        List firewall rules
  help            Show this help

Examples:
  gcx network                 Interactive mode
  gcx network list            List VPC networks
  gcx network subnets         List all subnets
  gcx network ip              Interactive IP management
  gcx network ip list         List reserved IPs
  gcx network ip reserve      Reserve new IP
  gcx network firewall        List firewall rules
EOF
}

# =============================================================================
# Main
# =============================================================================

network_main() {
    case "${1:-}" in
        list|ls)
            network_list
            ;;
        subnets|subnet)
            subnet_list "$2"
            ;;
        ip)
            case "${2:-}" in
                list|ls)
                    ip_list
                    ;;
                reserve|create)
                    ip_reserve
                    ;;
                "")
                    ip_select
                    ;;
                *)
                    # Treat as IP name, show details
                    ip_describe "$2"
                    ;;
            esac
            ;;
        firewall|fw)
            firewall_list "$2"
            ;;
        help|--help|-h)
            show_network_help
            ;;
        "")
            network_menu
            ;;
        *)
            # Treat as network name
            network_describe "$1"
            ;;
    esac
}
