#!/usr/bin/env python3
"""
compare_audio.py - Compare reference and output WAV files for PICO-8 audio analysis

Compares two sets of WAV files (reference vs output) and generates a contact sheet
showing amplitude and frequency spectrum analysis for each SFX (0-63).

Usage:
    python compare_audio.py "reference_sfx_%d.wav" "output_sfx_%d.wav"
"""

import sys
import numpy as np
import wave
import matplotlib.pyplot as plt
import matplotlib.gridspec as gridspec
from pathlib import Path

# PICO-8 audio constants
FRAME_SIZE = 16 * 183  # 2928 samples per frame (16 notes at 183 samples per note @ 22.05kHz)
NUM_SFX = 64
NUM_FREQUENCIES = 96  # PICO-8 note range 0-95

def pico8_note_to_freq(note):
    """Convert PICO-8 note index (0-95) to frequency in Hz"""
    return 440.0 * (2.0 ** ((note - 33.0) / 12.0))

def read_wav(filename):
    """Read WAV file and return samples as numpy array"""
    try:
        with wave.open(filename, 'rb') as wav:
            n_channels = wav.getnchannels()
            sampwidth = wav.getsampwidth()
            framerate = wav.getframerate()
            n_frames = wav.getnframes()
            
            # Read raw audio data
            audio_data = wav.readframes(n_frames)
            
            # Convert to numpy array
            if sampwidth == 1:
                samples = np.frombuffer(audio_data, dtype=np.uint8)
                samples = (samples.astype(np.float32) - 128) / 128.0
            elif sampwidth == 2:
                samples = np.frombuffer(audio_data, dtype=np.int16)
                samples = samples.astype(np.float32) / 32768.0
            else:
                raise ValueError(f"Unsupported sample width: {sampwidth}")
            
            # Handle stereo by taking first channel
            if n_channels == 2:
                samples = samples[::2]
            
            return samples, framerate
    except FileNotFoundError:
        return None, None
    except Exception as e:
        print(f"Error reading {filename}: {e}")
        return None, None

def calculate_frame_amplitude(frame):
    """Calculate RMS amplitude of a frame"""
    return np.sqrt(np.mean(frame ** 2))

def calculate_frame_spectrum(frame, sample_rate):
    """
    Calculate frequency spectrum for PICO-8 note frequencies.
    Returns intensity at each of the 96 PICO-8 note frequencies.
    """
    # Apply window to reduce spectral leakage
    windowed = frame * np.hanning(len(frame))
    
    # FFT
    fft = np.fft.rfft(windowed)
    fft_freqs = np.fft.rfftfreq(len(frame), 1.0 / sample_rate)
    fft_mag = np.abs(fft)
    
    # Calculate intensity at each PICO-8 note frequency
    spectrum = np.zeros(NUM_FREQUENCIES)
    for note_idx in range(NUM_FREQUENCIES):
        target_freq = pico8_note_to_freq(note_idx)
        
        # Find nearest FFT bin
        bin_idx = np.argmin(np.abs(fft_freqs - target_freq))
        
        # Use magnitude at that bin (could also sum nearby bins for better accuracy)
        spectrum[note_idx] = fft_mag[bin_idx]
    
    return spectrum

def analyze_wav(samples, sample_rate):
    """
    Analyze WAV file samples.
    Returns:
        - amplitudes: list of RMS amplitude per frame
        - spectra: 2D array of frequency intensities (frames × frequencies)
    """
    if samples is None or len(samples) == 0:
        return [], np.array([])
    
    num_frames = len(samples) // FRAME_SIZE
    amplitudes = []
    spectra = []
    
    for frame_idx in range(num_frames):
        start = frame_idx * FRAME_SIZE
        end = start + FRAME_SIZE
        frame = samples[start:end]
        
        if len(frame) < FRAME_SIZE:
            # Pad last frame if needed
            frame = np.pad(frame, (0, FRAME_SIZE - len(frame)), mode='constant')
        
        amp = calculate_frame_amplitude(frame)
        spec = calculate_frame_spectrum(frame, sample_rate)
        
        amplitudes.append(amp)
        spectra.append(spec)
    
    return amplitudes, np.array(spectra)

