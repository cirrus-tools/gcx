#!/bin/bash

# release.sh - Release gcx to GitHub
# Usage: ./scripts/release.sh [version]
# Example: ./scripts/release.sh 1.1.0

set -e

cd "$(dirname "$0")/.."

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Get current version
CURRENT_VERSION=$(grep '^VERSION=' bin/gcx.sh | cut -d'"' -f2)
echo -e "${BLUE}Current version: ${CURRENT_VERSION}${NC}"

# Get new version
NEW_VERSION="${1:-}"
if [ -z "$NEW_VERSION" ]; then
    read -p "New version: " NEW_VERSION
fi

if [ -z "$NEW_VERSION" ]; then
    echo -e "${RED}Version is required${NC}"
    exit 1
fi

# Validate version format
if ! [[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "${RED}Invalid version format. Use: X.Y.Z${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}Will release: v${NEW_VERSION}${NC}"
echo ""

# Check for uncommitted changes
if ! git diff --quiet || ! git diff --cached --quiet; then
    echo -e "${YELLOW}Warning: You have uncommitted changes${NC}"
    git status --short
    echo ""
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
fi

# Update version in gcx.sh
echo -e "${BLUE}Updating bin/gcx.sh...${NC}"
sed -i '' "s/^VERSION=\".*\"/VERSION=\"${NEW_VERSION}\"/" bin/gcx.sh

# Update CHANGELOG
if [ -f "CHANGELOG.md" ]; then
    echo -e "${BLUE}Updating CHANGELOG.md...${NC}"
    TODAY=$(date +%Y-%m-%d)

    # Replace [Unreleased] with new version section
    sed -i '' "s/^## \[Unreleased\]$/## [Unreleased]\n\n## [${NEW_VERSION}] - ${TODAY}/" CHANGELOG.md

    # Update links at bottom
    sed -i '' "s|\[Unreleased\]: \(.*\)/compare/v.*\.\.\.HEAD|[Unreleased]: \1/compare/v${NEW_VERSION}...HEAD|" CHANGELOG.md

    # Add new version link (before the first version link)
    if ! grep -q "\[${NEW_VERSION}\]:" CHANGELOG.md; then
        sed -i '' "/^\[Unreleased\]:.*$/a\\
[${NEW_VERSION}]: https://github.com/cirrus-tools/gcx/compare/v${CURRENT_VERSION}...v${NEW_VERSION}
" CHANGELOG.md
    fi
fi

# Commit
echo -e "${BLUE}Committing changes...${NC}"
git add bin/gcx.sh CHANGELOG.md
git commit -m "chore: release v${NEW_VERSION}"

# Tag
echo -e "${BLUE}Creating tag v${NEW_VERSION}...${NC}"
git tag -a "v${NEW_VERSION}" -m "Release v${NEW_VERSION}"

# Push
echo -e "${BLUE}Pushing to origin...${NC}"
git push origin main
git push origin "v${NEW_VERSION}"

echo ""
echo -e "${GREEN}Released v${NEW_VERSION}${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Wait a few seconds for GitHub to create the tarball"
echo "  2. Run publish.sh in homebrew-tap to update the formula:"
echo ""
echo "     cd ../homebrew-tap"
echo "     ./scripts/publish.sh ${NEW_VERSION}"
echo ""
