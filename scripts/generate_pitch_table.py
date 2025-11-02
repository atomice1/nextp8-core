#!/usr/bin/env python3
"""
Generate PICO-8 pitch phase increment table.

PICO-8 pitch system:
- Pitch 0 = C0 (16.35 Hz) - two octaves below C2
- Pitch 24 = C2 (65.41 Hz) 
- Pitch 57 = A4 (440 Hz) - the musical reference pitch
- Formula: freq = 440 * 2^((note - 57) / 12)

Phase accumulator:
- 32-bit phase accumulator incremented at 22050 Hz sample rate
- phase_inc = (2^32 * freq) / 22050
"""

import math

SAMPLE_RATE = 22050
PHASE_BITS = 32
REFERENCE_FREQ = 440.0
REFERENCE_NOTE = 33

def calculate_phase_inc(note):
    """Calculate phase increment for a given PICO-8 pitch (note number)."""
    # Formula: freq = 440 * 2^((note - 57) / 12)
    # note 0 = C0 = 16.35Hz
    # note 24 = C2 = 65.41Hz
    # note 33 = A2 = 110Hz
    # note 57 = A4 = 440 Hz
    freq = REFERENCE_FREQ * math.pow(2.0, (note - REFERENCE_NOTE) / 12.0)
    phase_inc = (math.pow(2, PHASE_BITS) * freq) / SAMPLE_RATE
    return int(phase_inc)

def main():
    # Generate table for PICO-8 pitches 0..95
    entries = [calculate_phase_inc(i) for i in range(96)]
    
    # Print some key frequencies for verification
    print(f"Note  0 (C0): {REFERENCE_FREQ * math.pow(2.0, (0 - REFERENCE_NOTE) / 12.0):.2f} Hz -> 0x{entries[0]:08x} ({entries[0]})")
    print(f"Note 12 (C1): {REFERENCE_FREQ * math.pow(2.0, (12 - REFERENCE_NOTE) / 12.0):.2f} Hz -> 0x{entries[12]:08x} ({entries[12]})")
    print(f"Note 24 (C2): {REFERENCE_FREQ * math.pow(2.0, (24 - REFERENCE_NOTE) / 12.0):.2f} Hz -> 0x{entries[24]:08x} ({entries[24]})")
    print(f"Note 33 (A2): {REFERENCE_FREQ * math.pow(2.0, (33 - REFERENCE_NOTE) / 12.0):.2f} Hz -> 0x{entries[33]:08x} ({entries[33]})")
    print(f"Note 36 (C3): {REFERENCE_FREQ * math.pow(2.0, (36 - REFERENCE_NOTE) / 12.0):.2f} Hz -> 0x{entries[36]:08x} ({entries[36]})")
    print(f"Note 48 (C4): {REFERENCE_FREQ * math.pow(2.0, (48 - REFERENCE_NOTE) / 12.0):.2f} Hz -> 0x{entries[48]:08x} ({entries[48]})")
    print(f"Note 57 (A4): {REFERENCE_FREQ * math.pow(2.0, (57 - REFERENCE_NOTE) / 12.0):.2f} Hz -> 0x{entries[57]:08x} ({entries[57]})")
    print(f"Note 60 (C5): {REFERENCE_FREQ * math.pow(2.0, (60 - REFERENCE_NOTE) / 12.0):.2f} Hz -> 0x{entries[60]:08x} ({entries[60]})")
    print(f"Note 72 (C6): {REFERENCE_FREQ * math.pow(2.0, (72 - REFERENCE_NOTE) / 12.0):.2f} Hz -> 0x{entries[72]:08x} ({entries[72]})")
    print(f"Note 84 (C7): {REFERENCE_FREQ * math.pow(2.0, (84 - REFERENCE_NOTE) / 12.0):.2f} Hz -> 0x{entries[84]:08x} ({entries[84]})")
    print()
    
    # Verify octave relationships (should all be 2.0)
    print("Octave verification (should all be 2.0):")
    print(f"Note  0->12: ratio {entries[12] / entries[0]:.6f}")
    print(f"Note 12->24: ratio {entries[24] / entries[12]:.6f}")
    print(f"Note 24->36: ratio {entries[36] / entries[24]:.6f}")
    print(f"Note 36->48: ratio {entries[48] / entries[36]:.6f}")
    print(f"Note 48->60: ratio {entries[60] / entries[48]:.6f}")
    print(f"Note 60->72: ratio {entries[72] / entries[60]:.6f}")
    print(f"Note 72->84: ratio {entries[84] / entries[72]:.6f}")
    print()
    
    # Generate Verilog table
    print("// Pitch table (32-bit fixed-point phase increments for PICO-8 pitches 0..95)")
    print("// PICO-8 pitch 0 = C0, pitch 24 = C2, pitch 57 = A4 (440 Hz)")
    print("// phase_inc = (2^32 * freq) / 22050; freq = 440*2^((note-33)/12)")
    print("reg [31:0] pitch_phase_inc [0:95];")
    print("initial begin")
    
    for i in range(0, 96, 2):
        print(f"    pitch_phase_inc[{i:2d}] = 32'h{entries[i]:08x}; pitch_phase_inc[{i+1:2d}] = 32'h{entries[i+1]:08x};")
    
    print("end")

if __name__ == "__main__":
    main()
