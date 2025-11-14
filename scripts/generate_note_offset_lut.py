#!/usr/bin/env python3
"""
Generate PICO-8 note_offset_lut table for envelope effects.

note_offset ramps from 0 to 2^24 over the duration of a note effect.
Used for slide, fade in/out, and drop effects.

PICO-8 SFX speed is in ticks, with 120 ticks per second (22050/183 ≈ 120.49).
For speed_byte = 1 to 255:
  increment = 2^24 // (183 * speed_byte)

This ensures note_offset reaches exactly 2^24 after speed_byte ticks.
"""

def calculate_note_offset_inc(speed_byte):
    """Calculate note_offset increment for a given speed_byte."""
    if speed_byte == 0:
        return 0  # Not used, but included for completeness
    return (1 << 24) // (183 * speed_byte)

def main():
    print("Generating note_offset_lut values...")
    
    # Generate table for speed_byte 0..255
    entries = [calculate_note_offset_inc(i) for i in range(256)]
    
    # Print some key values for verification
    print(f"speed_byte  0: increment = {entries[0]} (not used)")
    print(f"speed_byte  1: increment = {entries[1]} (fastest, {entries[1]} per sample)")
    print(f"speed_byte 16: increment = {entries[16]} (default speed)")
    print(f"speed_byte 32: increment = {entries[32]}")
    print(f"speed_byte 64: increment = {entries[64]}")
    print(f"speed_byte 128: increment = {entries[128]}")
    print(f"speed_byte 255: increment = {entries[255]} (slowest)")
    print()
    
    # Verify that increment * (183 * speed_byte) ≈ 2^24
    print("Verification (increment * (183 * speed_byte) should be close to 2^24 = 16777216):")
    for speed in [1, 16, 32, 64, 128, 255]:
        product = entries[speed] * (183 * speed)
        error = abs(product - (1 << 24))
        print(f"speed {speed:3d}: {entries[speed]:8d} * (183 * {speed:3d}) = {product:8d} (error: {error})")
    print()
    
    # Generate Verilog table
    print("// note_offset_lut for U17F24 fixed-point envelope effects")
    print("// note_offset increments per tick for each speed_byte value")
    print("// increment = 2^24 // (183 * speed_byte) (183 ticks per second at 22050 Hz)")
    print("// Top 7 bits are always 0, so we use U17F24 format")
    print("reg [16:0] note_offset_lut [0:255];")
    print("initial begin")
    print("    note_offset_lut[  0] = 17'h1ffff;  // Special value, not used")
    
    # Print in groups of 4 for readability
    for i in range(1, 256, 4):
        line = f"    note_offset_lut[{i:3d}] = 17'h{entries[i]:05x};"
        if i+1 < 256:
            line += f"   note_offset_lut[{i+1:3d}] = 17'h{entries[i+1]:05x};"
        if i+2 < 256:
            line += f"   note_offset_lut[{i+2:3d}] = 17'h{entries[i+2]:05x};"
        if i+3 < 256:
            line += f"   note_offset_lut[{i+3:3d}] = 17'h{entries[i+3]:05x};"
        print(line)
    
    print("end")

if __name__ == "__main__":
    main()