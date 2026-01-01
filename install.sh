#!/bin/bash

# gcx installer

PREFIX="${PREFIX:-/usr/local}"
BINDIR="${BINDIR:-$PREFIX/bin}"
LIBDIR="${LIBDIR:-$PREFIX/lib/gcx}"

echo "Installing gcx to $BINDIR..."

# Check dependencies
for dep in gcloud yq gum; do
    if ! command -v $dep &>/dev/null; then
        echo "Warning: $dep not found. Install with: brew install $dep"
    fi
done

# Install
install -d "$BINDIR"
install -d "$LIBDIR"
install -m 755 bin/gcx.sh "$BINDIR/gcx"
install -m 644 lib/gcx-setup.sh "$LIBDIR/gcx-setup.sh"

echo ""
echo "✓ Installed successfully!"
echo ""
echo "Run 'gcx setup' to configure."
