#!/bin/bash

# gcx-gke.sh
# GKE cluster management for gcx
# This file is sourced by gcx when running 'gcx gke'

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

gke_list() {
    local project=$(gcloud config get-value project 2>/dev/null)
    local tmpfile=$(mktemp)

    gum spin --spinner dot --title "Loading GKE clusters..." -- \
        sh -c "gcloud container clusters list --quiet --format='table(name,location,master_version,currentNodeCount,status)' > '$tmpfile' 2>&1"
    local exit_code=$?

    local result=$(cat "$tmpfile")
    rm -f "$tmpfile"

    if [ $exit_code -ne 0 ] || echo "$result" | grep -q "ERROR\|PERMISSION_DENIED"; then
        if echo "$result" | grep -q "API.*not enabled\|PERMISSION_DENIED"; then
            echo -e "${RED}Error: Kubernetes Engine API not enabled or no permission${NC}"
            echo -e "${YELLOW}Enable it at: https://console.cloud.google.com/apis/library/container.googleapis.com${NC}"
        else
            echo -e "${RED}Error: $result${NC}"
        fi
        return 1
    fi

    if [ -z "$result" ] || echo "$result" | grep -q "Listed 0 items"; then
        echo -e "${YELLOW}No GKE clusters found in project ${project}${NC}"
        return 0
    fi

    echo "$result"
    echo ""
}

gke_select() {
    local project=$(gcloud config get-value project 2>/dev/null)
    local tmpfile=$(mktemp)

    gum spin --spinner dot --title "Loading GKE clusters..." -- \
        sh -c "gcloud container clusters list --quiet --format='value(name,location,status,currentNodeCount,master_version)' > '$tmpfile' 2>&1"
    local exit_code=$?

    local clusters=$(cat "$tmpfile")
    rm -f "$tmpfile"

    if [ $exit_code -ne 0 ] || echo "$clusters" | grep -q "ERROR\|PERMISSION_DENIED"; then
        if echo "$clusters" | grep -q "API.*not enabled\|PERMISSION_DENIED"; then
            echo -e "${RED}Error: Kubernetes Engine API not enabled or no permission${NC}"
            echo -e "${YELLOW}Enable it at: https://console.cloud.google.com/apis/library/container.googleapis.com${NC}"
        else
            echo -e "${RED}Error loading clusters${NC}"
        fi
        return 1
    fi

    if [ -z "$clusters" ]; then
        echo -e "${YELLOW}No GKE clusters found in project ${project}${NC}"
        return 1
    fi

    local options=""
    while IFS=$'\t' read -r name location status nodes version; do
        local icon="⚪"
        [ "$status" = "RUNNING" ] && icon="🟢"
        [ "$status" = "PROVISIONING" ] && icon="🟡"
        [ "$status" = "STOPPING" ] && icon="🔴"
        [ "$status" = "ERROR" ] && icon="❌"

        options="${options}${icon} ${name} | ${location} | ${nodes} nodes | ${version}\n"
    done <<< "$clusters"

    local choice=$(echo -e "$options" | gum filter --placeholder="Search cluster..." --header="Select GKE cluster:" --header.foreground="4")

    if [ -z "$choice" ]; then
        echo "Cancelled."
        return 0
    fi

    local selected_name=$(echo "$choice" | sed 's/^[^ ]* //' | cut -d'|' -f1 | xargs)
    local selected_location=$(echo "$choice" | cut -d'|' -f2 | xargs)

    echo ""
    echo -e "${GREEN}Selected: ${selected_name} (${selected_location})${NC}"
    echo ""

    gke_actions "$selected_name" "$selected_location"
}

gke_actions() {
    local name="$1"
    local location="$2"

    local actions="🔑 Get credentials (kubectl)\n📋 Show details\n📊 List node pools\n🔧 Resize node pool\n🌐 Open in Console\n❌ Cancel"

    local action=$(echo -e "$actions" | gum choose --header="Action for ${name}:" --header.foreground="4")

    case "$action" in
        *"Get credentials"*)
            gke_credentials "$name" "$location"
            ;;
        *"Show details"*)
            gke_describe "$name" "$location"
            ;;
        *"List node pools"*)
            gke_nodepools "$name" "$location"
            ;;
        *"Resize"*)
            gke_resize "$name" "$location"
            ;;
        *"Open in Console"*)
            gke_open "$name" "$location"
            ;;
        *"Cancel"*)
            echo "Cancelled."
            ;;
    esac
}

gke_credentials() {
    local name="$1"
    local location="$2"

    echo -e "${BLUE}Getting credentials for ${name}...${NC}"

    local location_flag="--region=$location"
    if [[ "$location" == *-[a-z] ]]; then
        location_flag="--zone=$location"
    fi

    if gcloud container clusters get-credentials "$name" $location_flag; then
        echo -e "${GREEN}✓ Credentials configured for kubectl${NC}"
        echo ""
        echo "Current context:"
        kubectl config current-context
    else
        echo -e "${RED}Failed to get credentials${NC}"
    fi
}

