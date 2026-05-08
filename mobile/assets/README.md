# App Icon Assets

This directory contains the logo and icon generation scripts for the am_radio Flutter app.

## Files

- `logo_design.txt` - Logo design documentation
- `generate_icon.py` - Python script to create PNG icon using Unicode/graphical design
- `resize_icons.py` - Python script to resize icons for Android densities
- `generate_icons.sh` - Shell script to regenerate all app icons
- `icon.png` - Main 512x512 icon (generated)
- `icon_1024.png` - iOS 1024x1024 icon (generated)

## Icon Design

The logo is a clean, minimalist vintage radio featuring:
- Antenna with circular tip at top
- Rounded rectangle radio body (vintage style)
- Central tuning dial with pointer
- "AM" text in bold
- Horizontal speaker grille lines at bottom

The design uses Unicode radio emoji (📻) as the primary approach, with a graphical fallback that renders a clean vector-style radio when emoji fonts aren't available.

Colors match the app's vintage bakelite theme:
- Background: #1A0F00 (dark brown)
- Foreground: #E8A020 (amber)

The minimalist design ensures clarity on all screen densities and device displays, especially important for small icon sizes.

## Regenerating Icons

After modifying the design in `generate_icon.py`, regenerate all app icons:

```bash
cd mobile
nix develop ..#mobile
./assets/generate_icons.sh
```

This will:
1. Generate icon.png and icon_1024.png from the design
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

