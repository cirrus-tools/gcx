# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.3.0] - 2026-01-05

### Added
- **Service Account Authentication**: Add orgs using SA credentials instead of browser login
  - Select existing credentials file from `~/.config/gcloud-creds/`
  - Paste JSON content directly (auto-saves)
  - Enter custom file path
  - Auto-extract account email from `client_email`
  - Auto-set ADC to same credentials file
- **Kubeconfig Creation**: Create new kubeconfig during add-org flow
  - Lists GKE clusters in current project
  - Auto-fetch credentials with `gcloud container clusters get-credentials`
  - Shows save location (`~/.kube/config-{name}`)

### Improved
- **Streamlined Add Org Flow**: Removed redundant prompts
  - Uses gcloud config name as org_id (no separate prompt)
  - Skips project selection when creating new config (already selected)
- **Better Ctrl+C Handling**: Pressing cancel now properly exits the script
- **Clear Input Labels**: Changed from placeholder text to header labels

## [1.2.4] - 2026-01-01

### Improved
- **Setup Wizard**: Significant UX improvements for `gcx setup`
  - Added interaction cancellation support
  - Auto-detection of gcloud account email
  - Integrated ADC login flow for new setups
  - Better handling of missing credentials and kubeconfigs
- **Auto-Activation**: Automatically links ADC credentials after setup

### Fixed
- Fix `add_identity` error when no organizations exist

## [1.2.3] - 2026-01-01

### Fixed
- Fix `gcx setup` failing on first run when config directory doesn't exist
- Fix yq syntax error when adding organizations/identities with dynamic names
- Fix gum choose failing when no kubeconfig or ADC credential files exist

## [1.2.2] - 2026-01-01

### Improved
- Use gum spinner for loading states (vm, run)
- Enhanced VM list with search filter and status icons
- Improved VM details view with formatted output
- Better error messages when API not enabled or permission denied

## [1.2.1] - 2026-01-01

### Fixed
- Fix lib path for homebrew installation (lib/gcx/ subdirectory)

## [1.2.0] - 2026-01-01

### Added
- `gcx vm` - VM instance management (list, SSH, start/stop)
- `gcx run` - Cloud Run service management (list, logs, open URL)

## [1.1.0] - 2026-01-01

### Added
- `gcx adc` - ADC (Application Default Credentials) management
- `gcx --version` flag
- `scripts/release.sh` for automated release flow
- Shell completion for bash and zsh

## [1.0.0] - 2026-01-01

### Added
- Initial release
- `gcx` - Interactive context switching
- `gcx <org>` - Direct organization switch
- `gcx status` - Show current context
- `gcx project` - Quick project switch
- `gcx setup` - Setup wizard
- Multi-organization, multi-identity support
- Config export/import for team sharing

[Unreleased]: https://github.com/cirrus-tools/gcx/compare/v1.3.0...HEAD
[1.3.0]: https://github.com/cirrus-tools/gcx/compare/v1.2.4...v1.3.0
[1.2.4]: https://github.com/cirrus-tools/gcx/compare/v1.2.3...v1.2.4
[1.2.3]: https://github.com/cirrus-tools/gcx/compare/v1.2.2...v1.2.3
[1.2.2]: https://github.com/cirrus-tools/gcx/compare/v1.2.1...v1.2.2
[1.2.1]: https://github.com/cirrus-tools/gcx/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/cirrus-tools/gcx/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/cirrus-tools/gcx/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/cirrus-tools/gcx/releases/tag/v1.0.0
