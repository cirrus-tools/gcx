# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/cirrus-tools/gcx/compare/v1.2.2...HEAD
[1.2.2]: https://github.com/cirrus-tools/gcx/compare/v1.2.1...v1.2.2
[1.2.1]: https://github.com/cirrus-tools/gcx/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/cirrus-tools/gcx/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/cirrus-tools/gcx/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/cirrus-tools/gcx/releases/tag/v1.0.0
