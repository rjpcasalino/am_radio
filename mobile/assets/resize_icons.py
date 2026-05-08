#!/usr/bin/env python3
"""
Resize icon for different Android densities
"""

from PIL import Image
import os

# Android icon sizes for different densities
SIZES = {
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
}

def resize_icons():
    """Resize the main icon for all Android densities"""
    input_path = 'icon.png'

    if not os.path.exists(input_path):
        print(f"Error: {input_path} not found!")
        return

    img = Image.open(input_path)

    for density, size in SIZES.items():
        output_dir = f'../android/app/src/main/res/mipmap-{density}'
        os.makedirs(output_dir, exist_ok=True)

        # Resize with high-quality resampling
        resized = img.resize((size, size), Image.Resampling.LANCZOS)
        output_path = os.path.join(output_dir, 'ic_launcher.png')
        resized.save(output_path)

        print(f"Created {output_path} ({size}x{size})")

if __name__ == '__main__':
    resize_icons()
