#!/bin/bash

# gcx-adc.sh
# ADC (Application Default Credentials) management for gcx
# This file is sourced by gcx when running 'gcx adc'

ADC_PATH="$HOME/.config/gcloud/application_default_credentials.json"
CREDS_DIR="$HOME/.config/gcloud-creds"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# =============================================================================
# ADC Status
# =============================================================================

get_adc_expiry() {
    if [ ! -f "$ADC_PATH" ]; then
        echo ""
        return
    fi

    # Check if it's a symlink to a service account key (no expiry)
    if [ -L "$ADC_PATH" ]; then
        local target=$(readlink "$ADC_PATH")
        if grep -q '"type": "service_account"' "$ADC_PATH" 2>/dev/null; then
            echo "never (service account)"
            return
        fi
    fi

    # For user credentials, check expiry
    local expiry=$(jq -r '.expiry // empty' "$ADC_PATH" 2>/dev/null)
    if [ -z "$expiry" ]; then
        # Try to get from token info
        local token=$(jq -r '.access_token // empty' "$ADC_PATH" 2>/dev/null)
        if [ -n "$token" ]; then
            # Token exists but no expiry info - might be service account
            if grep -q '"type": "service_account"' "$ADC_PATH" 2>/dev/null; then
                echo "never (service account)"
            else
                echo "unknown"
            fi
        else
            echo "no token"
        fi
        return
    fi

    echo "$expiry"
}

get_adc_remaining() {
    local expiry="$1"

    if [ -z "$expiry" ] || [ "$expiry" = "unknown" ] || [ "$expiry" = "no token" ]; then
        echo ""
        return
    fi

    if [[ "$expiry" == *"service account"* ]] || [[ "$expiry" == *"never"* ]]; then
        echo ""
        return
    fi

    # Parse expiry time
    local expiry_ts=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$expiry" "+%s" 2>/dev/null || \
                      date -j -f "%Y-%m-%dT%H:%M:%S" "${expiry%.*}" "+%s" 2>/dev/null)

    if [ -z "$expiry_ts" ]; then
        echo ""
        return
    fi

    local now_ts=$(date "+%s")
    local diff=$((expiry_ts - now_ts))

    if [ $diff -lt 0 ]; then
        echo "EXPIRED"
    elif [ $diff -lt 60 ]; then
        echo "${diff}s"
    elif [ $diff -lt 3600 ]; then
        echo "$((diff / 60))m"
    else
        echo "$((diff / 3600))h $((diff % 3600 / 60))m"
    fi
}

