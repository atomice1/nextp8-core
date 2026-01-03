#!/usr/bin/env python3
"""
Create an SD card image for tb_nextp8_loader testbench.

This script creates a 1MB FAT filesystem image in user space using pyfatfs,
and populates it with the nextp8.bin test application.

Requirements:
    - pyfatfs: pip install pyfatfs

Usage:
    make-sdcard-image.py [-o OUTPUT] BIN_FILE

Arguments:
    BIN_FILE    Path to nextp8.bin file to include in image

Options:
    -o, --output FILE    Output image file (default: sdcard.img)
    -h, --help          Show this help message
"""

import argparse
import sys
from pathlib import Path

try:
    from pyfatfs.PyFatFS import PyFatFS
    from pyfatfs.PyFat import PyFat
except ImportError:
    print("Error: pyfatfs module not found. Install it with:", file=sys.stderr)
    print("  pip install pyfatfs", file=sys.stderr)
    sys.exit(1)


def create_fat_image(image_path, size_mb=1):
    """
    Create an empty FAT filesystem image.

    Args:
        image_path: Path to the image file to create
        size_mb: Size of the image in megabytes (default: 1MB)
    """
    size_bytes = size_mb * 1024 * 1024

    fat_type = PyFat.FAT_TYPE_FAT12
    fat_name = "FAT12"

    print(f"Creating {size_mb}MB {fat_name} image: {image_path}")

    with open(image_path, 'wb') as f:
        f.truncate(size_bytes)

    # Format as FAT
    fs = PyFat()
    fs.mkfs(
        str(image_path),
        fat_type=fat_type,
        size=size_bytes,
        label="NEXTP8"
    )
    fs.close()

    with open(image_path, 'r+b') as f:
        # Read sectors per FAT
        f.seek(0x16)
        sectors_per_fat = int.from_bytes(f.read(2), 'little')

        # Fix CHS geometry - use common SD card values
        f.seek(0x18)  # sectors/track
        f.write(b'\x20\x00')  # 32 sectors/track
        f.seek(0x1A)  # heads
        f.write(b'\x40\x00')  # 64 heads

        # Fix FAT initialization (both copies) for FAT12
        fat_init = b'\xf8\xff\xff'

        fat1_offset = 0x200  # First FAT starts after boot sector
        fat2_offset = fat1_offset + (sectors_per_fat * 512)  # Second FAT

        for fat_offset in [fat1_offset, fat2_offset]:
            f.seek(fat_offset)
            f.write(fat_init)


def populate_image(image_path, bin_file):
    """
    Populate the FAT image with the test application.

    Args:
        image_path: Path to the FAT image file
        bin_file: Path to nextp8.bin file
    """
    bin_path = Path(bin_file)

    if not bin_path.exists():
        print(f"Error: Binary file not found: {bin_file}", file=sys.stderr)
        sys.exit(1)

    print(f"Populating FAT image...")

    with PyFatFS(str(image_path)) as fs:
        dest_dir = "machines/nextp8"
        print(f"  Creating directory: {dest_dir}")
        fs.makedirs(dest_dir, recreate=True)

        dest_file = f"{dest_dir}/nextp8.bin"
        print(f"  Copying: {bin_path.name} -> {dest_file}")

        with open(bin_path, 'rb') as f:
            data = f.read()

        with fs.open(dest_file, 'wb') as fat_file:
            fat_file.write(data)

    print(f"\nSD card image created successfully: {image_path}")
    print(f"Size: 1MB")
    print(f"Contents: {dest_file} ({len(data)} bytes)")


def main():
    parser = argparse.ArgumentParser(
        description="Create an SD card image for tb_nextp8_loader testbench.",
        formatter_class=argparse.RawDescriptionHelpFormatter
    )

    parser.add_argument(
        'bin_file',
        help='Path to nextp8.bin file to include in image'
    )

    parser.add_argument(
        '-o', '--output',
        default='sdcard.img',
        help='Output image file (default: sdcard.img)'
    )

    args = parser.parse_args()

    image_path = Path(args.output).absolute()

    create_fat_image(image_path, size_mb=1)

    populate_image(image_path, args.bin_file)


if __name__ == '__main__':
    main()
