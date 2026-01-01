#!/bin/bash

# gcx - GCloud Context Switcher
# Quick switch between GCP organizations, accounts, projects, and kubeconfig
# Usage: gcx [org] [identity]
#        gcx setup
#
# Reads configuration from ~/.config/gcx/config.yaml

# set -e disabled - gcloud commands may return non-zero on warnings

# Paths
CONFIG_DIR="$HOME/.config/gcx"
CONFIG_FILE="$CONFIG_DIR/config.yaml"
KUBECONFIG_DIR="$HOME/.kube"
KUBECONFIG_PATH="$KUBECONFIG_DIR/config"
ADC_PATH="$HOME/.config/gcloud/application_default_credentials.json"
CREDS_DIR="$HOME/.config/gcloud-creds"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Color name to ANSI code mapping
get_color_code() {
    case "$1" in
        red)     echo "$RED" ;;
        green)   echo "$GREEN" ;;
        yellow)  echo "$YELLOW" ;;
        blue)    echo "$BLUE" ;;
        magenta) echo "$MAGENTA" ;;
        cyan)    echo "$CYAN" ;;
        *)       echo "$GREEN" ;;
    esac
}

# =============================================================================
# Config Loading
# =============================================================================

has_config() {
    [ -f "$CONFIG_FILE" ] && command -v yq &>/dev/null
}

get_orgs() {
    if has_config; then
        yq '.organizations | keys | .[]' "$CONFIG_FILE" 2>/dev/null
    else
        echo ""
    fi
}

get_org_display_name() {
    local org="$1"
    if has_config; then
        yq ".organizations.$org.display_name // \"$org\"" "$CONFIG_FILE" 2>/dev/null
    else
        echo "$org"
    fi
}

get_org_color_name() {
    local org="$1"
    if has_config; then
        yq ".organizations.$org.color // \"green\"" "$CONFIG_FILE" 2>/dev/null
    else
        echo "cyan"
    fi
}

get_org_gcloud_config() {
    local org="$1"
    if has_config; then
        yq ".organizations.$org.gcloud_config // \"\"" "$CONFIG_FILE" 2>/dev/null
    else
        echo ""
    fi
}

get_org_kubeconfig() {
    local org="$1"
    if has_config; then
        yq ".organizations.$org.kubeconfig // \"\"" "$CONFIG_FILE" 2>/dev/null
    else
        echo ""
    fi
}

get_org_identities() {
    local org="$1"
    if has_config; then
        yq ".organizations.$org.identities | keys | .[]" "$CONFIG_FILE" 2>/dev/null
    else
        echo ""
    fi
}

get_identity_name() {
    local org="$1"
    local id="$2"
    if has_config; then
        yq ".organizations.$org.identities.$id.name // \"$id\"" "$CONFIG_FILE" 2>/dev/null
    else
        echo "$id"
    fi
}

get_identity_account() {
    local org="$1"
    local id="$2"
    if has_config; then
        yq ".organizations.$org.identities.$id.account // \"\"" "$CONFIG_FILE" 2>/dev/null
    else
        # No fallback - config required for account info
        echo ""
    fi
}

get_identity_adc() {
    local org="$1"
    local id="$2"
    if has_config; then
        yq ".organizations.$org.identities.$id.adc // \"\"" "$CONFIG_FILE" 2>/dev/null
    else
        # No fallback - config required for ADC info
        echo ""
    fi
}

get_identity_project() {
    local org="$1"
    local id="$2"
    if has_config; then
        yq ".organizations.$org.identities.$id.project // \"\"" "$CONFIG_FILE" 2>/dev/null
    else
        echo ""
    fi
}

get_default_org() {
    if has_config; then
        yq ".default_org // \"\"" "$CONFIG_FILE" 2>/dev/null
    else
        echo ""
    fi
}

# =============================================================================
# Status Display
# =============================================================================

get_current_org() {
    local active_config=$(gcloud config configurations list --filter="is_active=true" --format="value(name)" 2>/dev/null)
    local orgs=$(get_orgs)
    
    for org in $orgs; do
        local org_config=$(get_org_gcloud_config "$org")
        if [ "$org_config" = "$active_config" ]; then
            echo "$org"
            return
        fi
    done
    echo ""
}

