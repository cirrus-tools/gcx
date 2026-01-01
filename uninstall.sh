#!/bin/bash

# gcx uninstaller

PREFIX="${PREFIX:-/usr/local}"
BINDIR="${BINDIR:-$PREFIX/bin}"
LIBDIR="${LIBDIR:-$PREFIX/lib/gcx}"

echo "Uninstalling gcx..."

rm -f "$BINDIR/gcx"
rm -rf "$LIBDIR"

echo "✓ Uninstalled successfully!"
echo ""
echo "Note: Config file at ~/.config/gcx/ was not removed."
