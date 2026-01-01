#!/bin/bash

# gcx-setup.sh
# Setup and configuration tool for gcx
# This file is sourced by gcx when running 'gcx setup'

# set -e disabled - gcloud commands may return non-zero on warnings

# Handle Ctrl+C properly
trap 'echo ""; echo "Cancelled."; exit 130' INT

CONFIG_DIR="$HOME/.config/gcx"
CONFIG_FILE="$CONFIG_DIR/config.yaml"
CREDS_DIR="$HOME/.config/gcloud-creds"
KUBECONFIG_DIR="$HOME/.kube"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# =============================================================================
# Dependency Management
# =============================================================================

check_deps() {
    local missing=()
    
    command -v yq &>/dev/null || missing+=("yq")
    command -v gum &>/dev/null || missing+=("gum")
    command -v gcloud &>/dev/null || missing+=("google-cloud-sdk")
    command -v kubectl &>/dev/null || missing+=("kubectl")
    
    if [ ${#missing[@]} -eq 0 ]; then
        return 0
    fi
    
    echo -e "${YELLOW}Missing dependencies: ${missing[*]}${NC}"
    echo ""
    
    # Check if gum is available for interactive prompt
    if command -v gum &>/dev/null; then
        if gum confirm "Install missing dependencies via Homebrew?"; then
            install_deps "${missing[@]}"
        else
            echo -e "${RED}Cannot proceed without dependencies.${NC}"
            exit 1
        fi
    else
        echo "gum is not installed. Install dependencies manually:"
        echo "  brew install ${missing[*]}"
        echo ""
        read -p "Install now? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            install_deps "${missing[@]}"
        else
            echo -e "${RED}Cannot proceed without dependencies.${NC}"
            exit 1
        fi
    fi
}

install_deps() {
    local deps=("$@")
    
    # Check for Homebrew
    if ! command -v brew &>/dev/null; then
        echo -e "${RED}Homebrew not found. Please install Homebrew first:${NC}"
        echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
        exit 1
    fi
    
    echo -e "${BLUE}Installing: ${deps[*]}${NC}"
    brew install "${deps[@]}"
    echo -e "${GREEN}Dependencies installed successfully!${NC}"
}

# =============================================================================
# Environment Detection
# =============================================================================

detect_environment() {
    # Check if gcloud is authenticated
    local active_account=$(gcloud auth list --filter="status:ACTIVE" --format="value(account)" 2>/dev/null | head -n1)
    
    if [ -z "$active_account" ]; then
        echo "new_user"
        return
    fi
    
    # Count configurations
    local configs=$(gcloud config configurations list --format="value(name)" 2>/dev/null)
    local config_count=$(echo "$configs" | grep -c "." || echo "0")
    
    # Check if only default exists
    if [ "$config_count" -eq 1 ] && [ "$configs" = "default" ]; then
        echo "default_only"
        return
    fi
    
    echo "existing"
}

show_environment_status() {
    echo -e "${BLUE}🔍 Detecting environment...${NC}"
    echo ""
    
    # Check dependencies
    local deps_ok=true
    for dep in gcloud kubectl yq gum; do
        if command -v $dep &>/dev/null; then
            echo -e "${GREEN}✓${NC} $dep installed"
        else
            echo -e "${RED}✗${NC} $dep not found"
            deps_ok=false
        fi
    done
    echo ""
    
    if [ "$deps_ok" = false ]; then
        return 1
    fi
    
    # Check gcloud auth
    local active_account=$(gcloud auth list --filter="status:ACTIVE" --format="value(account)" 2>/dev/null | head -n1)
    if [ -n "$active_account" ]; then
        echo -e "${GREEN}✓${NC} Logged in as: $active_account"
    else
        echo -e "${YELLOW}⚠${NC} No active gcloud authentication"
    fi
    
    # Check configurations
    local configs=$(gcloud config configurations list --format="value(name)" 2>/dev/null | tr '\n' ' ')
    echo -e "${GREEN}✓${NC} gcloud configs: ${configs:-none}"
    
    # Check ctx-switch config
    if [ -f "$CONFIG_FILE" ]; then
        local orgs=$(yq '.organizations // {} | keys | .[]' "$CONFIG_FILE" 2>/dev/null | tr '\n' ' ')
        echo -e "${GREEN}✓${NC} ctx-switch orgs: $orgs"
    else
        echo -e "${YELLOW}⚠${NC} No ctx-switch config found"
    fi
    
    echo ""
}

# =============================================================================
# Scenario 1: New User (No gcloud auth)
# =============================================================================

setup_first_time() {
    echo -e "${BLUE}👋 Welcome to ctx-switch!${NC}"
    echo ""
    echo "Let's set up your first Google Cloud configuration."
    echo ""
    
    # Get configuration name
    local config_name=$(gum input --placeholder "Configuration name (e.g., mycompany)")
    
    if [ -z "$config_name" ]; then
        echo -e "${RED}Configuration name is required${NC}"
        return 1
    fi
    
    echo ""
    echo -e "${BLUE}Creating configuration '$config_name'...${NC}"
    
    # Create configuration
    gcloud config configurations create "$config_name" 2>/dev/null || true
    gcloud config configurations activate "$config_name" 2>/dev/null
    
    # Login
    echo ""
    echo -e "${BLUE}Opening browser for Google login...${NC}"
    gcloud auth login
    
    # Get account
    local account=$(gcloud auth list --filter="status:ACTIVE" --format="value(account)" 2>/dev/null | head -n1)
    echo -e "${GREEN}✓${NC} Logged in as: $account"
    
    # Select project
    echo ""
    echo -e "${BLUE}Loading projects...${NC}"
    local projects=$(gcloud projects list --format="value(projectId)" 2>/dev/null)
    
    if [ -n "$projects" ]; then
        local project=$(echo "$projects" | gum choose --header "Select default project:")
        if [ -n "$project" ]; then
            gcloud config set project "$project"
            echo -e "${GREEN}✓${NC} Project set to: $project"
        fi
    fi
    
    # Generate ADC
    echo ""
    if gum confirm "Generate Application Default Credentials?"; then
        gcloud auth application-default login
        
        # Save ADC
        mkdir -p "$CREDS_DIR"
        if [ -f "$HOME/.config/gcloud/application_default_credentials.json" ]; then
            cp "$HOME/.config/gcloud/application_default_credentials.json" "$CREDS_DIR/adc-${config_name}.json"
            echo -e "${GREEN}✓${NC} ADC saved to: adc-${config_name}.json"
        fi
    fi
    
    echo ""
    echo -e "${GREEN}✓ Configuration '$config_name' is ready!${NC}"
    echo ""
    
    # Continue to ctx-switch setup
    if gum confirm "Continue to set up ctx-switch?"; then
        init_from_current
    fi
}

# =============================================================================
# Scenario 2: Default Only Configuration
# =============================================================================

setup_from_default() {
    echo -e "${BLUE}📋 Current gcloud setup:${NC}"
    local account=$(gcloud config get-value account 2>/dev/null)
    local project=$(gcloud config get-value project 2>/dev/null)
    echo "   • default ($account)"
    echo "   • project: $project"
    echo ""
    
    echo "For multi-organization switching, we recommend separate configurations."
    echo ""
    
    local choice=$(echo -e "Create a new configuration (recommended)\nKeep using 'default' only" | gum choose --header "What would you like to do?")
    
    case "$choice" in
        "Create a new configuration"*)
            create_config_from_default
            ;;
        "Keep using 'default' only")
            echo ""
            echo "Continuing with 'default' configuration..."
            init_from_current
            ;;
    esac
}