show_status() {
    local current_org=$(get_current_org)
    local color_name=$(get_org_color_name "$current_org")
    local ORG_COLOR=$(get_color_code "$color_name")
    local ORG_NAME=$(get_org_display_name "$current_org")
    
    if [ -z "$current_org" ]; then
        ORG_COLOR="$CYAN"
        ORG_NAME="Unknown"
    fi
    
    echo ""
    echo -e "${ORG_COLOR}=== Current Context [${ORG_NAME}] ===${NC}"

    # gcloud
    local GCLOUD_ACCOUNT=$(gcloud config get-value account 2>/dev/null)
    local GCLOUD_PROJECT=$(gcloud config get-value project 2>/dev/null)
    echo -e "gcloud account: ${ORG_COLOR}${GCLOUD_ACCOUNT}${NC}"
    echo -e "gcloud project: ${ORG_COLOR}${GCLOUD_PROJECT}${NC}"

    # kubeconfig
    if [ -L "$KUBECONFIG_PATH" ]; then
        local KUBE_LINK=$(readlink "$KUBECONFIG_PATH" | xargs basename)
        echo -e "kubeconfig:     ${ORG_COLOR}${KUBE_LINK}${NC}"
    else
        local KUBE_CTX=$(kubectl config current-context 2>/dev/null || echo "none")
        echo -e "kube context:   ${ORG_COLOR}${KUBE_CTX}${NC}"
    fi

    # ADC
    if [ -L "$ADC_PATH" ]; then
        local ADC_LINK=$(readlink "$ADC_PATH" | xargs basename)
        echo -e "ADC:            ${ORG_COLOR}${ADC_LINK}${NC}"
    elif [ -f "$ADC_PATH" ]; then
        echo -e "ADC:            ${YELLOW}user login${NC}"
    else
        echo -e "ADC:            ${RED}not set${NC}"
    fi
    echo ""
}

# =============================================================================
# Switch Functions
# =============================================================================

switch_to_org() {
    local org="$1"
    local identity="$2"
    
    local display_name=$(get_org_display_name "$org")
    local color_name=$(get_org_color_name "$org")
    local ORG_COLOR=$(get_color_code "$color_name")
    
    echo -e "${BLUE}Switching to ${display_name}...${NC}"
    
    # Switch gcloud configuration
    local gcloud_config=$(get_org_gcloud_config "$org")
    if [ -n "$gcloud_config" ]; then
        if gcloud config configurations list --format="value(name)" | grep -q "^${gcloud_config}$"; then
            gcloud config configurations activate "$gcloud_config" 2>/dev/null
            echo -e "  gcloud config: ${ORG_COLOR}${gcloud_config}${NC}"
        else
            echo -e "  gcloud config: ${YELLOW}${gcloud_config} not found, skipping${NC}"
        fi
    fi
    
    # Switch kubeconfig
    local kubeconfig=$(get_org_kubeconfig "$org")
    if [ -n "$kubeconfig" ]; then
        if [ -f "$KUBECONFIG_DIR/$kubeconfig" ]; then
            rm -f "$KUBECONFIG_PATH"
            ln -s "$KUBECONFIG_DIR/$kubeconfig" "$KUBECONFIG_PATH"
            echo -e "  kubeconfig:    ${ORG_COLOR}${kubeconfig}${NC}"
        else
            echo -e "  kubeconfig:    ${YELLOW}${kubeconfig} not found${NC}"
        fi
    fi
    
    # Get identities for this org
    local identities=$(get_org_identities "$org")
    local identity_count=$(echo "$identities" | wc -l | tr -d ' ')
    
    # If identity not specified and multiple options, ask user
    if [ -z "$identity" ] && [ "$identity_count" -gt 1 ]; then
        local options=""
        for id in $identities; do
            local id_name=$(get_identity_name "$org" "$id")
            local id_account=$(get_identity_account "$org" "$id")
            local id_adc=$(get_identity_adc "$org" "$id")
            if [ -f "$CREDS_DIR/$id_adc" ]; then
                local emoji="👤"
                [[ "$id_name" == *"Service"* ]] && emoji="🤖"
                options="${options}${emoji} ${id_name} (${id_account})\n"
            fi
        done
        
        if [ -n "$options" ]; then
            local choice=$(echo -e "$options" | gum choose --limit=1 --header="Select identity (gcloud + ADC):" --header.foreground="4")
            
            # Find which identity was selected
            for id in $identities; do
                local id_name=$(get_identity_name "$org" "$id")
                if [[ "$choice" == *"$id_name"* ]]; then
                    identity="$id"
                    break
                fi
            done
        fi
    fi
    
    # Default to first identity if not set
    if [ -z "$identity" ]; then
        identity=$(echo "$identities" | head -n1)
    fi
    
    # Apply identity (account + ADC + project)
    if [ -n "$identity" ]; then
        local account=$(get_identity_account "$org" "$identity")
        local adc=$(get_identity_adc "$org" "$identity")
        local project=$(get_identity_project "$org" "$identity")
        local id_name=$(get_identity_name "$org" "$identity")
        
        if [ -n "$account" ]; then
            gcloud config set account "$account" 2>/dev/null
            echo -e "  gcloud account: ${ORG_COLOR}${account}${NC}"
        fi
        
        if [ -n "$project" ]; then
            gcloud config set project "$project" 2>/dev/null
            echo -e "  gcloud project: ${ORG_COLOR}${project}${NC}"
        fi
        
        if [ -n "$adc" ] && [ -f "$CREDS_DIR/$adc" ]; then
            rm -f "$ADC_PATH"
            ln -s "$CREDS_DIR/$adc" "$ADC_PATH"
            echo -e "  ADC:            ${ORG_COLOR}${adc} (${id_name})${NC}"
        elif [ -n "$adc" ]; then
            echo -e "  ADC:            ${YELLOW}${adc} not found${NC}"
        fi
    fi
    
    echo -e "${ORG_COLOR}Switched to ${display_name}${NC}"
}