show_adc_status() {
    echo ""
    echo -e "${BLUE}=== ADC Status ===${NC}"

    if [ ! -f "$ADC_PATH" ] && [ ! -L "$ADC_PATH" ]; then
        echo -e "${RED}No ADC configured${NC}"
        echo ""
        echo "Run 'gcx adc login' to set up ADC"
        echo ""
        return 1
    fi

    # Check if symlink
    if [ -L "$ADC_PATH" ]; then
        local target=$(readlink "$ADC_PATH")
        local target_name=$(basename "$target")
        echo -e "Source:  ${CYAN}${target_name}${NC} (symlink)"
    else
        echo -e "Source:  ${CYAN}user login${NC}"
    fi

    # Get credential type
    local cred_type=$(jq -r '.type // "authorized_user"' "$ADC_PATH" 2>/dev/null)
    echo -e "Type:    ${CYAN}${cred_type}${NC}"

    # Get account/client info
    if [ "$cred_type" = "service_account" ]; then
        local sa_email=$(jq -r '.client_email // "unknown"' "$ADC_PATH" 2>/dev/null)
        echo -e "Account: ${CYAN}${sa_email}${NC}"
        echo -e "Expiry:  ${GREEN}never (service account key)${NC}"
    else
        local client_id=$(jq -r '.client_id // "unknown"' "$ADC_PATH" 2>/dev/null)
        echo -e "Client:  ${CYAN}${client_id:0:20}...${NC}"

        # Check token expiry by actually testing it
        echo -e -n "Status:  "
        if check_adc_valid; then
            echo -e "${GREEN}valid${NC}"
        else
            echo -e "${RED}expired or invalid${NC}"
        fi
    fi

    echo ""

    # Show available credentials
    if [ -d "$CREDS_DIR" ]; then
        local creds=$(ls "$CREDS_DIR"/*.json 2>/dev/null | wc -l | tr -d ' ')
        if [ "$creds" -gt 0 ]; then
            echo -e "${BLUE}Available credentials:${NC}"
            for f in "$CREDS_DIR"/*.json; do
                [ -f "$f" ] || continue
                local name=$(basename "$f")
                local type=$(jq -r '.type // "authorized_user"' "$f" 2>/dev/null)
                local icon="👤"
                [ "$type" = "service_account" ] && icon="🤖"

                # Check if this is the current one
                if [ -L "$ADC_PATH" ]; then
                    local current=$(readlink "$ADC_PATH" | xargs basename 2>/dev/null)
                    if [ "$name" = "$current" ]; then
                        echo -e "  ${icon} ${GREEN}${name}${NC} (current)"
                    else
                        echo "  ${icon} ${name}"
                    fi
                else
                    echo "  ${icon} ${name}"
                fi
            done
            echo ""
        fi
    fi
}

check_adc_valid() {
    # Try to get an access token to verify ADC is valid
    gcloud auth application-default print-access-token &>/dev/null
    return $?
}

# =============================================================================
# ADC Actions
# =============================================================================

adc_login() {
    echo -e "${BLUE}Refreshing ADC (user login)...${NC}"
    echo ""

    # Remove symlink if exists (we want fresh user creds)
    if [ -L "$ADC_PATH" ]; then
        echo -e "${YELLOW}Removing symlink to use fresh credentials${NC}"
        rm -f "$ADC_PATH"
    fi

    gcloud auth application-default login

    if [ $? -eq 0 ]; then
        echo ""
        echo -e "${GREEN}ADC refreshed successfully!${NC}"
        show_adc_status
    else
        echo ""
        echo -e "${RED}Failed to refresh ADC${NC}"
        return 1
    fi
}

adc_switch() {
    if [ ! -d "$CREDS_DIR" ]; then
        echo -e "${RED}No credentials directory found: ${CREDS_DIR}${NC}"
        echo "Save your credentials there first."
        return 1
    fi

    local creds=$(ls "$CREDS_DIR"/*.json 2>/dev/null)
    if [ -z "$creds" ]; then
        echo -e "${RED}No credentials found in ${CREDS_DIR}${NC}"
        return 1
    fi

    # Build selection list
    local options=""
    for f in "$CREDS_DIR"/*.json; do
        [ -f "$f" ] || continue
        local name=$(basename "$f")
        local type=$(jq -r '.type // "authorized_user"' "$f" 2>/dev/null)
        local icon="👤"
        [ "$type" = "service_account" ] && icon="🤖"

        local email=""
        if [ "$type" = "service_account" ]; then
            email=$(jq -r '.client_email // ""' "$f" 2>/dev/null)
        fi

        if [ -n "$email" ]; then
            options="${options}${icon} ${name} (${email})\n"
        else
            options="${options}${icon} ${name}\n"
        fi
    done
    options="${options}🔄 Fresh login (gcloud auth application-default login)"

    local choice=$(echo -e "$options" | gum choose --header="Select ADC credential:" --header.foreground="4")

    if [ -z "$choice" ]; then
        echo "Cancelled."
        return 0
    fi

    if [[ "$choice" == *"Fresh login"* ]]; then
        adc_login
        return $?
    fi

    # Extract filename from choice
    local selected=$(echo "$choice" | sed 's/^[^ ]* //' | cut -d' ' -f1)
    local cred_path="$CREDS_DIR/$selected"

    if [ ! -f "$cred_path" ]; then
        echo -e "${RED}Credential file not found: ${cred_path}${NC}"
        return 1
    fi

    # Create symlink
    rm -f "$ADC_PATH"
    ln -s "$cred_path" "$ADC_PATH"

    echo -e "${GREEN}Switched ADC to: ${selected}${NC}"
    echo ""
    show_adc_status
}

adc_save() {
    local name="${1:-}"

    if [ ! -f "$ADC_PATH" ]; then
        echo -e "${RED}No ADC to save. Run 'gcx adc login' first.${NC}"
        return 1
    fi

    if [ -L "$ADC_PATH" ]; then
        echo -e "${YELLOW}Current ADC is a symlink, nothing to save.${NC}"
        return 1
    fi

    if [ -z "$name" ]; then
        name=$(gum input --placeholder "Save as (e.g., adc-myproject.json)")
    fi

    if [ -z "$name" ]; then
        echo "Cancelled."
        return 0
    fi

    # Ensure .json extension
    [[ "$name" != *.json ]] && name="${name}.json"

    mkdir -p "$CREDS_DIR"
    cp "$ADC_PATH" "$CREDS_DIR/$name"

    echo -e "${GREEN}Saved ADC to: ${CREDS_DIR}/${name}${NC}"

    # Offer to symlink
    if gum confirm "Switch to using this saved credential (symlink)?"; then
        rm -f "$ADC_PATH"
        ln -s "$CREDS_DIR/$name" "$ADC_PATH"
        echo -e "${GREEN}Now using symlink to: ${name}${NC}"
    fi
}

show_adc_help() {
    cat << EOF
gcx adc - ADC (Application Default Credentials) management

Usage: gcx adc [command]

Commands:
  (no args)     Show ADC status
  login, l      Fresh login (gcloud auth application-default login)
  switch, s     Switch between saved credentials
  save [name]   Save current ADC to credentials directory
  help          Show this help

Examples:
  gcx adc                   Show current ADC status
  gcx adc login             Refresh ADC with fresh login
  gcx adc switch            Switch to a saved credential
  gcx adc save myproject    Save current ADC as myproject.json

Credentials are stored in: ~/.config/gcloud-creds/
EOF
}

# =============================================================================
# Main
# =============================================================================

adc_main() {
    case "${1:-}" in
        login|l|refresh|r)
            adc_login
            ;;
        switch|s)
            adc_switch
            ;;
        save)
            adc_save "$2"
            ;;
        help|--help|-h)
            show_adc_help
            ;;
        "")
            show_adc_status
            ;;
        *)
            echo -e "${RED}Unknown command: $1${NC}"
            echo "Run 'gcx adc help' for usage."
            exit 1
            ;;
    esac
}
