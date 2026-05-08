#!/bin/bash
# generate_icons.sh - Generate app icons from ASCII art
#
# This script should be run in the mobile development environment:
#   nix develop .#mobile
#   cd mobile
#   ./assets/generate_icons.sh

set -e

echo "Generating ASCII art icon..."
python3 assets/generate_icon.py

echo ""
echo "Installing dependencies..."
flutter pub get

echo ""
echo "Generating launcher icons..."
flutter pub run flutter_launcher_icons

echo ""
echo "✓ App icons generated successfully!"
echo ""
echo "The new ASCII art radio logo has been applied to:"
echo "  - Android (mipmap resources)"
echo "  - iOS (Assets.xcassets)"
echo ""