create_config_from_default() {
    echo ""
    local new_name=$(gum input --placeholder "New configuration name (e.g., mycompany)")
    
    if [ -z "$new_name" ]; then
        echo -e "${RED}Configuration name is required${NC}"
        return 1
    fi
    
    # Get current settings
    local account=$(gcloud config get-value account 2>/dev/null)
    local project=$(gcloud config get-value project 2>/dev/null)
    
    # Create new configuration
    echo -e "${BLUE}Creating configuration '$new_name'...${NC}"
    gcloud config configurations create "$new_name" 2>/dev/null || true
    
    if gum confirm "Copy account and project from 'default'?"; then
        gcloud config configurations activate "$new_name" 2>/dev/null
        gcloud config set account "$account" 2>/dev/null
        gcloud config set project "$project" 2>/dev/null
        echo -e "${GREEN}✓${NC} Copied settings to '$new_name'"
    fi
    
    # Offer to rename default
    echo ""
    if gum confirm "Rename 'default' to something meaningful?"; then
        local new_default_name=$(gum input --placeholder "New name for 'default' (e.g., personal)")
        if [ -n "$new_default_name" ]; then
            gcloud config configurations activate default 2>/dev/null
            gcloud config configurations rename default --new-name="$new_default_name" 2>/dev/null
            echo -e "${GREEN}✓${NC} Renamed 'default' → '$new_default_name'"
        fi
    fi
    
    echo ""
    echo -e "${GREEN}✓ Configurations ready!${NC}"
    gcloud config configurations list --format="table(name,is_active,properties.core.account)"
    echo ""
    
    # Continue to ctx-switch setup
    if gum confirm "Continue to set up ctx-switch?"; then
        init_from_current
    fi
}