def calculate_differences(ref_amps, ref_specs, out_amps, out_specs):
    """Calculate amplitude and spectrum differences"""
    # Pad shorter sequence to match longer one
    max_frames = max(len(ref_amps), len(out_amps))
    
    ref_amps_padded = np.pad(ref_amps, (0, max_frames - len(ref_amps)), mode='constant')
    out_amps_padded = np.pad(out_amps, (0, max_frames - len(out_amps)), mode='constant')
    
    # Amplitude differences
    amp_diffs = np.abs(ref_amps_padded - out_amps_padded)
    mean_amp_diff = np.mean(amp_diffs)
    
    # Spectrum differences
    if ref_specs.size > 0 and out_specs.size > 0:
        # Pad spectrum arrays
        ref_specs_padded = np.pad(ref_specs, ((0, max_frames - ref_specs.shape[0]), (0, 0)), mode='constant')
        out_specs_padded = np.pad(out_specs, ((0, max_frames - out_specs.shape[0]), (0, 0)), mode='constant')
        
        spec_diffs = np.abs(ref_specs_padded - out_specs_padded)
        mean_spec_diff = np.mean(spec_diffs)
    else:
        spec_diffs = np.zeros((max_frames, NUM_FREQUENCIES))
        mean_spec_diff = 0.0
    
    return amp_diffs, spec_diffs, mean_amp_diff, mean_spec_diff

def plot_sfx_comparison(ax_row, sfx_idx, ref_amps, ref_specs, out_amps, out_specs, 
                        amp_diffs, spec_diffs, mean_amp_diff, mean_spec_diff,
                        is_first=False, is_last=False):
    """Plot one row of comparison (6 plots: 3 pairs of amplitude/spectrum)"""
    
    # Reference amplitude
    ax = ax_row[0]
    if len(ref_amps) > 0:
        ax.bar(range(len(ref_amps)), ref_amps, width=1.0, color='blue', edgecolor='none')
        ax.set_ylim(0, 1.0)
    ax.set_ylabel(f'SFX {sfx_idx}\nAmp', fontsize=6)
    ax.tick_params(labelsize=5)
    ax.grid(True, alpha=0.3, axis='y')
    if is_first:
        ax.set_title('Reference', fontsize=7)
    
    # Reference spectrum
    ax = ax_row[1]
    if ref_specs.size > 0:
        # Transpose so frequency is on Y axis
        ax.imshow(ref_specs.T, aspect='auto', origin='lower', cmap='hot', 
                 interpolation='nearest', vmin=0, vmax=np.max(ref_specs) if np.max(ref_specs) > 0 else 1)
    ax.set_ylabel('Freq', fontsize=6)
    ax.tick_params(labelsize=5)
    if is_first:
        ax.set_title('Spectrum', fontsize=7)
    
    # Output amplitude
    ax = ax_row[2]
    if len(out_amps) > 0:
        ax.bar(range(len(out_amps)), out_amps, width=1.0, color='green', edgecolor='none')
        ax.set_ylim(0, 1.0)
    ax.set_ylabel('Amp', fontsize=6)
    ax.tick_params(labelsize=5)
    ax.grid(True, alpha=0.3, axis='y')
    if is_first:
        ax.set_title('Output', fontsize=7)
    
    # Output spectrum
    ax = ax_row[3]
    if out_specs.size > 0:
        ax.imshow(out_specs.T, aspect='auto', origin='lower', cmap='hot',
                 interpolation='nearest', vmin=0, vmax=np.max(out_specs) if np.max(out_specs) > 0 else 1)
    ax.set_ylabel('Freq', fontsize=6)
    ax.tick_params(labelsize=5)
    if is_first:
        ax.set_title('Spectrum', fontsize=7)
    
    # Difference amplitude
    ax = ax_row[4]
    if len(amp_diffs) > 0:
        ax.bar(range(len(amp_diffs)), amp_diffs, width=1.0, color='red', edgecolor='none')
        ax.set_ylim(0, 1.0)
    ax.set_ylabel(f'Amp Δ\n{mean_amp_diff:.3f}', fontsize=6)
    ax.tick_params(labelsize=5)
    ax.grid(True, alpha=0.3, axis='y')
    if is_first:
        ax.set_title('Difference', fontsize=7)
    
    # Difference spectrum
    ax = ax_row[5]
    if spec_diffs.size > 0:
        max_diff = np.max(spec_diffs) if np.max(spec_diffs) > 0 else 1
        ax.imshow(spec_diffs.T, aspect='auto', origin='lower', cmap='hot',
                 interpolation='nearest', vmin=0, vmax=max_diff)
    ax.set_ylabel(f'Freq Δ\n{mean_spec_diff:.3f}', fontsize=6)
    ax.tick_params(labelsize=5)
    if is_first:
        ax.set_title('Spectrum', fontsize=7)
    
    # Only show x-axis labels on bottom row
    if is_last:
        for i, label in enumerate(['Time', 'Time', 'Time', 'Time', 'Time', 'Time']):
            ax_row[i].set_xlabel(label, fontsize=6)
    else:
        for i in range(6):
            ax_row[i].set_xticklabels([])

