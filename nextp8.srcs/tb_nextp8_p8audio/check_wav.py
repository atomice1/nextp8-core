#!/usr/bin/env python3
"""
Check WAV file for non-zero audio samples.
Exits with code 0 if non-zero samples found, code 1 otherwise.
"""

import sys
import struct

def check_wav(filename):
    with open(filename, 'rb') as f:
        # Skip WAV header (44 bytes)
        f.seek(44)

        # Read all sample data
        data = f.read()

        # Parse 16-bit little-endian samples
        num_samples = len(data) // 2
        samples = struct.unpack(f'<{num_samples}h', data)

        # In one failure mode, the first sample is -1 and the rest zeroes
        if samples[0] == -1 and samples[1] == 0:
            samples = samples[1:]
            first_is_minus_one = True
        else:
            first_is_minus_one = False

        # Count non-zero samples
        non_zero = sum(1 for s in samples if s != 0)

        print(f"Total samples: {num_samples}")
        print(f"Non-zero samples: {non_zero}")
        print(f"Zero samples: {num_samples - non_zero}")

        if non_zero == 0:
            if first_is_minus_one:
                print("ERROR: First sample is -1, rest are zero!")
            else:
                print("ERROR: All samples are zero!")
            return False

        # Show min/max for diagnostics
        if samples:
            print(f"Sample range: [{min(samples)}, {max(samples)}]")

        print("PASS: Non-zero audio detected")
        return True

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <wavfile>")
        sys.exit(1)
    
    success = check_wav(sys.argv[1])
    sys.exit(0 if success else 1)
