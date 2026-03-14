# tb_p8audio_sfx Test Case Documentation

Test cart: `tb_p8audio_sfx.p8`

Testbench range: **SFX 8–29** (full mode), **SFX 8 only** (quick mode via `+QUICK=1`).

SFX 0–7 are **custom instrument sources** (not directly played by the testbench, but
loaded on-demand when a test SFX references a custom waveform).

## Format Conventions

The `.p8` on-disk format differs from the in-memory format that `p8sfx_core_mux.sv`
actually processes. This document describes the **in-memory** representation, which is
what the hardware decodes. The testbench `load_p8_sfx` task performs the conversion.

### In-Memory Note Encoding (16-bit, little-endian)

| Bit(s) | Field | Range |
|--------|-------|-------|
| 15 | Custom waveform flag | 0–1 |
| 14–12 | Effect | 0–7 |
| 11–9 | Volume | 0–7 |
| 8–6 | Waveform | 0–7 |
| 5–0 | Pitch | 0–63 |

When the custom flag (bit 15) is set, the 3-bit waveform field selects which SFX
slot (0–7) provides the custom PCM waveform data.

### In-Memory Filter Byte (byte 64 of each 68-byte SFX slot)

| Bit(s) | Field | Meaning |
|--------|-------|---------|
| 0 | Editor mode | Not used by audio hardware |
| 1 | noiz | Noise injection filter |
| 2 | buzz | Buzz distortion filter |
| 7–3 | x (5-bit) | Combined encoding: detune = x%3, reverb = (x/3)%3, dampen = (x/9)%3 |

Filter levels: 0 = off, 1 = mild, 2 = strong.

### Speed / Duration

Speed is byte 65 (in-memory). Duration per note = speed × (1/128) seconds.
Total SFX duration = 32 notes × speed / 128 seconds.
At 22050 Hz with 183 samples per tick: total samples = 32 × speed × 183.

---

## Custom Instrument Sources (SFX 0–7)

These SFX slots define waveform data used by other SFX via the custom waveform flag.
They are not played directly by the testbench.

### SFX 0 — Custom Instrument: Multi-Waveform Arpeggio

- **Speed:** 8 (62.5 ms/note)
- **Filters:** none
- **Waveform instrument:** no (loop_start bit 7 = 0)
- **Active notes:** 27/32
- **Waveforms used:** sine (0), triangle (1), sawtooth (2)
- **Effects:** none
- **Pitch range:** c-0 to c-5

Plays ascending/descending octave arpeggios across three waveform types:
- Notes 0–10: Sine wave, c-0 → c-5 → c-0 (ascending then descending)
- Notes 12–20: Triangle wave, c-1 → c-5 → c-1
- Notes 22–28: Sawtooth wave, c-2 → c-5 → c-2

Referenced as custom instrument by: **SFX 1** (note 11) and **SFX 21** (notes 0, 6–9, 21).

### SFX 1 — Custom Instrument: Waveform Instrument with Effects

- **Speed:** 16 (125 ms/note)
- **Filters:** none
- **Waveform instrument:** YES (loop_start bit 7 = 1)
- **Bass flag:** 0 (speed is even)
- **Active notes:** 30/32
- **Waveforms used:** sine (0), custom SFX 0, custom SFX 3
- **Effects:** none, slide, vibrato, arp_fast, arp_slow

