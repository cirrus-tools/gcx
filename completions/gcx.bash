# gcx bash completion

_gcx_completions() {
    local cur prev words cword
    _init_completion || return

    local commands="status s project p adc setup version help"
    local adc_commands="login l switch s save help"
    local setup_commands="init add-org add-id export import list show edit deps help"

    # Get organizations from config
    local config_file="$HOME/.config/gcx/config.yaml"
    local orgs=""
    if [ -f "$config_file" ] && command -v yq &>/dev/null; then
        orgs=$(yq '.organizations | keys | .[]' "$config_file" 2>/dev/null | tr '\n' ' ')
    fi

    case "${prev}" in
        gcx)
            COMPREPLY=($(compgen -W "${commands} ${orgs}" -- "${cur}"))
            return
            ;;
        adc)
            COMPREPLY=($(compgen -W "${adc_commands}" -- "${cur}"))
            return
            ;;
        setup)
            COMPREPLY=($(compgen -W "${setup_commands}" -- "${cur}"))
            return
            ;;
    esac

    # Handle second level (gcx <org> <identity>)
    if [ "${#words[@]}" -eq 3 ]; then
        local org="${words[1]}"
        if [ -f "$config_file" ] && command -v yq &>/dev/null; then
            local identities=$(yq ".organizations.${org}.identities | keys | .[]" "$config_file" 2>/dev/null | tr '\n' ' ')
            if [ -n "$identities" ]; then
                COMPREPLY=($(compgen -W "${identities}" -- "${cur}"))
                return
            fi
        fi
    fi

    COMPREPLY=($(compgen -W "${commands} ${orgs}" -- "${cur}"))
}

complete -F _gcx_completions gcx
