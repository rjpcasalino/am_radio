#!/usr/bin/env python3
"""
Generate app icon using Unicode radio symbol for am_radio Flutter app.
Uses the vintage bakelite color palette from the app.
"""

from PIL import Image, ImageDraw, ImageFont
import os

# Color palette from mobile/lib/main.dart
BACKGROUND = "#1A0F00"  # Dark brown
AMBER = "#E8A020"       # Primary amber
CREAM = "#F0E0B0"       # On-surface cream

# Unicode radio symbol - using the official radio emoji/symbol
# U+1F4FB (📻) Radio emoji
RADIO_SYMBOL = "📻"

def create_icon(size=512):
    """Create a square icon with Unicode radio symbol"""
    # Create image with dark background
    img = Image.new('RGB', (size, size), BACKGROUND)
    draw = ImageDraw.Draw(img)

    # Try to find a font that supports Unicode emoji/symbols
    font = None
    font_size = int(size * 0.6)  # Make the symbol large

    # Try various fonts that might have good Unicode support
    font_candidates = [
        'NotoColorEmoji',  # Google's emoji font
        'AppleColorEmoji',  # Apple emoji font
        'Segoe UI Emoji',   # Windows emoji font
        'Noto Sans Symbols2',  # Symbol font
        'DejaVuSans',       # Fallback with good Unicode support
        'Arial Unicode MS',
        'Symbola',
    ]

    for font_name in font_candidates:
        try:
            font = ImageFont.truetype(font_name, size=font_size)
            break
        except:
            continue

    # If no truetype font found, try system default with large size
    if font is None:
        try:
            # Try to load a larger default font
            font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', size=font_size)
        except:
            # Absolute fallback - create a simple graphical radio instead
            return create_graphical_radio(size)

    # Get text bounding box for centering
    bbox = draw.textbbox((0, 0), RADIO_SYMBOL, font=font)
    text_width = bbox[2] - bbox[0]
    text_height = bbox[3] - bbox[1]

    # Center the symbol
    x = (size - text_width) // 2 - bbox[0]
    y = (size - text_height) // 2 - bbox[1]

    # Draw the radio symbol in amber
    draw.text((x, y), RADIO_SYMBOL, fill=AMBER, font=font)

    return img

def create_graphical_radio(size=512):
    """Create a simple graphical radio icon if emoji font is not available"""
    img = Image.new('RGB', (size, size), BACKGROUND)
    draw = ImageDraw.Draw(img)

    # Padding from edges
    padding = size // 6

    # Radio body - rounded rectangle
    body_left = padding
    body_top = padding * 2
    body_right = size - padding
    body_bottom = size - padding
    corner_radius = size // 10

    # Draw radio body outline in amber
    draw.rounded_rectangle(
        [body_left, body_top, body_right, body_bottom],
        radius=corner_radius,
        outline=AMBER,
        width=size // 40
    )

    # Draw antenna
    antenna_x = size // 2
    antenna_bottom = body_top
    antenna_top = padding // 2
    draw.line([antenna_x, antenna_bottom, antenna_x, antenna_top], fill=AMBER, width=size // 50)

    # Draw antenna tip
    tip_size = size // 30
    draw.ellipse([antenna_x - tip_size, antenna_top - tip_size,
                  antenna_x + tip_size, antenna_top + tip_size], fill=AMBER)

    # Draw dial/tuner (circle)
    dial_y = body_top + (body_bottom - body_top) // 3
    dial_size = size // 6
    dial_x = size // 2
    draw.ellipse([dial_x - dial_size, dial_y - dial_size,
                  dial_x + dial_size, dial_y + dial_size],
                 outline=AMBER, width=size // 60)

    # Draw pointer on dial
    pointer_size = dial_size // 2
    draw.line([dial_x, dial_y, dial_x, dial_y - pointer_size],
              fill=AMBER, width=size // 80)

    # Draw "AM" text
    try:
        font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
                                 size=size // 8)
    except:
        font = ImageFont.load_default()

    text = "AM"
    bbox = draw.textbbox((0, 0), text, font=font)
    text_width = bbox[2] - bbox[0]
    text_height = bbox[3] - bbox[1]
    text_x = (size - text_width) // 2 - bbox[0]
    text_y = dial_y + dial_size + padding // 2
    draw.text((text_x, text_y), text, fill=AMBER, font=font)

    # Draw speaker grille (horizontal lines at bottom)
    grille_top = text_y + text_height + padding // 3
    grille_bottom = body_bottom - padding // 2
    grille_left = body_left + padding
    grille_right = body_right - padding
    num_lines = 5

    for i in range(num_lines):
        y = grille_top + (grille_bottom - grille_top) * i // (num_lines - 1)
        draw.line([grille_left, y, grille_right, y], fill=AMBER, width=size // 100)

    return img

def main():
    """Generate icons for different sizes"""
    output_dir = os.path.dirname(os.path.abspath(__file__))

    # Create main icon
    icon = create_icon(512)
    icon.save(os.path.join(output_dir, 'icon.png'))
    print(f"Created icon.png (512x512)")

    # Also create a 1024x1024 version for iOS
    icon_1024 = create_icon(1024)
    icon_1024.save(os.path.join(output_dir, 'icon_1024.png'))
    print(f"Created icon_1024.png (1024x1024)")

if __name__ == '__main__':
    main()
