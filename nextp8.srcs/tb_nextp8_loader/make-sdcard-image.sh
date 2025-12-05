#!/bin/bash
# Script to create SD card image for tb_nextp8_loader testbench
# Based on scripts/make-sdcard.sh

set -e

scriptdir="$(dirname "$0")"
basedir="${scriptdir}/../../.."
tb_dir="${scriptdir}"
mountpoint="$(mktemp -d)"

# Build the application binary
echo "=== Building hello test application ==="
make -f "${tb_dir}/Makefile.app" -C "${tb_dir}"
echo ""

# Check that nextp8.bin exists
if [ ! -f "${tb_dir}/nextp8.bin" ]; then
    echo "ERROR: nextp8.bin not found. Build failed?"
    exit 1
fi

# Create 1MB SD card image (1024 * 1KB blocks)
echo "=== Creating SD card image ==="
dd if=/dev/zero of="${tb_dir}/sdcard.img" bs=1024 count=1024
mkfs.vfat "${tb_dir}/sdcard.img"

# Mount the image
echo "=== Mounting SD card image ==="
mkdir -p "${mountpoint}"
sudo mount -o loop,uid="${LOGNAME}" "${tb_dir}/sdcard.img" "${mountpoint}"

# Create directory structure
echo "=== Creating directory structure ==="
mkdir -p "${mountpoint}/machines/nextp8"

# Copy the hello test application as nextp8.bin
echo "=== Copying nextp8.bin (hello test application) ==="
cp "${tb_dir}/nextp8.bin" "${mountpoint}/machines/nextp8/nextp8.bin"

# Unmount
echo "=== Unmounting SD card image ==="
sudo umount "${mountpoint}"
rmdir "${mountpoint}"

echo ""
echo "=== SD card image created successfully ==="
echo "Image: ${tb_dir}/sdcard.img"
echo "Size: 1 MB"
echo ""

# List contents using debugfs for verification
echo "=== Verifying SD card contents ==="
if command -v mdir >/dev/null 2>&1; then
    echo "Contents:"
    mdir -i "${tb_dir}/sdcard.img" -/
else
    echo "(Install mtools to verify FAT filesystem contents)"
fi

echo ""
echo "Expected contents:"
echo "  /machines/nextp8/nextp8.bin        - Hello test application (116 bytes)"
echo ""
echo "To use in testbench, ensure loader.mem exists and run:"
echo "  cd ${tb_dir}"
echo "  make sim"