gke_describe() {
    local name="$1"
    local location="$2"
    local tmpfile=$(mktemp)

    local location_flag="--region=$location"
    if [[ "$location" == *-[a-z] ]]; then
        location_flag="--zone=$location"
    fi

    gum spin --spinner dot --title "Loading details..." -- \
        sh -c "gcloud container clusters describe '$name' $location_flag --quiet --format='value(name,location,currentMasterVersion,currentNodeCount,status,network,subnetwork,endpoint,createTime)' > '$tmpfile' 2>&1"

    local info=$(cat "$tmpfile")
    rm -f "$tmpfile"

    IFS=$'\t' read -r cluster_name loc version nodes status network subnet endpoint created <<< "$info"

    local status_icon="⚪"
    [ "$status" = "RUNNING" ] && status_icon="🟢"
    [ "$status" = "PROVISIONING" ] && status_icon="🟡"

    echo ""
    gum style --border rounded --padding "1 2" --border-foreground 4 \
        "${status_icon} ${cluster_name}" \
        "" \
        "Location:  ${loc}" \
        "Version:   ${version}" \
        "Nodes:     ${nodes}" \
        "Status:    ${status}" \
        "Network:   ${network##*/}" \
        "Subnet:    ${subnet##*/}" \
        "Endpoint:  ${endpoint}" \
        "Created:   ${created%T*}"
    echo ""
}

gke_nodepools() {
    local name="$1"
    local location="$2"
    local tmpfile=$(mktemp)

    local location_flag="--region=$location"
    if [[ "$location" == *-[a-z] ]]; then
        location_flag="--zone=$location"
    fi

    gum spin --spinner dot --title "Loading node pools..." -- \
        sh -c "gcloud container node-pools list --cluster='$name' $location_flag --quiet --format='table(name,config.machineType,autoscaling.enabled,autoscaling.minNodeCount,autoscaling.maxNodeCount,status)' > '$tmpfile' 2>&1"

    local result=$(cat "$tmpfile")
    rm -f "$tmpfile"

    if [ -z "$result" ]; then
        echo -e "${YELLOW}No node pools found${NC}"
        return 0
    fi

    echo "$result"
    echo ""
}

gke_resize() {
    local name="$1"
    local location="$2"

    local location_flag="--region=$location"
    if [[ "$location" == *-[a-z] ]]; then
        location_flag="--zone=$location"
    fi

    local pools=$(gcloud container node-pools list --cluster="$name" $location_flag --format="value(name)" 2>/dev/null)

    if [ -z "$pools" ]; then
        echo -e "${YELLOW}No node pools found${NC}"
        return 1
    fi

    local pool=$(echo "$pools" | gum choose --header="Select node pool to resize:" --header.foreground="4")
    [ -z "$pool" ] && { echo "Cancelled."; return 0; }

    local current_size=$(gcloud container node-pools describe "$pool" --cluster="$name" $location_flag --format="value(initialNodeCount)" 2>/dev/null)

    echo -e "Current size: ${CYAN}${current_size}${NC}"

    local new_size=$(gum input --placeholder "$current_size" --header="New node count:")
    [ -z "$new_size" ] && { echo "Cancelled."; return 0; }

    if gum confirm "Resize ${pool} from ${current_size} to ${new_size} nodes?"; then
        echo -e "${BLUE}Resizing node pool...${NC}"
        if gcloud container clusters resize "$name" --node-pool="$pool" --num-nodes="$new_size" $location_flag --quiet; then
            echo -e "${GREEN}Resized ${pool} to ${new_size} nodes${NC}"
        else
            echo -e "${RED}Failed to resize${NC}"
        fi
    else
        echo "Cancelled."
    fi
}

gke_open() {
    local name="$1"
    local location="$2"
    local project=$(gcloud config get-value project 2>/dev/null)

    local url="https://console.cloud.google.com/kubernetes/clusters/details/${location}/${name}/details?project=${project}"
    echo -e "${BLUE}Opening: ${url}${NC}"
    open "$url"
}

show_gke_help() {
    cat << EOF
gcx gke - GKE cluster management

Usage: gcx gke [command] [args]

Commands:
  (no args)         Interactive cluster selector
  list, ls          List all clusters
  credentials <n>   Get kubectl credentials for cluster
  nodepools <name>  List node pools
  help              Show this help

Examples:
  gcx gke                      Interactive mode
  gcx gke list                 List all clusters
  gcx gke credentials my-gke   Get kubectl config
  gcx gke nodepools my-gke     List node pools
EOF
}

gke_main() {
    case "${1:-}" in
        list|ls)
            gke_list
            ;;
        credentials|creds)
            if [ -n "$2" ]; then
                local location="${3:-}"
                if [ -z "$location" ]; then
                    local match=$(gcloud container clusters list --format="value(name,location)" --filter="name=$2" 2>/dev/null | head -1)
                    if [ -n "$match" ]; then
                        location=$(echo "$match" | cut -f2)
                    else
                        echo -e "${RED}Cluster not found: $2${NC}"
                        return 1
                    fi
                fi
                gke_credentials "$2" "$location"
            else
                gke_select
            fi
            ;;
        nodepools|np)
            if [ -n "$2" ]; then
                local location="${3:-}"
                if [ -z "$location" ]; then
                    local match=$(gcloud container clusters list --format="value(name,location)" --filter="name=$2" 2>/dev/null | head -1)
                    if [ -n "$match" ]; then
                        location=$(echo "$match" | cut -f2)
                    fi
                fi
                gke_nodepools "$2" "$location"
            else
                gke_select
            fi
            ;;
        help|--help|-h)
            show_gke_help
            ;;
        "")
            gke_select
            ;;
        *)
            local match=$(gcloud container clusters list --format="value(name,location)" --filter="name~$1" 2>/dev/null | head -1)
            if [ -n "$match" ]; then
                local name=$(echo "$match" | cut -f1)
                local location=$(echo "$match" | cut -f2)
                gke_actions "$name" "$location"
            else
                echo -e "${RED}Cluster not found: $1${NC}"
            fi
            ;;
    esac
}
