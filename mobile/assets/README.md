# App Icon Assets

This directory contains the ASCII art logo and icon generation scripts for the am_radio Flutter app.

## Files

- `logo_design.txt` - ASCII art logo design documentation
- `generate_icon.py` - Python script to create PNG icon from ASCII art
- `resize_icons.py` - Python script to resize icons for Android densities
- `generate_icons.sh` - Shell script to regenerate all app icons
- `icon.png` - Main 512x512 icon (generated)
- `icon_1024.png` - iOS 1024x1024 icon (generated)

## Icon Design

The logo features a vintage radio with:
- Antenna (!) at top
- Radio body with dial (●─⊙─●)
- "A M" text for AM Radio
- Speaker grille pattern (≈≈≈≈≈)
- Vintage bakelite color scheme

Colors match the app's theme:
- Background: #1A0F00 (dark brown)
- Foreground: #E8A020 (amber)

## Regenerating Icons

After modifying the ASCII art in `generate_icon.py`, regenerate all app icons:

```bash
cd mobile
nix develop ..#mobile
./assets/generate_icons.sh
```

This will:
1. Generate icon.png and icon_1024.png from ASCII art
2. Run `flutter pub get` to install dependencies
3. Run `flutter_launcher_icons` to create platform-specific icons

## Manual Generation

If you prefer to generate icons manually:

```bash
# Generate base PNG icons
python3 generate_icon.py

# Resize for Android densities
python3 resize_icons.py

# Or use flutter_launcher_icons for all platforms
flutter pub run flutter_launcher_icons
```
