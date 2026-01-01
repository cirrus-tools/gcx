#!/bin/bash

# gcx-run.sh
# Cloud Run service management for gcx
# This file is sourced by gcx when running 'gcx run'

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# =============================================================================
# Service List
# =============================================================================

run_list() {
    local project=$(gcloud config get-value project 2>/dev/null)
    local region="${1:-}"

    local tmpfile=$(mktemp)
    local exit_code

    if [ -n "$region" ]; then
        gum spin --spinner dot --title "Loading Cloud Run services..." -- \
            sh -c "gcloud run services list --quiet --region='$region' --format='table(metadata.name,region,status.url,status.conditions[0].status)' > '$tmpfile' 2>&1"
        exit_code=$?
    else
        gum spin --spinner dot --title "Loading Cloud Run services..." -- \
            sh -c "gcloud run services list --quiet --format='table(metadata.name,region,status.url,status.conditions[0].status)' > '$tmpfile' 2>&1"
        exit_code=$?
    fi

    local result=$(cat "$tmpfile")
    rm -f "$tmpfile"

    if [ $exit_code -ne 0 ] || echo "$result" | grep -q "ERROR\|PERMISSION_DENIED"; then
        if echo "$result" | grep -q "API.*not enabled\|PERMISSION_DENIED"; then
            echo -e "${RED}Error: Cloud Run API not enabled or no permission${NC}"
            echo -e "${YELLOW}Enable it at: https://console.cloud.google.com/apis/library/run.googleapis.com${NC}"
        else
            echo -e "${RED}Error: $result${NC}"
        fi
        return 1
    fi

    if [ -z "$result" ]; then
        echo -e "${YELLOW}No Cloud Run services found in project ${project}${NC}"
        return 0
    fi

    echo "$result"
    echo ""
}

# =============================================================================
# Service Select (Interactive)
# =============================================================================

run_select() {
    local project=$(gcloud config get-value project 2>/dev/null)
    local tmpfile=$(mktemp)

    gum spin --spinner dot --title "Loading Cloud Run services..." -- \
        sh -c "gcloud run services list --quiet --format='value(metadata.name,region)' > '$tmpfile' 2>&1"
    local exit_code=$?

    local services=$(cat "$tmpfile")
    rm -f "$tmpfile"

    if [ $exit_code -ne 0 ] || echo "$services" | grep -q "ERROR\|PERMISSION_DENIED"; then
        if echo "$services" | grep -q "API.*not enabled\|PERMISSION_DENIED"; then
            echo -e "${RED}Error: Cloud Run API not enabled or no permission${NC}"
            echo -e "${YELLOW}Enable it at: https://console.cloud.google.com/apis/library/run.googleapis.com${NC}"
        else
            echo -e "${RED}Error loading services${NC}"
        fi
        return 1
    fi

    if [ -z "$services" ]; then
        echo -e "${YELLOW}No Cloud Run services found in project ${project}${NC}"
        return 1
    fi

    # Build selection list
    local options=""
    while IFS=$'\t' read -r name region; do
        options="${options}🚀 ${name} (${region})\n"
    done <<< "$services"

    local choice=$(echo -e "$options" | gum choose --header="Select service:" --header.foreground="4")

    if [ -z "$choice" ]; then
        echo "Cancelled."
        return 0
    fi

    # Extract service name and region
    local selected_name=$(echo "$choice" | sed 's/^[^ ]* //' | cut -d' ' -f1)
    local selected_region=$(echo "$choice" | grep -o '([^)]*' | sed 's/(//')

    echo ""
    echo -e "${GREEN}Selected: ${selected_name} (${selected_region})${NC}"
    echo ""

    # Show action menu
    run_actions "$selected_name" "$selected_region"
}

# =============================================================================
# Service Actions
# =============================================================================

run_actions() {
    local name="$1"
    local region="$2"

    local actions="🌐 Open URL\n📋 Show details\n📊 View logs\n🔄 Redeploy (latest)\n⚙️  Update traffic\n🗑️  Delete\n❌ Cancel"

    local action=$(echo -e "$actions" | gum choose --header="Action for ${name}:" --header.foreground="4")

    case "$action" in
        *"Open URL"*)
            run_open "$name" "$region"
            ;;
        *"Show details"*)
            run_describe "$name" "$region"
            ;;
        *"View logs"*)
            run_logs "$name" "$region"
            ;;
        *"Redeploy"*)
            run_redeploy "$name" "$region"
            ;;
        *"Update traffic"*)
            run_traffic "$name" "$region"
            ;;
        *"Delete"*)
            run_delete "$name" "$region"
            ;;
        *"Cancel"*)
            echo "Cancelled."
            ;;
    esac
}

run_open() {
    local name="$1"
    local region="$2"

    local url=$(gcloud run services describe "$name" --region="$region" --format="value(status.url)" 2>/dev/null)

    if [ -n "$url" ]; then
        echo -e "${BLUE}Opening: ${url}${NC}"
        open "$url"
    else
        echo -e "${RED}Could not get service URL${NC}"
    fi
}

run_describe() {
    local name="$1"
    local region="$2"

    echo -e "${BLUE}=== Service Details: ${name} ===${NC}"
    echo ""
    gcloud run services describe "$name" --region="$region" --format="yaml(metadata.name,status.url,spec.template.spec.containers[0].image,spec.template.spec.containers[0].resources,spec.traffic)"
}

run_logs() {
    local name="$1"
    local region="$2"

    echo -e "${BLUE}Streaming logs for ${name}...${NC}"
    echo -e "${YELLOW}(Press Ctrl+C to stop)${NC}"
    echo ""
    gcloud run services logs read "$name" --region="$region" --limit=50
}

