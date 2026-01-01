# gcx - GCloud Context Switcher

🔄 **Quick context switcher for Google Cloud Platform**

Switch between GCP organizations, accounts, projects, kubeconfig, and Application Default Credentials with a single command.

## Features

- 🏢 **Multi-organization support** - Switch between different GCP orgs
- 👤 **Multiple identities** - User accounts and service accounts per org
- 📁 **Project binding** - Each identity can have a default project
- ☸️ **Kubeconfig management** - Auto-switch kubeconfig per org
- 🔐 **ADC management** - Application Default Credentials switching
- 🎨 **Color-coded status** - Visual distinction per organization
- 🧙 **Smart setup** - Guided setup for new users

## Installation

### Homebrew (recommended)

```bash
brew tap cirrus-tools/tap
brew install gcx
```

### Manual

```bash
git clone https://github.com/cirrus-tools/gcx.git
cd gcx
./install.sh
```

## Quick Start

```bash
# First time setup
gcx setup

# Switch context
gcx                     # Interactive mode
gcx myorg               # Switch to org
gcx myorg sa            # Switch to org with specific identity

# Quick actions
gcx status              # Show current context  (or: gcx s)
gcx project             # Quick switch project  (or: gcx p)
gcx setup               # Run setup wizard
```

## Configuration

Config file: `~/.config/gcx/config.yaml`

```yaml
version: 1
default_org: mycompany

organizations:
  mycompany:
    display_name: "My Company"
    color: "green"
    gcloud_config: "mycompany"
    kubeconfig: "config-mycompany"
    identities:
      user:
        name: "User"
        account: "me@mycompany.com"
        adc: "adc-mycompany.json"
        project: "mycompany-prod"
      sa:
        name: "Service Account"
        account: "devops@mycompany.iam.gserviceaccount.com"
        adc: "devops-credentials.json"
        project: "mycompany-prod"
```

## Setup Commands

```bash
gcx setup               # Smart setup (detects your environment)
gcx setup init          # Initialize configuration
gcx setup add-org       # Add new organization
gcx setup add-id        # Add identity to org
gcx setup export        # Export template for sharing
gcx setup import FILE   # Import template
gcx setup edit          # Edit config file
```

## Team Sharing

```bash
# Export template (removes account emails)
gcx setup export > team-template.yaml

# Team member imports
gcx setup import team-template.yaml
gcx setup edit  # Fill in their accounts
```

## Dependencies

- [gcloud](https://cloud.google.com/sdk) - Google Cloud CLI
- [kubectl](https://kubernetes.io/docs/tasks/tools/) - Kubernetes CLI
- [yq](https://github.com/mikefarah/yq) - YAML processor
- [gum](https://github.com/charmbracelet/gum) - Interactive prompts

## Roadmap

- [ ] VM instance selector (`gcx vm`)
- [ ] Cloud SQL selector (`gcx sql`)
- [ ] Network/VPC selector (`gcx network`)
- [ ] GKE cluster selector (`gcx gke`)
- [ ] SSH config generation
- [ ] Shell completion (bash/zsh/fish)

## License

MIT