Complex multi-effect custom instrument definition:
- Notes 0–10: Sine with ascending pitch (c-0 → g#2), slide effects on notes 2–8
- Note 11: Custom SFX 0, pitch d-0, arp_slow
- Notes 12–21: Custom SFX 3 (square-mapped), descending c-5 → e-3, arp_fast/arp_slow, varied volumes
- Notes 22–31: Sine, vibrato (notes 24–27) and slide (notes 23, 28–30)

Referenced as custom instrument by: **SFX 21** (notes 2, 11–14, 22).

### SFX 2 — Custom Instrument: Waveform Instrument with Bass Flag

- **Speed:** 17 (132.8 ms/note)
- **Filters:** none
- **Waveform instrument:** YES (loop_start bit 7 = 1)
- **Bass flag:** 1 (speed is odd — enables bass mode for custom playback)
- **Active notes:** 27/32
- **Waveforms used:** sine (0), custom SFX 3
- **Effects:** none, slide, vibrato, fade_out, arp_fast, arp_slow

Similar to SFX 1 but with bass flag set (odd speed value). Tests the bass mode
custom instrument path in the hardware.
- Notes 0, 15–31: Sine with slide/vibrato effects
- Notes 2–14: Custom SFX 3 with arp_fast, arp_slow, fade_out at varied volumes and pitches

Referenced as custom instrument by: **SFX 21** (notes 4, 16–19, 23).

### SFX 3 — Custom Instrument: Minimal Sine

- **Speed:** 16, **Filters:** none, **Waveform instrument:** no
- **Active notes:** 1/32 — single c-2 sine at volume 5
- Referenced as custom instrument by: **SFX 1** and **SFX 2** (via custom waveform 3 = SFX 3)

### SFX 4–7 — Custom Instrument: Minimal Placeholders

Each identical to SFX 3: single c-2 sine at volume 5, speed 16, no filters.
Not referenced by any test SFX. Provide valid (non-empty) data for custom instrument
slots 4–7 in case the hardware reads them.

---

## Test Cases (SFX 8–21)

### SFX 8 — All 8 Standard Waveform Types

**Purpose:** Exercises every built-in waveform oscillator at two different pitches.

| Property | Value |
|----------|-------|
| Speed | 128 (1 s/note, ~34 s total) |
| Filters | none |
| Loop | none |
| Effects | none |
| Pitch | c-2 (24) and a-4 (57) |

Plays pairs of notes (low pitch, high pitch) for each waveform, separated by
silent notes:

| Notes | Waveform | Pitches |
|-------|----------|---------|
| 0–1 | 0 — sine | c-2, a-4 |
| 3–4 | 1 — triangle | c-2, a-4 |
| 6–7 | 2 — sawtooth | c-2, a-4 |
| 9–10 | 3 — square (long) | c-2, a-4 |
| 12–13 | 4 — pulse (short) | c-2, a-4 |
| 15–16 | 5 — organ | c-2, a-4 |
| 18–19 | 6 — noise | c-2, a-4 |
| 21–22 | 7 — phaser | c-2, a-4 |

**Features exercised:** All 8 waveform generators: sine, triangle, sawtooth, square,
pulse, organ, noise, phaser. Two pitches per waveform test frequency-dependent
behavior (phase increment calculation).

### SFX 9 — All 8 Note Effects

**Purpose:** Exercises every note effect type using sine waveform.

| Property | Value |
|----------|-------|
| Speed | 128 (1 s/note, ~34 s total) |
| Filters | none |
| Loop | none |
| Waveform | sine (0) only |

| Notes | Effect | Detail |
|-------|--------|--------|
| 0 | 0 — none | c-1 reference pitch |
| 1 | 1 — slide | c-2 (slides from previous note c-1) |
| 3 | 2 — vibrato | c-2 |
| 5 | 3 — drop | c-2 |
| 7 | 4 — fade_in | c-2 |
| 9 | 5 — fade_out | c-2 |
| 12–15 | 6 — arp_fast | 4-note group: c-0, c-1, c-2, c-3 (loops at speed 2) |
| 20–23 | 7 — arp_slow | 4-note group: c-0, c-1, c-2, c-3 (loops at speed 4) |

**Features exercised:** Slide (pitch interpolation), vibrato (pitch modulation),
drop (pitch drop to zero), fade_in / fade_out (volume envelope), arp_fast / arp_slow
(4-note arpeggio cycling). Arpeggio uses octave-spaced notes (c-0 through c-3) across
a 4-note group.

### SFX 10 — Noiz Filter

**Purpose:** Tests the noise injection filter.

| Property | Value |
|----------|-------|
| Speed | 128 |
| Filter byte | 0x03 — **noiz** enabled |
| Active notes | 2/32 |

| Note | Waveform | Pitch |
|------|----------|-------|
| 0 | sine | c-2 |
| 2 | noise | c-2 |

**Features exercised:** Noiz filter applied to sine (additive noise on a tonal
waveform) and noise (noise on noise — tests interaction). Only 2 active notes
keeps the test focused on filter behavior.

### SFX 11 — Buzz Filter × All Waveforms

**Purpose:** Tests buzz distortion across all 8 waveform types.

| Property | Value |
|----------|-------|
| Speed | 128 |
| Filter byte | 0x05 — **buzz** enabled |
| Pitch | c-2 (all notes) |
| Effects | none |

One note per waveform type (0–7), all at c-2 with volume 5, separated by silent notes.

**Features exercised:** Buzz filter changes waveform character (triangle → tilted
saw, saw → buzz saw, etc.) for every oscillator type.

### SFX 12 — Detune Level 1 × All Waveforms

**Purpose:** Tests mild detuning across all 8 waveform types.

| Property | Value |
|----------|-------|
| Speed | 128 |
| Filter byte | 0x09 — **detune=1** (bits 7:3 = 1) |
| Pitch | c-2 (all notes) |
| Effects | none |

Same note layout as SFX 11. One note per waveform, all at c-2.

**Features exercised:** Detune level 1 creates a chorus-like effect by slightly
detuning the oscillator. Tests detune modular arithmetic decoding (x=1, 1%3=1).

### SFX 13 — Detune Level 2 × All Waveforms

**Purpose:** Tests strong detuning across all 8 waveform types.

| Property | Value |
|----------|-------|
| Speed | 128 |
| Filter byte | 0x11 — **detune=2** (bits 7:3 = 2) |
| Pitch | c-2 (all notes) |
| Effects | none |

Same note layout as SFX 11–12.

**Features exercised:** Detune level 2 (stronger pitch offset). Tests decoding
(x=2, 2%3=2).

### SFX 14 — Reverb Level 1 × All Waveforms

**Purpose:** Tests mild reverb across all 8 waveform types.

| Property | Value |
|----------|-------|
| Speed | 128 |
| Filter byte | 0x19 — **reverb=1** (bits 7:3 = 3) |
| Pitch | c-2 (all notes) |
| Effects | none |

Same note layout as SFX 11–13.

**Features exercised:** Reverb level 1 (short delay line, ~16.6 ms tap at
REVERB_TAPS_SHORT=366 samples). Tests reverb delay buffer read/write and
mix-back. Decoding: x=3, (3/3)%3=1.

### SFX 15 — Reverb Level 2 × All Waveforms

**Purpose:** Tests strong reverb across all 8 waveform types.

| Property | Value |
|----------|-------|
| Speed | 128 |
| Filter byte | 0x31 — **reverb=2** (bits 7:3 = 6) |
| Pitch | c-2 (all notes) |
| Effects | none |

Same note layout.

**Features exercised:** Reverb level 2 (longer delay line, ~33.2 ms tap at
REVERB_TAPS_LONG=732 samples). Decoding: x=6, (6/3)%3=2.

### SFX 16 — Dampen Level 1 × All Waveforms

**Purpose:** Tests mild low-pass dampen filter across all 8 waveform types.

| Property | Value |
|----------|-------|
| Speed | 128 |
| Filter byte | 0x49 — **dampen=1** (bits 7:3 = 9) |
| Pitch | c-2 (all notes) |
| Effects | none |

Same note layout.

**Features exercised:** Dampen level 1 (IIR low-pass filter with mild coefficient).
Tests dampen filter alpha lookup and multiply-accumulate. Decoding: x=9, (9/9)%3=1.

### SFX 17 — Dampen Level 2 × All Waveforms

**Purpose:** Tests strong low-pass dampen filter across all 8 waveform types.

| Property | Value |
|----------|-------|
| Speed | 128 |
| Filter byte | 0x91 — **dampen=2** (bits 7:3 = 18) |
| Pitch | c-2 (all notes) |
| Effects | none |

Same note layout.

**Features exercised:** Dampen level 2 (stronger low-pass, more aggressive
high-frequency attenuation). Decoding: x=18, (18/9)%3=2.

### SFX 18 — Pitch Range (Octave Sweep)

**Purpose:** Tests pitch accuracy across the full 5-octave range.

| Property | Value |
|----------|-------|
| Speed | 16 (125 ms/note, ~4.25 s total) |
| Filters | none |
| Waveform | sine (0) only |
| Effects | none |

| Note | Pitch |
|------|-------|
| 0 | c-0 (0) |
| 1 | c-1 (12) |
| 2 | c-2 (24) |
| 3 | c-3 (36) |
| 4 | c-4 (48) |
| 5 | c-5 (60) |

**Features exercised:** Phase increment accuracy at 6 octaves (c-0 through c-5),
each doubling in frequency. Tests the pitch lookup table across its full range.
Faster speed (16 vs 128) checks timing at shorter note durations.

### SFX 19 — Volume Levels (All 7 Non-Zero Volumes)

**Purpose:** Tests all discrete volume levels and volume scaling.

| Property | Value |
|----------|-------|
| Speed | 16 |
| Filters | none |
| Waveform | sine (0) only |
| Effects | none |

| Notes | Pitch | Volumes |
|-------|-------|---------|
| 0–6 | c-2 | 7, 6, 5, 4, 3, 2, 1 (descending) |
| 8–14 | c-1 | 1, 2, 3, 4, 5, 6, 7 (ascending) |

**Features exercised:** All 7 non-zero volume levels (1–7). Volume scaling path
(`sample * eff_vol / 224`). Two pitch groups verify volume is independent of pitch.
Descending then ascending pattern helps identify off-by-one or nonlinear volume errors.

### SFX 20 — Note Loop

**Purpose:** Tests the SFX note loop mechanism.

| Property | Value |
|----------|-------|
| Speed | 16 |
| Filters | none |
| Loop | **start=8, end=15** |
| Waveform | sine (0) only |
| Effects | none |

| Notes | Pitch | Role |
|-------|-------|------|
| 0, 2, 4, 6 | c-1 | Pre-loop (notes before loop region) |
| 8–10, 12–14, 16 | c-2 through c-5 | Loop body (notes 8–15 repeat) |

**Features exercised:** SFX loop start/end registers. After reaching note 15,
playback jumps back to note 8 and repeats. Verifies loop_start and loop_end
header decoding from bytes 66–67. The testbench captures a fixed number of
samples (32 × speed × 183), so the loop repeats multiple times within the
capture window.

### SFX 21 — Custom Waveform Instruments (PCM)

**Purpose:** Tests custom waveform playback using SFX 0, 1, and 2 as instrument
sources.

| Property | Value |
|----------|-------|
| Speed | 128 (1 s/note, ~34 s total) |
| Filters | none |
| Loop | none |
| Pitch | c-1 (all notes) |
| Effects | none |

All notes use the **custom waveform flag** (bit 15 = 1). The 3-bit waveform field
selects which SFX slot provides the PCM data:

| Notes | Custom Source | Source Description |
|-------|-------------|---------------------|
| 0, 6–9, 21 | SFX 0 (waveform 0) | Multi-waveform arpeggio (sine/tri/saw) |
| 2, 11–14, 22 | SFX 1 (waveform 1) | Waveform instrument with effects |
| 4, 16–19, 23 | SFX 2 (waveform 2) | Waveform instrument with bass flag |

Each custom instrument is tested with:
- A single introductory note (notes 0, 2, 4)
- A sustained 4-note block (notes 6–9, 11–14, 16–19)
- A final single note cycling through all three (notes 21–23)

**Features exercised:**
- Custom waveform flag decoding (bit 15 of in-memory note word)
- Even/odd context pairing (even context synthesises custom instrument, odd context
  reads its PCM output)
- SFX 0 as plain custom instrument (no waveform instrument flag)
- SFX 1 as waveform instrument (loop_start bit 7 = 1, bass_flag = 0)
- SFX 2 as waveform instrument with bass mode (loop_start bit 7 = 1, bass_flag = 1,
  speed = 17 which is odd)
- Phase multiplication path (`phase_mult` in p8sfx_core_mux.sv)
- Inter-context PCM data transfer

---

## Waveform Isolation Tests (SFX 22–29)

SFX 22–29 each play a single note (c-2, volume 5, no effect) with one waveform
type, speed=1, and no filters. These are designed to isolate individual waveform
generators for debugging regressions.

| SFX | Waveform | In-Memory Note Word |
|-----|----------|--------------------|
| 22 | 0 — sine | 0x0a18 |
| 23 | 1 — triangle | 0x0a58 |
| 24 | 2 — sawtooth | 0x0a98 |
| 25 | 3 — square (long) | 0x0ad8 |
| 26 | 4 — pulse (short) | 0x0b18 |
| 27 | 5 — organ | 0x0b58 |
| 28 | 6 — noise | 0x0b98 |
| 29 | 7 — phaser | 0x0bd8 |

All share:
- **Speed:** 1 (shortest possible, 7.8 ms/note, ~0.27 s total)
- **Filter byte:** 0x01 (no audio filters)
- **Loop:** none
- **Active notes:** 1/32
- **Pitch:** c-2 (24)
- **Volume:** 5
- **Effect:** none

---

## Feature Coverage Summary

| Feature | Tested By |
|---------|-----------|
| Waveform: sine | SFX 8, 9, 10, 18, 19, 20, **22** |
| Waveform: triangle | SFX 8, 11–17, **23** |
| Waveform: sawtooth | SFX 8, 11–17, **24** |
| Waveform: square (long) | SFX 8, 11–17, **25** |
| Waveform: pulse (short) | SFX 8, 11–17, **26** |
| Waveform: organ | SFX 8, 11–17, **27** |
| Waveform: noise | SFX 8, 10, 11–17, **28** |
| Waveform: phaser | SFX 8, 11–17, **29** |
| Effect: none | SFX 8, 10–29 |
| Effect: slide | SFX 9 |
| Effect: vibrato | SFX 9 |
| Effect: drop | SFX 9 |
| Effect: fade_in | SFX 9 |
| Effect: fade_out | SFX 9 |
| Effect: arp_fast | SFX 9 |
| Effect: arp_slow | SFX 9 |
| Filter: noiz | SFX 10 |
| Filter: buzz | SFX 11 |
| Filter: detune=1 | SFX 12 |
| Filter: detune=2 | SFX 13 |
| Filter: reverb=1 | SFX 14 |
| Filter: reverb=2 | SFX 15 |
| Filter: dampen=1 | SFX 16 |
| Filter: dampen=2 | SFX 17 |
| Pitch range (full) | SFX 18 (c-0 to c-5) |
| Volume levels (1–7) | SFX 19 |
| Note looping | SFX 20 (loop 8–15) |
| Custom waveform (PCM) | SFX 21 (sources: SFX 0, 1, 2) |
| Waveform instrument flag | SFX 1, 2 (via SFX 21) |
| Bass flag (odd speed) | SFX 2 (via SFX 21) |
| Waveform isolation (1 note) | SFX 22–29 (one waveform per SFX) |

### Notable Gaps

- No test combines multiple filters (e.g., buzz + reverb, detune + dampen).
- Effects are only tested on sine; no test applies effects to non-sine waveforms.
- Custom instruments are only tested with effect=none; no custom + effect combination.
- No test for speed=0 (maps to effective speed 1) edge case.
- Filter levels are tested at 1 and 2 only; the combined encoding allows setting
  multiple filter types simultaneously (e.g., detune=1 + reverb=2 + dampen=1 would
  be x = 1 + 3×2 + 9×1 = 16, filter byte bits 7:3 = 16), but this is not tested.