# =============================================================================
# Main
# =============================================================================

show_help() {
    cat << EOF
gcx - GCloud Context Switcher

Usage: gcx [command] [options]

Commands:
  (no args)       Interactive mode - show status and switch
  <org>           Switch to organization
  <org> <id>      Switch to org with specific identity
  status, s       Show current context
  project, p      Quick switch project
  setup           Run setup wizard
  help            Show this help

Setup Commands:
  setup init      Initialize configuration
  setup add-org   Add new organization
  setup add-id    Add identity to org
  setup export    Export template for sharing
  setup import    Import template
  setup edit      Edit config file

Examples:
  gcx                     Interactive mode
  gcx myorg               Switch to myorg
  gcx myorg sa            Switch to myorg with SA identity
  gcx project             Quick switch project
  gcx setup               Run setup wizard
EOF
}

switch_project() {
    echo -e "${BLUE}Loading projects...${NC}"
    local projects=$(gcloud projects list --format="value(projectId)" 2>/dev/null)
    
    if [ -z "$projects" ]; then
        echo -e "${RED}No projects found or not authenticated${NC}"
        return 1
    fi
    
    local current=$(gcloud config get-value project 2>/dev/null)
    local selected=$(echo "$projects" | gum choose --limit=1 --header="Select project (current: $current):" --header.foreground="4")
    
    if [ -n "$selected" ]; then
        gcloud config set project "$selected" 2>/dev/null
        echo -e "${GREEN}Switched to project: ${selected}${NC}"
    fi
}

main() {
    case "${1:-}" in
        status|s)
            show_status
            ;;
        project|p)
            switch_project
            show_status
            ;;
        setup)
            # Find lib directory
            SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
            if [ -f "$SCRIPT_DIR/../lib/gcx-setup.sh" ]; then
                source "$SCRIPT_DIR/../lib/gcx-setup.sh"
            elif [ -f "$SCRIPT_DIR/gcx-setup.sh" ]; then
                source "$SCRIPT_DIR/gcx-setup.sh"
            elif [ -f "/usr/local/lib/gcx/gcx-setup.sh" ]; then
                source "/usr/local/lib/gcx/gcx-setup.sh"
            else
                echo "Error: gcx-setup.sh not found"
                exit 1
            fi
            shift
            main "$@"
            ;;
        help|--help|-h)
            show_help
            ;;
        "")
            # Interactive mode
            show_status
            
            local orgs=$(get_orgs)
            local options=""
            for org in $orgs; do
                local display=$(get_org_display_name "$org")
                options="${options}${display}\n"
            done
            options="${options}Status only"
            
            local choice=$(echo -e "$options" | gum choose --limit=1 --header="Switch to:" --header.foreground="4")
            
            if [ "$choice" != "Status only" ]; then
                # Find org by display name
                for org in $orgs; do
                    local display=$(get_org_display_name "$org")
                    if [ "$display" = "$choice" ]; then
                        switch_to_org "$org"
                        show_status
                        break
                    fi
                done
            fi
            ;;
        *)
            # Direct org switch
            local org="$1"
            local identity="$2"
            
            # Check if org exists
            local orgs=$(get_orgs)
            local found=false
            for o in $orgs; do
                if [ "$o" = "$org" ]; then
                    found=true
                    break
                fi
                # Also check display names (case insensitive)
                local display=$(get_org_display_name "$o")
                local display_lower=$(echo "$display" | tr '[:upper:]' '[:lower:]')
                local org_lower=$(echo "$org" | tr '[:upper:]' '[:lower:]')
                if [ "$display_lower" = "$org_lower" ]; then
                    org="$o"
                    found=true
                    break
                fi
            done
            
            if [ "$found" = true ]; then
                switch_to_org "$org" "$identity"
                show_status
            else
                echo -e "${RED}Unknown organization: $org${NC}"
                echo "Available: $(get_orgs | tr '\n' ' ')"
                exit 1
            fi
            ;;
    esac
}

main "$@"