def main():
    if len(sys.argv) != 3:
        print("Usage: python compare_audio.py <reference_pattern> <output_pattern>")
        print("Example: python compare_audio.py 'ref_sfx_%d.wav' 'out_sfx_%d.wav'")
        print("         python compare_audio.py 'reference.wav' 'output.wav'")
        sys.exit(1)
    
    ref_pattern = sys.argv[1]
    out_pattern = sys.argv[2]
    
    print(f"Comparing audio files...")
    print(f"  Reference pattern: {ref_pattern}")
    print(f"  Output pattern: {out_pattern}")
    
    # Check if patterns contain %d (multi-file mode) or not (single-file mode)
    is_multi_file = '%d' in ref_pattern or '%d' in out_pattern
    
    if is_multi_file:
        # Validate both patterns have %d
        if '%d' not in ref_pattern or '%d' not in out_pattern:
            print("ERROR: Both patterns must contain %d for multi-file mode")
            sys.exit(1)
        print(f"\nMulti-file comparison mode (SFX 0-63)")
        sfx_range = range(NUM_SFX)
    else:
        print(f"\nSingle file comparison mode")
        sfx_range = [0]  # Single iteration with dummy index
    
    # First pass: collect data for SFX that have both files
    sfx_data = []  # List of (sfx_idx, ref_amps, ref_specs, out_amps, out_specs, amp_diffs, spec_diffs, mean_amp_diff, mean_spec_diff)
    
    # Process each SFX
    for sfx_idx in sfx_range:
        if is_multi_file:
            ref_filename = ref_pattern % sfx_idx
            out_filename = out_pattern % sfx_idx
        else:
            ref_filename = ref_pattern
            out_filename = out_pattern
        
        # Check if files exist
        ref_exists = Path(ref_filename).exists()
        out_exists = Path(out_filename).exists()
        
        if not ref_exists and not out_exists:
            # Both files missing - skip silently (only in multi-file mode)
            if is_multi_file:
                continue
            else:
                print(f"ERROR: Both files not found")
                sys.exit(1)
        
        if not ref_exists:
            msg = f"Reference file not found: {ref_filename}"
            if is_multi_file:
                print(f"WARNING: SFX {sfx_idx}: {msg}")
                continue
            else:
                print(f"ERROR: {msg}")
                sys.exit(1)
            
        if not out_exists:
            msg = f"Output file not found: {out_filename}"
            if is_multi_file:
                print(f"WARNING: SFX {sfx_idx}: {msg}")
                continue
            else:
                print(f"ERROR: {msg}")
                sys.exit(1)
        
        print(f"Processing SFX {sfx_idx}: {ref_filename} vs {out_filename}" if is_multi_file 
              else f"Processing: {ref_filename} vs {out_filename}")
        
        # Read WAV files
        ref_samples, ref_rate = read_wav(ref_filename)
        out_samples, out_rate = read_wav(out_filename)
        
        # Analyze
        ref_amps, ref_specs = analyze_wav(ref_samples, ref_rate) if ref_samples is not None else ([], np.array([]))
        out_amps, out_specs = analyze_wav(out_samples, out_rate) if out_samples is not None else ([], np.array([]))
        
        # Calculate differences
        amp_diffs, spec_diffs, mean_amp_diff, mean_spec_diff = calculate_differences(
            ref_amps, ref_specs, out_amps, out_specs
        )
        
        # Store data for this SFX
        sfx_data.append((sfx_idx, ref_amps, ref_specs, out_amps, out_specs, 
                        amp_diffs, spec_diffs, mean_amp_diff, mean_spec_diff))
    
    if len(sfx_data) == 0:
        print("\nNo data was compared (all files missing)")
        return
    
    # Create figure with grid layout based on actual number of SFX
    num_sfx_to_plot = len(sfx_data)
    fig = plt.figure(figsize=(24, num_sfx_to_plot * 1.5))
    gs = gridspec.GridSpec(num_sfx_to_plot, 6, figure=fig, hspace=0.3, wspace=0.3)
    
    overall_amp_diffs = []
    overall_spec_diffs = []
    sfx_with_data = []
    
    # Second pass: plot the data
    for plot_row, (sfx_idx, ref_amps, ref_specs, out_amps, out_specs, 
                   amp_diffs, spec_diffs, mean_amp_diff, mean_spec_diff) in enumerate(sfx_data):
        
        overall_amp_diffs.append(mean_amp_diff)
        overall_spec_diffs.append(mean_spec_diff)
        sfx_with_data.append(sfx_idx)
        
        # Create subplot row
        ax_row = [fig.add_subplot(gs[plot_row, i]) for i in range(6)]
        
        # Plot (use plot_row for position, sfx_idx for labeling)
        plot_sfx_comparison(ax_row, sfx_idx, ref_amps, ref_specs, out_amps, out_specs,
                          amp_diffs, spec_diffs, mean_amp_diff, mean_spec_diff,
                          is_first=(plot_row == 0), is_last=(plot_row == num_sfx_to_plot - 1))
    
    # Add overall statistics as title
    mean_overall_amp = np.mean(overall_amp_diffs)
    mean_overall_spec = np.mean(overall_spec_diffs)
    num_compared = len(sfx_with_data)
    fig.suptitle(f'Audio Comparison Contact Sheet\n'
                f'Compared {num_compared} SFX pairs  |  '
                f'Mean Amplitude Difference: {mean_overall_amp:.4f}  |  '
                f'Mean Spectrum Difference: {mean_overall_spec:.4f}',
                fontsize=10, fontweight='bold')
    
    # Save
    output_file = 'audio_comparison.png'
    print(f"\nSaving comparison to {output_file}...")
    plt.savefig(output_file, dpi=150, bbox_inches='tight')
    print(f"Done!")
    
    print(f"\nOverall Statistics:")
    print(f"  SFX Compared: {len(sfx_with_data)} pairs")
    print(f"  SFX Indices: {sfx_with_data}")
    print(f"  Mean Amplitude Difference: {mean_overall_amp:.4f}")
    print(f"  Mean Spectrum Difference: {mean_overall_spec:.4f}")


if __name__ == '__main__':
    main()