run_redeploy() {
    local name="$1"
    local region="$2"

    # Get current image
    local image=$(gcloud run services describe "$name" --region="$region" --format="value(spec.template.spec.containers[0].image)" 2>/dev/null)

    if [ -z "$image" ]; then
        echo -e "${RED}Could not get current image${NC}"
        return 1
    fi

    echo -e "${BLUE}Current image: ${image}${NC}"

    if gum confirm "Redeploy ${name} with the same image?"; then
        echo -e "${BLUE}Redeploying ${name}...${NC}"
        gcloud run services update "$name" --region="$region" --image="$image"
        echo -e "${GREEN}Redeployed ${name}${NC}"
    else
        echo "Cancelled."
    fi
}

run_traffic() {
    local name="$1"
    local region="$2"

    echo -e "${BLUE}Current traffic allocation:${NC}"
    gcloud run services describe "$name" --region="$region" --format="yaml(spec.traffic)"
    echo ""

    # Get revisions
    local revisions=$(gcloud run revisions list --service="$name" --region="$region" --format="value(metadata.name)" 2>/dev/null)

    if [ -z "$revisions" ]; then
        echo -e "${YELLOW}No revisions found${NC}"
        return 1
    fi

    local options=""
    while read -r rev; do
        options="${options}${rev}\n"
    done <<< "$revisions"

    local selected=$(echo -e "$options" | gum choose --header="Route 100% traffic to:" --header.foreground="4")

    if [ -n "$selected" ]; then
        if gum confirm "Route all traffic to ${selected}?"; then
            gcloud run services update-traffic "$name" --region="$region" --to-revisions="${selected}=100"
            echo -e "${GREEN}Traffic updated${NC}"
        fi
    fi
}

run_delete() {
    local name="$1"
    local region="$2"

    echo -e "${RED}WARNING: This will delete the service ${name}${NC}"

    if gum confirm "Delete service ${name}?"; then
        echo -e "${BLUE}Deleting ${name}...${NC}"
        gcloud run services delete "$name" --region="$region" --quiet
        echo -e "${GREEN}Deleted ${name}${NC}"
    else
        echo "Cancelled."
    fi
}

# =============================================================================
# Direct Commands
# =============================================================================

run_logs_direct() {
    local query="$1"
    local region="$2"

    local matches
    if [ -n "$region" ]; then
        matches=$(gcloud run services list --region="$region" --format="value(metadata.name,region)" --filter="metadata.name~${query}" 2>/dev/null)
    else
        matches=$(gcloud run services list --format="value(metadata.name,region)" --filter="metadata.name~${query}" 2>/dev/null)
    fi

    local count=$(echo "$matches" | grep -c "." || echo "0")

    if [ "$count" -eq 0 ]; then
        echo -e "${RED}No service found matching: ${query}${NC}"
        return 1
    elif [ "$count" -eq 1 ]; then
        local name=$(echo "$matches" | cut -f1)
        local svc_region=$(echo "$matches" | cut -f2)
        run_logs "$name" "$svc_region"
    else
        echo -e "${YELLOW}Multiple services match '${query}':${NC}"
        while IFS=$'\t' read -r name svc_region; do
            echo "  - ${name} (${svc_region})"
        done <<< "$matches"
    fi
}

# =============================================================================
# Help
# =============================================================================

show_run_help() {
    cat << EOF
gcx run - Cloud Run service management

Usage: gcx run [command] [args]

Commands:
  (no args)       Interactive service selector
  list, ls        List all services
  logs <name>     View service logs
  open <name>     Open service URL in browser
  help            Show this help

Options:
  --region, -r    Specify region

Examples:
  gcx run                     Interactive mode
  gcx run list                List all services
  gcx run logs api            View logs for service matching 'api'
  gcx run open frontend       Open frontend service URL
EOF
}

# =============================================================================
# Main
# =============================================================================

run_main() {
    local region=""

    # Parse --region flag
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --region|-r)
                region="$2"
                shift 2
                ;;
            *)
                break
                ;;
        esac
    done

    case "${1:-}" in
        list|ls)
            run_list "$region"
            ;;
        logs)
            if [ -n "$2" ]; then
                run_logs_direct "$2" "$region"
            else
                run_select
            fi
            ;;
        open)
            if [ -n "$2" ]; then
                # Quick open by name
                local matches=$(gcloud run services list --format="value(metadata.name,region)" --filter="metadata.name~${2}" 2>/dev/null | head -1)
                if [ -n "$matches" ]; then
                    local name=$(echo "$matches" | cut -f1)
                    local svc_region=$(echo "$matches" | cut -f2)
                    run_open "$name" "$svc_region"
                else
                    echo -e "${RED}No service found matching: ${2}${NC}"
                fi
            else
                run_select
            fi
            ;;
        help|--help|-h)
            show_run_help
            ;;
        "")
            run_select
            ;;
        *)
            # Treat as service name, show actions
            local matches=$(gcloud run services list --format="value(metadata.name,region)" --filter="metadata.name~${1}" 2>/dev/null | head -1)
            if [ -n "$matches" ]; then
                local name=$(echo "$matches" | cut -f1)
                local svc_region=$(echo "$matches" | cut -f2)
                run_actions "$name" "$svc_region"
            else
                echo -e "${RED}No service found matching: ${1}${NC}"
                echo "Run 'gcx run help' for usage."
            fi
            ;;
    esac
}