# =============================================================================
# Scenario 3: Existing User - Smart Menu
# =============================================================================

smart_menu() {
    show_environment_status
    
    local OPTIONS="🆕 First-time setup (guided)
➕ Add new organization
👤 Add identity to existing org
📥 Import from template
📤 Export template for sharing
📋 Show current config
✏️  Edit config file
🔄 Reconfigure from scratch
🔧 Check dependencies"

    local action=$(echo "$OPTIONS" | gum choose --header "What would you like to do?" --header.foreground="4")
    
    case "$action" in
        *"First-time setup"*)
            init_from_current
            ;;
        *"Add new organization"*)
            add_org_smart
            ;;
        *"Add identity"*)
            add_identity
            ;;
        *"Import from template"*)
            local file=$(gum input --placeholder "Path to template file")
            import_config "$file"
            ;;
        *"Export template"*)
            export_config
            ;;
        *"Show current config"*)
            show_config
            ;;
        *"Edit config"*)
            edit_config
            ;;
        *"Reconfigure"*)
            init_config --from-current
            ;;
        *"Check dependencies"*)
            check_deps
            echo -e "${GREEN}All dependencies are installed!${NC}"
            ;;
    esac
}

add_org_smart() {
    check_config_exists
    
    echo -e "${BLUE}Add new organization${NC}"
    echo ""
    
    # Ask if they need a new gcloud config
    local gcloud_configs=$(gcloud config configurations list --format="value(name)" 2>/dev/null)
    
    local config_choice=$(echo -e "Use existing gcloud configuration\nCreate new gcloud configuration" | gum choose --header "gcloud configuration:")
    
    local gcloud_config=""
    
    if [[ "$config_choice" == *"Create new"* ]]; then
        gcloud_config=$(create_new_gcloud_config)
    else
        gcloud_config=$(echo "$gcloud_configs" | gum choose --header "Select gcloud configuration")
    fi
    
    if [ -z "$gcloud_config" ]; then
        echo -e "${RED}No configuration selected${NC}"
        return 1
    fi
    
    # Now continue with normal add_org flow
    local org_name=$(gum input --placeholder "Organization ID (lowercase, no spaces)")
    local display_name=$(gum input --placeholder "Display name" --value "$org_name")
    
    # Get kubeconfig
    local kubeconfigs=$(ls "$KUBECONFIG_DIR"/config-* 2>/dev/null | xargs -n1 basename || echo "none")
    local kubeconfig=$(echo -e "$kubeconfigs\n(none)" | gum choose --header "Select kubeconfig")
    [ "$kubeconfig" = "(none)" ] && kubeconfig=""
    
    # Get account
    local account=$(gum input --placeholder "Account email")
    
    # Get ADC
    local adc_files=$(ls "$CREDS_DIR"/*.json 2>/dev/null | xargs -n1 basename || echo "none")
    local adc=$(echo -e "$adc_files\n(none)" | gum choose --header "Select ADC credential")
    [ "$adc" = "(none)" ] && adc=""
    
    # Get project
    echo -e "${BLUE}Loading projects...${NC}"
    local projects=$(gcloud projects list --format="value(projectId)" 2>/dev/null)
    local project=$(echo -e "$projects\n(skip)" | gum choose --header "Select default project")
    [ "$project" = "(skip)" ] && project=""
    
    # Select color
    local color=$(echo -e "green\nmagenta\ncyan\nyellow\nblue\nred" | gum choose --header "Select display color")
    
    # Add to config using yq
    yq -i ".organizations.[\"$org_name\"] = {
        \"display_name\": \"$display_name\",
        \"color\": \"$color\",
        \"gcloud_config\": \"$gcloud_config\",
        \"kubeconfig\": \"$kubeconfig\",
        \"identities\": {
            \"default\": {
                \"name\": \"User\",
                \"account\": \"$account\",
                \"adc\": \"$adc\",
                \"project\": \"$project\"
            }
        }
    }" "$CONFIG_FILE"
    
    echo ""
    echo -e "${GREEN}✓${NC} Added organization: $org_name"
}

create_new_gcloud_config() {
    local config_name=$(gum input --placeholder "New configuration name")
    
    if [ -z "$config_name" ]; then
        return 1
    fi
    
    echo -e "${BLUE}Creating configuration '$config_name'...${NC}"
    gcloud config configurations create "$config_name" 2>/dev/null || true
    gcloud config configurations activate "$config_name" 2>/dev/null
    
    echo -e "${BLUE}Opening browser for login...${NC}"
    gcloud auth login
    
    # Select project
    echo -e "${BLUE}Loading projects...${NC}"
    local projects=$(gcloud projects list --format="value(projectId)" 2>/dev/null)
    if [ -n "$projects" ]; then
        local project=$(echo "$projects" | gum choose --header "Select project:")
        if [ -n "$project" ]; then
            gcloud config set project "$project"
        fi
    fi
    
    echo -e "${GREEN}✓${NC} Configuration '$config_name' created"
    echo "$config_name"
}

# =============================================================================
# Config Management
# =============================================================================

init_config() {
    local from_current=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --from-current)
                from_current=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
    
    # Create config directory
    mkdir -p "$CONFIG_DIR"
    
    if [ -f "$CONFIG_FILE" ]; then
        echo -e "${YELLOW}Config file already exists: $CONFIG_FILE${NC}"
        if command -v gum &>/dev/null; then
            if ! gum confirm "Overwrite existing config?"; then
                echo "Aborted."
                exit 0
            fi
        else
            read -p "Overwrite? (y/n) " -n 1 -r
            echo
            [[ ! $REPLY =~ ^[Yy]$ ]] && exit 0
        fi
    fi
    
    if [ "$from_current" = true ]; then
        init_from_current
    else
        init_interactive
    fi
}

init_from_current() {
    # Ensure config directory exists
    mkdir -p "$CONFIG_DIR"
    
    echo -e "${BLUE}Detecting current configuration...${NC}"
    echo ""
    
    # Detect gcloud configurations
    local gcloud_configs=$(gcloud config configurations list --format="value(name)" 2>/dev/null)
    echo -e "${GREEN}✓${NC} Found gcloud configs: $(echo $gcloud_configs | tr '\n' ' ')"
    
    # Detect kubeconfigs
    local kubeconfigs=$(ls "$KUBECONFIG_DIR"/config-* 2>/dev/null | xargs -n1 basename || echo "")
    if [ -n "$kubeconfigs" ]; then
        echo -e "${GREEN}✓${NC} Found kubeconfigs: $(echo $kubeconfigs | tr '\n' ' ')"
    else
        echo -e "${YELLOW}⚠${NC} No kubeconfigs found"
    fi
    
    # Detect credentials
    local creds=$(ls "$CREDS_DIR"/*.json 2>/dev/null | xargs -n1 basename || echo "")
    if [ -n "$creds" ]; then
        echo -e "${GREEN}✓${NC} Found credentials: $(echo $creds | tr '\n' ' ')"
    else
        echo -e "${YELLOW}⚠${NC} No ADC credentials found"
    fi
    
    echo ""
    echo -e "${YELLOW}Now let's configure your organizations...${NC}"
    echo ""
    
    # Start config file
    cat > "$CONFIG_FILE" << 'EOF'
# ctx-switch configuration
# Generated from current system settings

version: 1
EOF

    # Set up one organization (simplified UX)
    local org_count=1
    
    for ((i=1; i<=org_count; i++)); do
        echo ""
        echo -e "${BLUE}--- Organization Setup ---${NC}"
        
        local org_id
        org_id=$(gum input --header "Organization ID:" --placeholder "lowercase, e.g., mycompany")
        if [ $? -ne 0 ] || [ -z "$org_id" ]; then echo "Cancelled."; return 1; fi
        
        local display_name
        display_name=$(gum input --header "Display Name:" --placeholder "Human readable name" --value "$org_id")
        if [ $? -ne 0 ]; then echo "Cancelled."; return 1; fi
        [ -z "$display_name" ] && display_name="$org_id"
        
        local color
        color=$(echo -e "green\nmagenta\ncyan\nyellow\nblue\nred" | gum choose --header "Select color:")
        if [ $? -ne 0 ]; then echo "Cancelled."; return 1; fi
        
        local gcloud_config
        gcloud_config=$(echo "$gcloud_configs" | gum choose --header "Select gcloud configuration:")
        if [ $? -ne 0 ]; then echo "Cancelled."; return 1; fi
        
        # Handle kubeconfig selection - skip if none available
        local kubeconfig=""
        if [ -n "$kubeconfigs" ]; then
            kubeconfig=$(echo -e "$kubeconfigs\n(none)" | gum choose --header "Select kubeconfig:")
            if [ $? -ne 0 ]; then echo "Cancelled."; return 1; fi
            [ "$kubeconfig" = "(none)" ] && kubeconfig=""
        fi
        
        # Set as default if first org
        if [ $i -eq 1 ]; then
            yq -i ".default_org = \"$org_id\"" "$CONFIG_FILE"
        fi
        
        # Add organization structure
        yq -i ".organizations.[\"$org_id\"] = {
            \"display_name\": \"$display_name\",
            \"color\": \"$color\",
            \"gcloud_config\": \"$gcloud_config\",
            \"kubeconfig\": \"$kubeconfig\",
            \"identities\": {}
        }" "$CONFIG_FILE"
        
        # Ask about identities
        local add_more="yes"
        local id_num=1
        while [ "$add_more" = "yes" ]; do
            echo ""
            echo -e "${BLUE}Identity $id_num for $display_name${NC}"
            
            local id_key
            id_key=$(gum input --header "Identity Key:" --placeholder "e.g., user, sa, admin" --value "$([ $id_num -eq 1 ] && echo 'user' || echo '')")
            if [ $? -ne 0 ] || [ -z "$id_key" ]; then echo "Cancelled."; return 1; fi
            
            local id_name
            id_name=$(gum input --header "Identity Display Name:" --placeholder "e.g., User, Service Account" --value "User")
            if [ $? -ne 0 ]; then echo "Cancelled."; return 1; fi
            [ -z "$id_name" ] && id_name="$id_key"
            
            # Get account email from selected gcloud config as default
            local default_account=""
            if [ -n "$gcloud_config" ]; then
                default_account=$(gcloud config configurations describe "$gcloud_config" --format="value(properties.core.account)" 2>/dev/null)
            fi
            
            local account
            account=$(gum input --header "Account Email:" --placeholder "e.g., you@company.com" --value "$default_account")
            if [ $? -ne 0 ]; then echo "Cancelled."; return 1; fi
            
            local adc=""
            if [ -n "$creds" ]; then
                # Credentials exist, let user choose
                adc=$(echo -e "$creds\n(none)" | gum choose --header "Select ADC credential file:")
                if [ $? -ne 0 ]; then echo "Cancelled."; return 1; fi
                [ "$adc" = "(none)" ] && adc=""
            else
                # No credentials found, offer to set up
                echo -e "${YELLOW}No ADC credentials found.${NC}"
                local adc_action
                adc_action=$(echo -e "🔐 Login now (gcloud auth application-default login)\n⏭️  Skip for now" | gum choose --header "Set up Application Default Credentials?")
                if [ $? -ne 0 ]; then echo "Cancelled."; return 1; fi
                
                if [[ "$adc_action" == *"Login now"* ]]; then
                    echo -e "${BLUE}Opening browser for ADC login...${NC}"
                    gcloud auth application-default login
                    
                    if [ -f "$HOME/.config/gcloud/application_default_credentials.json" ]; then
                        # Ask for a name to save it
                        local adc_name
                        adc_name=$(gum input --header "Save ADC as:" --placeholder "e.g., adc-${org_id}.json" --value "adc-${org_id}.json")
                        if [ $? -ne 0 ]; then echo "Cancelled."; return 1; fi
                        
                        if [ -n "$adc_name" ]; then
                            mkdir -p "$CREDS_DIR"
                            cp "$HOME/.config/gcloud/application_default_credentials.json" "$CREDS_DIR/$adc_name"
                            adc="$adc_name"
                            echo -e "${GREEN}✓${NC} ADC saved to: $CREDS_DIR/$adc_name"
                            # Update creds list
                            creds=$(ls "$CREDS_DIR"/*.json 2>/dev/null | xargs -n1 basename || echo "")
                        fi
                    fi
                fi
            fi
            
            yq -i ".organizations.[\"$org_id\"].identities.[\"$id_key\"] = {
                \"name\": \"$id_name\",
                \"account\": \"$account\",
                \"adc\": \"$adc\"
            }" "$CONFIG_FILE"
            
            id_num=$((id_num + 1))
            
            if ! gum confirm "Add another identity?"; then
                add_more="no"
            fi
        done
    done
    
    echo ""
    echo -e "${GREEN}✓${NC} Config file created: $CONFIG_FILE"
    
    # Auto-activate: Create ADC symlink if adc was configured
    local default_org=$(yq '.default_org' "$CONFIG_FILE" 2>/dev/null)
    if [ -n "$default_org" ]; then
        local default_adc=$(yq ".organizations.[\"$default_org\"].identities.user.adc // \"\"" "$CONFIG_FILE" 2>/dev/null)
        if [ -n "$default_adc" ] && [ -f "$CREDS_DIR/$default_adc" ]; then
            rm -f "$ADC_PATH"
            ln -s "$CREDS_DIR/$default_adc" "$ADC_PATH"
            echo -e "${GREEN}✓${NC} ADC linked: $default_adc"
        fi
    fi
    
    echo ""
    echo "You can edit this file anytime with: gcx setup edit"
}

init_interactive() {
    echo -e "${BLUE}Interactive setup${NC}"
    echo ""
    
    # Get organization name
    local org_name=$(gum input --placeholder "Organization name (e.g., mycompany)")
    local display_name=$(gum input --placeholder "Display name (e.g., My Company)" --value "$org_name")
    
    # Get gcloud config
    local gcloud_configs=$(gcloud config configurations list --format="value(name)" 2>/dev/null)
    local gcloud_config=$(echo "$gcloud_configs" | gum choose --header "Select gcloud configuration")
    
    # Get kubeconfig
    local kubeconfigs=$(ls "$KUBECONFIG_DIR"/config-* 2>/dev/null | xargs -n1 basename || echo "none")
    local kubeconfig=$(echo "$kubeconfigs" | gum choose --header "Select kubeconfig")
    
    # Get account
    local account=$(gum input --placeholder "Account email (e.g., you@company.com)")
    
    # Get ADC file
    local adc_files=$(ls "$CREDS_DIR"/*.json 2>/dev/null | xargs -n1 basename || echo "none")
    local adc=$(echo "$adc_files" | gum choose --header "Select ADC credential file")
    
    # Select color
    local color=$(echo -e "green\nmagenta\ncyan\nyellow\nblue\nred" | gum choose --header "Select display color")
    
    # Generate config
    cat > "$CONFIG_FILE" << EOF
# ctx-switch configuration

version: 1
default_org: $org_name

organizations:
  $org_name:
    display_name: "$display_name"
    color: "$color"
    gcloud_config: "$gcloud_config"
    kubeconfig: "$kubeconfig"
    identities:
      default:
        name: "User"
        account: "$account"
        adc: "$adc"
EOF

    echo ""
    echo -e "${GREEN}✓${NC} Config file created: $CONFIG_FILE"
}

# =============================================================================
# Organization Management
# =============================================================================

add_org() {
    check_config_exists
    
    echo -e "${BLUE}Add new organization${NC}"
    echo ""
    
    local org_name=$(gum input --placeholder "Organization ID (lowercase, no spaces)")
    local display_name=$(gum input --placeholder "Display name" --value "$org_name")
    
    # Get gcloud config
    local gcloud_configs=$(gcloud config configurations list --format="value(name)" 2>/dev/null)
    local gcloud_config=$(echo "$gcloud_configs" | gum choose --header "Select gcloud configuration")
    
    # Get kubeconfig
    local kubeconfigs=$(ls "$KUBECONFIG_DIR"/config-* 2>/dev/null | xargs -n1 basename || echo "")
    local kubeconfig=""
    if [ -n "$kubeconfigs" ]; then
        kubeconfig=$(echo -e "$kubeconfigs\n(none)" | gum choose --header "Select kubeconfig")
        [ "$kubeconfig" = "(none)" ] && kubeconfig=""
    fi
    
    # Get account
    local account=$(gum input --placeholder "Account email")
    
    # Get ADC
    local adc_files=$(ls "$CREDS_DIR"/*.json 2>/dev/null | xargs -n1 basename || echo "")
    local adc=""
    if [ -n "$adc_files" ]; then
        adc=$(echo -e "$adc_files\n(none)" | gum choose --header "Select ADC credential")
        [ "$adc" = "(none)" ] && adc=""
    fi
    
    # Select color
    local color=$(echo -e "green\nmagenta\ncyan\nyellow\nblue\nred" | gum choose --header "Select display color")
    
    # Add to config using yq
    yq -i ".organizations.[\"$org_name\"] = {
        \"display_name\": \"$display_name\",
        \"color\": \"$color\",
        \"gcloud_config\": \"$gcloud_config\",
        \"kubeconfig\": \"$kubeconfig\",
        \"identities\": {
            \"default\": {
                \"name\": \"User\",
                \"account\": \"$account\",
                \"adc\": \"$adc\"
            }
        }
    }" "$CONFIG_FILE"
    
    echo ""
    echo -e "${GREEN}✓${NC} Added organization: $org_name"
}

add_identity() {
    check_config_exists
    
    local org="$1"
    
    if [ -z "$org" ]; then
        # Select organization
        local orgs=$(yq '.organizations // {} | keys | .[]' "$CONFIG_FILE" 2>/dev/null)
        if [ -z "$orgs" ]; then
            echo -e "${RED}No organizations found. Run 'gcx setup' first to add an organization.${NC}"
            return 1
        fi
        org=$(echo "$orgs" | gum choose --header "Select organization")
    fi
    
    echo -e "${BLUE}Add identity to $org${NC}"
    echo ""
    
    local id_key=$(gum input --placeholder "Identity key (e.g., user, sa, admin)")
    local id_name=$(gum input --placeholder "Display name (e.g., User, Service Account)")
    local account=$(gum input --placeholder "Account email")
    
    local adc_files=$(ls "$CREDS_DIR"/*.json 2>/dev/null | xargs -n1 basename || echo "")
    local adc=""
    if [ -n "$adc_files" ]; then
        adc=$(echo "$adc_files" | gum choose --header "Select ADC credential (or Ctrl+C to skip)" || echo "")
    fi
    
    yq -i ".organizations.[\"$org\"].identities.[\"$id_key\"] = {
        \"name\": \"$id_name\",
        \"account\": \"$account\",
        \"adc\": \"$adc\"
    }" "$CONFIG_FILE"
    
    echo ""
    echo -e "${GREEN}✓${NC} Added identity '$id_name' to $org"
}

# =============================================================================
# Export / Import
# =============================================================================

export_config() {
    check_config_exists
    
    echo -e "${BLUE}Exporting config template...${NC}"
    echo ""
    
    # Create a sanitized copy
    local template=$(yq 'del(.organizations[].identities[].account)' "$CONFIG_FILE")
    
    # Add placeholder comments
    cat << EOF
# ctx-switch configuration template
# Generated on $(date +%Y-%m-%d)
#
# Instructions:
# 1. Save this file
# 2. Run: ctx-switch-setup import <filename>
# 3. Fill in your account details

$template

# Note: Account emails have been removed for sharing.
# You'll need to fill in your own account details after import.
EOF
}

import_config() {
    local file="$1"
    
    if [ -z "$file" ]; then
        echo -e "${RED}Usage: ctx-switch-setup import <file>${NC}"
        exit 1
    fi
    
    if [ ! -f "$file" ]; then
        echo -e "${RED}File not found: $file${NC}"
        exit 1
    fi
    
    mkdir -p "$CONFIG_DIR"
    
    if [ -f "$CONFIG_FILE" ]; then
        echo -e "${YELLOW}Existing config will be backed up${NC}"
        cp "$CONFIG_FILE" "$CONFIG_FILE.bak"
    fi
    
    cp "$file" "$CONFIG_FILE"
    
    echo -e "${GREEN}✓${NC} Config imported: $CONFIG_FILE"
    echo ""
    echo "Now run 'ctx-switch-setup edit' to fill in your account details."
}

# =============================================================================
# Utilities
# =============================================================================

check_config_exists() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}Config file not found. Run 'ctx-switch-setup init' first.${NC}"
        exit 1
    fi
}

show_config() {
    check_config_exists
    
    echo -e "${BLUE}Current configuration:${NC}"
    echo ""
    cat "$CONFIG_FILE"
}

edit_config() {
    check_config_exists
    
    ${EDITOR:-vim} "$CONFIG_FILE"
}

show_help() {
    cat << EOF
ctx-switch-setup - Setup tool for ctx-switch

Usage: ctx-switch-setup <command> [options]

Commands:
  init [--from-current]   Initialize config (--from-current: detect existing settings)
  add-org                 Add a new organization
  add-id [org]            Add identity to an organization
  export                  Export config template (for sharing)
  import <file>           Import config from file
  list                    Show current configuration
  edit                    Edit config file in editor
  deps                    Check and install dependencies

Examples:
  ctx-switch-setup init --from-current
  ctx-switch-setup add-org
  ctx-switch-setup add-id <org>
  ctx-switch-setup export > template.yaml
  ctx-switch-setup import template.yaml
EOF
}

# =============================================================================
# Main
# =============================================================================

main() {
    case "${1:-}" in
        init)
            shift
            check_deps
            init_config "$@"
            ;;
        add-org)
            check_deps
            add_org
            ;;
        add-id)
            check_deps
            add_identity "$2"
            ;;
        export)
            export_config
            ;;
        import)
            import_config "$2"
            ;;
        list|show)
            show_config
            ;;
        edit)
            edit_config
            ;;
        deps)
            check_deps
            echo -e "${GREEN}All dependencies are installed!${NC}"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            # Smart interactive mode with environment detection
            check_deps
            
            local env_type=$(detect_environment)
            
            case "$env_type" in
                "new_user")
                    echo -e "${BLUE}🔍 Detecting environment...${NC}"
                    echo ""
                    echo -e "${YELLOW}⚠${NC} No Google Cloud authentication found."
                    echo ""
                    setup_first_time
                    ;;
                "default_only")
                    setup_from_default
                    ;;
                "existing")
                    smart_menu
                    ;;
            esac
            ;;
    esac
}

main "$@"
