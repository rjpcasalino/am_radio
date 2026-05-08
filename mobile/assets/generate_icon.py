#!/usr/bin/env python3
"""
Generate app icon from ASCII art for am_radio Flutter app.
Uses the vintage bakelite color palette from the app.
"""

from PIL import Image, ImageDraw, ImageFont
import os

# Color palette from mobile/lib/main.dart
BACKGROUND = "#1A0F00"  # Dark brown
AMBER = "#E8A020"       # Primary amber
CREAM = "#F0E0B0"       # On-surface cream

# ASCII art logo
LOGO = """   !
 __║__
[●─⊙─●]
| A M |
|≈≈≈≈≈|
'-----'"""

def create_icon(size=512):
    """Create a square icon with ASCII art"""
    # Create image with dark background
    img = Image.new('RGB', (size, size), BACKGROUND)
    draw = ImageDraw.Draw(img)

    # Try to use a monospace font, fallback to default
    try:
        # Try common monospace fonts
        for font_name in ['DejaVuSansMono', 'Courier', 'Monaco', 'Consolas']:
            try:
                font = ImageFont.truetype(font_name, size=size // 12)
                break
            except:
                continue
        else:
            # If no truetype font found, use default
            font = ImageFont.load_default()
    except:
        font = ImageFont.load_default()

    # Draw ASCII art centered
    lines = LOGO.strip().split('\n')

    # Calculate text dimensions for centering
    line_height = size // 10
    total_height = len(lines) * line_height
    y_offset = (size - total_height) // 2

    for i, line in enumerate(lines):
        # Get text width for centering
        bbox = draw.textbbox((0, 0), line, font=font)
        text_width = bbox[2] - bbox[0]
        x_offset = (size - text_width) // 2

        y_pos = y_offset + (i * line_height)

        # Draw text in amber/cream color
        draw.text((x_offset, y_pos), line, fill=AMBER, font=font)

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
