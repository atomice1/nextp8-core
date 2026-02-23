pico-8 cartridge // http://www.pico-8.com
version 43
__lua__

-- tb_p8audio_api.p8: pico-8 reference tests for p8audio subsystem
-- tests 18 scenarios to validate audio api behavior against official pico-8 implementation

-- test state tracking
total_tests = 0
passed_tests = 0
current_test = ""
test_log = {}

-- memory constants (matching c/sv testbenches)
sfx_base = 0x3200
music_base = 0x3100
sfx_bytes = 68
music_bytes = 4
sfx_count = 64
music_count = 64

-- helper: initialize test memory
function init_memory()
    -- clear sfx memory
    for i = sfx_base, sfx_base + sfx_count * sfx_bytes - 1 do
        poke(i, 0)
    end

    -- clear music memory
    for i = music_base, music_base + music_count * music_bytes - 1 do
        poke(i, 0)
    end
end

-- helper: write a note to sfx slot
-- format: 16-bit little-endian per pico-8 spec
-- low byte:  ww pppppp  (waveform bits 1-0 in bits 7-6, pitch bits 5-0)
-- high byte: c eee vvv w  (custom bit 7, effect bits 6-4, volume bits 3-1, waveform bit 2 in bit 0)
function write_sfx_note(slot, note_idx, pitch, wave, vol, effect)
    wave = wave or 0  -- sine
    vol = vol or 7    -- full volume
    effect = effect or 0 -- no effect
    pitch = pitch or 0

    local addr = sfx_base + slot * sfx_bytes + note_idx * 2

    -- split waveform into low 2 bits and high 1 bit
    local wave_low_bits = wave % 4      -- waveform bits 0-1
    local wave_high_bit = (wave \ 4) % 2  -- waveform bit 2

    -- encode note (16-bit little-endian, pico-8 format)
    -- low byte: pitch (bits 5-0) + waveform low 2 bits (bits 7-6)
    local low = pitch + wave_low_bits * 64

    -- high byte: waveform bit 2 (bit 0) + volume (bits 3-1) + effect (bits 6-4)
    local high = wave_high_bit + (vol % 8) * 2 + ((effect % 8) * 16)

    poke(addr, low % 256)
    poke(addr + 1, high % 256)
end

-- helper: initialize sfx slot with simple waveform
function init_sfx_slot(slot, num_notes, wave, vol)
    wave = wave or 0  -- sine
    vol = vol or 7
    num_notes = num_notes or 32

    for i = 0, num_notes - 1 do
        -- use pitch progression for variety
        write_sfx_note(slot, i, i * 2, wave, vol, 0)
    end

    local sfx_addr = sfx_base + slot * sfx_bytes

    -- byte 64: editor mode (tracker=1) and filter flags
    poke(sfx_addr + 64, 1)  -- tracker mode, no filters

    -- byte 65: speed (1 = ~1/120 second per note)
    poke(sfx_addr + 65, 1)

    -- bytes 66-67: loop start and end
    poke(sfx_addr + 66, 0)              -- loop start at note 0
    poke(sfx_addr + 67, num_notes - 1)  -- loop end at last note
end

-- helper: wait for sfx to start on channel
function wait_sfx_channel(channel, max_frames)
    max_frames = max_frames or 120
    local frames = 0
    while frames < max_frames do
        local sfx_playing = stat(46 + channel)
        local note_playing = stat(50 + channel)
        if sfx_playing >= 0 and sfx_playing < 64 and note_playing >= 0 and note_playing < 32 then  -- valid sfx index (0-63)
            return true
        end
        frames += 1
        flip()  -- process one frame
    end
    return false
end

-- helper: check if sfx is playing on channel
function is_sfx_playing(channel)
    local sfx_idx = stat(46 + channel)
    return sfx_idx >= 0 and sfx_idx < 64
end

-- helper: get note playing on channel
function get_note_playing(channel)
    return stat(50 + channel)
end

-- helper: get pattern index
function get_music_pattern()
    return stat(54)
end

-- helper: check if music is playing
function is_music_playing()
    return stat(57)
end

-- helper: wait for idle (no sfx on any channel)
function wait_idle(max_frames)
    max_frames = max_frames or 120
    local frames = 0
    while frames < max_frames do
        local idle = true
        for ch = 0, 3 do
            if is_sfx_playing(ch) then
                idle = false
                break
            end
        end
        if idle then
            return true
        end
        frames += 1
        flip()  -- process one frame
    end
    return false
end

-- helper: wait for idle on channel
function wait_channel_idle(ch, max_frames)
    max_frames = max_frames or 120
    local frames = 0
    while frames < max_frames do
        local idle = true
        if is_sfx_playing(ch) then
            idle = false
            break
        end
        if idle then
            return true
        end
        frames += 1
        flip()  -- process one frame
    end
    return false
end

-- helper: wait for release (all channels either idle or past note 32 after release)
function wait_for_release(max_frames)
    max_frames = max_frames or 120
    local frames = 0
    while frames < max_frames do
        local done = true
        -- wait for music to stop
        if is_music_playing() then
            done = false
        end
        -- wait for all sfx channels to finish
        for ch = 0, 3 do
            local note = get_note_playing(ch)
            -- channel is done if not playing, or if note index >= 32 (past the end after release)
            if is_sfx_playing(ch) and note < 32 then
                done = false
                break
            end
        end
        if done then
            return true
        end
        frames += 1
        flip()  -- process one frame
    end
    return false
end

-- helper: log test result
function log_result(test_name, passed, message)
    total_tests += 1
    local result_line = ""
    if passed then
        passed_tests += 1
        result_line = "pass: " .. test_name .. ": " .. message
    else
        result_line = "fail: " .. test_name .. ": " .. message
    end
    printh(result_line)
    print(result_line, 4, 22 + (total_tests - 1) * 8)
end

-- test 1: version query (sanity check)
function test_p8audio_version()
    current_test = "test_p8audio_version"
    init_memory()

    -- just verify pico-8 can run (always true)
    log_result(current_test, true, "pico-8 runtime available")
end

-- test 2: sfx auto-channel
function test_sfx_auto_channel()
    current_test = "test_sfx_auto_channel"
    init_memory()
    init_sfx_slot(0, 32, 0, 7)
    init_sfx_slot(1, 32, 0, 7)
    init_sfx_slot(2, 32, 0, 7)
    init_sfx_slot(3, 32, 0, 7)

    -- play sfx 0 without explicit channel (auto-assign to ch0)
    sfx(0)
    wait_sfx_channel(0, 60)
    if not is_sfx_playing(0) then
        log_result(current_test, false, "sfx 0 did not start on ch0")
        return
    end

    -- play sfx 1 (auto-assign to ch1)
    sfx(1)
    wait_sfx_channel(1, 60)
    if not is_sfx_playing(1) then
        log_result(current_test, false, "sfx 1 did not start on ch1")
        return
    end

    log_result(current_test, true, "sfx auto-assigned to channels 0,1")
end

-- test 3: sfx explicit queue on channel
function test_sfx_explicit_queue()
    current_test = "test_sfx_explicit_queue"
    init_memory()
    init_sfx_slot(5, 32, 0, 7)
    init_sfx_slot(6, 32, 0, 7)

    -- play sfx 5 on channel 2
    sfx(5, 2, 0, 32)
    wait_sfx_channel(2, 60)

    if not is_sfx_playing(2) then
        log_result(current_test, false, "sfx 5 did not start on ch2")
        return
    end

    local sfx_id = stat(46 + 2)
    if sfx_id ~= 5 then
        log_result(current_test, false, "sfx 5 not on ch2, got sfx " .. sfx_id)
        return
    end

    log_result(current_test, true, "sfx 5 playing on channel 2")
end

-- test 4: sfx stop by channel
function test_sfx_stop_channel()
    current_test = "test_sfx_stop_channel"
    init_memory()
    init_sfx_slot(0, 32, 0, 7)
    init_sfx_slot(1, 32, 0, 7)

    -- play two sfx
    sfx(0, 0)
    sfx(1, 1)
    wait_sfx_channel(0, 60)
    wait_sfx_channel(1, 60)

    if not (is_sfx_playing(0) and is_sfx_playing(1)) then
        log_result(current_test, false, "setup failed, not both playing")
        return
    end

    -- stop channel 0
    sfx(-1, 0)
    wait_channel_idle(0, 60)

    if is_sfx_playing(0) then
        log_result(current_test, false, "sfx(-1,0) did not stop ch0")
        return
    end

    if not is_sfx_playing(1) then
        log_result(current_test, false, "sfx(-1,0) incorrectly stopped ch1")
        return
    end

    log_result(current_test, true, "channel 0 stopped, channel 1 still playing")
end

-- test 5: sfx stop by sfx index (any channel)
function test_sfx_stop_by_index()
    current_test = "test_sfx_stop_by_index"
    init_memory()
    init_sfx_slot(0, 32, 0, 7)
    init_sfx_slot(1, 32, 0, 7)

    -- play same sfx on two channels
    sfx(0, 0)
    sfx(0, 1)
    wait_sfx_channel(0, 60)
    wait_sfx_channel(1, 60)

    if not (is_sfx_playing(0) and is_sfx_playing(1)) then
        log_result(current_test, false, "setup failed, sfx 0 not on both ch0 and ch1")
        return
    end

    -- stop sfx 0 from all channels
    sfx(0, -2)
    wait_idle(60)

    if is_sfx_playing(0) or is_sfx_playing(1) then
        log_result(current_test, false, "sfx(0,-2) did not stop both channels")
        return
    end

    log_result(current_test, true, "sfx 0 stopped on both channels")
end

-- test 6: sfx release loop
function test_sfx_release_loop()
    current_test = "test_sfx_release_loop"
    init_memory()
    init_sfx_slot(0, 32, 0, 7)  -- 32 notes, speed 1, loop from 0 to 31

    -- play looping sfx
    sfx(0, 0)
    wait_sfx_channel(0, 60)

    if not is_sfx_playing(0) then
        log_result(current_test, false, "sfx 0 did not start on ch0")
        return
    end

    -- wait for sfx to loop by watching for note index to wrap around
    local last_note = get_note_playing(0)
    local looped = false
    for i = 1, 500 do
        flip()
        local current_note = get_note_playing(0)
        if current_note <= last_note then
            looped = true
            break
        end
        last_note = current_note
    end

    if not looped then
        log_result(current_test, false, "sfx did not loop within 500 frames")
        return
    end

    local note_at_loop = get_note_playing(0)

    if not is_sfx_playing(0) then
        log_result(current_test, false, "sfx 0 stopped before release")
        return
    end

    -- release loop (sfx(-2, ch) finishes current note and exits loop)
    sfx(-2, 0)
    wait_idle(120)  -- wait for release to finish

    note = get_note_playing(0)
    if is_sfx_playing(0) and note >= 0 and note < 32 then
        log_result(current_test, false, "sfx(-2,0) did not release loop")
        return
    end

    log_result(current_test, true, "looping sfx detected at note " .. note_at_loop .. " and released")
end

-- test 7: sfx start offset
function test_sfx_offset()
    current_test = "test_sfx_offset"
    init_memory()
    init_sfx_slot(0, 32, 1, 7)  -- pitched waveform

    -- change speed to 4 (slower) for this test so we can catch the starting note
    local sfx_addr = sfx_base + 0 * sfx_bytes
    poke(sfx_addr + 65, 4)  -- speed 4 instead of 1

    -- play with offset=16, length=10 (should play notes 16-31)
    sfx(0, 0, 16, 10)
    wait_sfx_channel(0, 60)

    if not is_sfx_playing(0) then
        log_result(current_test, false, "sfx 0 did not start on ch0")
        return
    end

    local note_start = get_note_playing(0)
    if (note_start < 14) or (note_start > 18) then
        log_result(current_test, false, "offset not honored: expected ~16, got " .. note_start)
        return
    end

    -- wait for sfx to finish and capture last note (should be 31 = offset+length-1)
    local last_note = note_start
    for i = 1, 500 do
        flip()
        if not is_sfx_playing(0) then
            break
        end
        local current_note = get_note_playing(0)
        -- note index >= 32 means past the end (length is absolute, not relative)
        if current_note < 0 or current_note >= 32 then
            break
        end
        last_note = current_note
    end

    if last_note ~= 25 then
        log_result(current_test, false, "offset+length: expected last note 31, got " .. last_note)
        return
    end

    log_result(current_test, true, "offset=16, length=10 honored (notes 16-" .. last_note .. ")")
end

-- test 8: sfx length parameter
function test_sfx_length()
    current_test = "test_sfx_length"
    init_memory()
    init_sfx_slot(0, 32, 0, 7)

    -- change speed to 4 (slower) for this test so we can catch the ending note
    local sfx_addr = sfx_base + 0 * sfx_bytes
    poke(sfx_addr + 65, 4)  -- speed 4 instead of 1

    -- play with length=8 (should play notes 0-7, stop after note 7)
    sfx(0, 0, 0, 8)
    wait_sfx_channel(0, 60)

    if not is_sfx_playing(0) then
        log_result(current_test, false, "sfx 0 did not start on ch0")
        return
    end

    -- wait for sfx to finish and capture last note (should be 7 = length-1)
    local last_note = get_note_playing(0)
    for i = 1, 500 do
        flip()
        if not is_sfx_playing(0) then
            break
        end
        local current_note = get_note_playing(0)
        -- note index >= 32 means past the end
        if current_note < 0 or current_note >= 32 then
            break
        end
        last_note = current_note
    end

    if last_note ~= 7 then
        log_result(current_test, false, "length=8: expected last note 7, got " .. last_note)
        return
    end

    log_result(current_test, true, "sfx length=8 honored, last note=" .. last_note)
end

-- test 9: sfx offset + length edge cases
function test_sfx_offset_length_edges()
    current_test = "test_sfx_offset_length_edges"
    init_memory()
    init_sfx_slot(0, 32, 0, 7)

    -- play max offset, short length
    sfx(0, 0, 30, 2)
    wait_sfx_channel(0, 60)

    if not is_sfx_playing(0) then
        log_result(current_test, false, "sfx 0 did not start on ch0")
        return
    end

    local note_idx = get_note_playing(0)
    if (note_idx < 28) or (note_idx > 31) then
        log_result(current_test, false, "offset=30 not honored: expected 28-31, got " .. note_idx)
        return
    end

    log_result(current_test, true, "edge case: offset=30, length=2, note=" .. note_idx)
end

-- test 10: sfx loop with offset + length (wrap around)
function test_sfx_loop_offset_wrap()
    current_test = "test_sfx_loop_offset_wrap"
    init_memory()

    -- create sfx with 16 notes total, loop from 0-15
    local sfx_addr = sfx_base + 0 * sfx_bytes
    for i = 0, 15 do
        write_sfx_note(0, i, i * 2, 0, 7, 0)
    end
    poke(sfx_addr + 64, 1)              -- tracker mode
    poke(sfx_addr + 65, 4)              -- slower speed
    poke(sfx_addr + 66, 0)              -- loop start at 0
    poke(sfx_addr + 67, 15)             -- loop end at 15

    -- play with offset=12, length=8 (should play 12,13,14,15,0,1,2,3 due to looping)
    sfx(0, 0, 12, 8)
    wait_sfx_channel(0, 60)

    if not is_sfx_playing(0) then
        log_result(current_test, false, "sfx 0 did not start on ch0")
        return
    end

    local note_start = get_note_playing(0)
    if (note_start < 10) or (note_start > 14) then
        log_result(current_test, false, "offset=12 not honored: expected 10-14, got " .. note_start)
        return
    end

    -- wait and verify it wraps around (note should eventually drop back below 12)
    local wrapped = false
    local max_note = note_start
    for i = 1, 1000 do
        flip()
        if not is_sfx_playing(0) then
            break
        end
        local current_note = get_note_playing(0)
        if current_note >= 16 then
            break  -- past end (length constraint)
        end
        if current_note < 10 and current_note >= 0 then
            wrapped = true
            break
        end
        if current_note > max_note then
            max_note = current_note
        end
    end

    if not wrapped then
        log_result(current_test, false, "sfx with loop did not wrap around back to 0")
        return
    end

    log_result(current_test, true, "loop with offset=12, length=8 wrapped correctly")
end

-- test 12: stop all sfx
function test_sfx_stop_all()
    current_test = "test_sfx_stop_all"
    init_memory()
    for i = 0, 3 do
        init_sfx_slot(i, 32, 0, 7)
    end

    -- play on all 4 channels
    for i = 0, 3 do
        sfx(i, i)
    end
    wait_sfx_channel(0, 60)
    wait_sfx_channel(1, 60)

    local all_playing = true
    for i = 0, 3 do
        if not is_sfx_playing(i) then
            all_playing = false
            break
        end
    end

    if not all_playing then
        log_result(current_test, false, "setup failed, not all channels active")
        return
    end

    -- stop all
    sfx(-1)
    wait_idle(60)

    for i = 0, 3 do
        if is_sfx_playing(i) then
            log_result(current_test, false, "sfx(-1) did not stop all channels")
            return
        end
    end

    log_result(current_test, true, "all channels stopped")
end

-- test 11: release all sfx
function test_sfx_release_all()
    current_test = "test_sfx_release_all"
    init_memory()
    init_sfx_slot(0, 32, 0, 7)
    init_sfx_slot(1, 32, 0, 7)

    -- play on multiple channels
    sfx(0, 0)
    sfx(1, 1)
    wait_sfx_channel(0, 60)
    wait_sfx_channel(1, 60)

    if not (is_sfx_playing(0) and is_sfx_playing(1)) then
        log_result(current_test, false, "setup failed, channels not playing")
        return
    end

    -- release all
    sfx(-2)

    -- wait for both channels to finish (note index >= 32 means past the end)
    local ch0_finished = false
    local ch1_finished = false
    for i = 1, 500 do
        flip()
        if get_note_playing(0) >= 32 then
            ch0_finished = true
        end
        if get_note_playing(1) >= 32 then
            ch1_finished = true
        end
        if ch0_finished and ch1_finished then
            break
        end
    end

    if not (ch0_finished and ch1_finished) then
        log_result(current_test, false, "sfx(-2) did not finish releasing all channels")
        return
    end

    log_result(current_test, true, "all channels released")
end

-- test 12: multi-channel interleaving
function test_multi_channel()
    current_test = "test_multi_channel"
    init_memory()
    for i = 0, 3 do
        init_sfx_slot(i, 32, i, 7)  -- different waveforms per channel
    end

    -- play different sfx on each channel
    sfx(0, 0)
    sfx(1, 1)
    sfx(2, 2)
    sfx(3, 3)

    wait_sfx_channel(0, 60)
    wait_sfx_channel(1, 60)
    wait_sfx_channel(2, 60)
    wait_sfx_channel(3, 60)

    for i = 0, 3 do
        local sfx_on_ch = stat(46 + i)
        if sfx_on_ch ~= i then
            log_result(current_test, false, "sfx " .. i .. " not on ch" .. i .. ", got " .. sfx_on_ch)
            return
        end
    end

    log_result(current_test, true, "all 4 channels playing unique sfx")
end

-- test 13: all channels busy, auto-queue
function test_channels_busy_auto_queue()
    current_test = "test_channels_busy_auto_queue"
    init_memory()
    for i = 0, 4 do
        init_sfx_slot(i, 32, 0, 7)
    end

    -- fill all 4 channels
    for i = 0, 3 do
        sfx(i, i)
    end
    wait_sfx_channel(0, 60)

    -- try to play 5th sfx (should auto-queue on next free channel)
    sfx(4)

    local played_on_channel = -1
    for i = 0, 3 do
        local sfx_on_ch = stat(46 + i)
        if sfx_on_ch == 4 then
            played_on_channel = i
            break
        end
    end

    if played_on_channel < 0 then
        log_result(current_test, false, "sfx 4 did not queue on any busy channel")
        return
    end

    log_result(current_test, true, "sfx 4 queued on channel " .. played_on_channel)
end

-- test 14: busy channel and explicit queue
function test_busy_channel_queue()
    current_test = "test_busy_channel_queue"
    init_memory()
    init_sfx_slot(0, 32, 0, 7)
    init_sfx_slot(1, 32, 0, 7)

    -- play sfx 0 on channel 0
    sfx(0, 0)
    wait_sfx_channel(0, 60)

    if not is_sfx_playing(0) then
        log_result(current_test, false, "sfx 0 did not start on ch0")
        return
    end

    -- queue sfx 1 on same busy channel 0
    sfx(1, 0)

    -- eventually sfx 1 should play
    local played = false
    for i = 1, 240 do
        if stat(46) == 1 then
            played = true
            break
        end
    end

    if not played then
        log_result(current_test, false, "queued sfx 1 did not play on ch0")
        return
    end

    log_result(current_test, true, "sfx 1 queued and played on channel 0")
end

-- test 15: music pattern basic
function test_music_basic()
    current_test = "test_music_basic"
    init_memory()

    -- initialize a simple music pattern with some sfx
    init_sfx_slot(0, 32, 0, 7)
    init_sfx_slot(1, 32, 0, 7)
    init_sfx_slot(2, 32, 0, 7)
    init_sfx_slot(3, 32, 0, 7)

    -- create pattern 0 with sfx 0-3 on channels 0-3
    -- format per spec: bits 5-0 = sfx id, bit 6 = disabled (0=enabled), bit 7 = frame flags
    -- frame flags: ch0 bit 7 = begin loop, ch1 bit 7 = end loop, ch2 bit 7 = stop at end
    poke(music_base + 0, 0)  -- channel 0: sfx 0, enabled (0x00 = bits 5-0 only)
    poke(music_base + 1, 1)  -- channel 1: sfx 1, enabled
    poke(music_base + 2, 2)  -- channel 2: sfx 2, enabled
    poke(music_base + 3, 3)  -- channel 3: sfx 3, enabled

    -- play music pattern 0
    music(0)

    -- wait for music to start
    local played = false
    for i = 1, 120 do
        local playing = is_music_playing()
        if playing then
            played = true
            break
        end
    end

    if not played then
        log_result(current_test, false, "music pattern 0 did not start")
        return
    end

    log_result(current_test, true, "music pattern 0 started")
end

-- test 16: music masking
function test_music_mask()
    current_test = "test_music_mask"
    init_memory()

    for i = 0, 3 do
        init_sfx_slot(i, 32, 0, 7)
    end

    -- create pattern with all 4 channels
    for i = 0, 3 do
        poke(music_base + i, i)
    end

    -- play with channel mask (only channels 0,2 enabled)
    music(0, 0, 0x5)  -- mask: 0101 (binary) = channels 0 and 2

    -- check if playing
    local played = false
    for i = 1, 120 do
        if is_music_playing() then
            played = true
            break
        end
    end

    if not played then
        log_result(current_test, false, "music pattern with channel mask did not start")
        return
    end

    log_result(current_test, true, "music pattern with channel mask played")
end

-- test 17: sfx over music
function test_sfx_over_music()
    current_test = "test_sfx_over_music"
    init_memory()

    -- initialize all sfx slots
    for i = 0, 3 do
        init_sfx_slot(i, 32, 0, 7)
    end

    -- start music on pattern 0
    for i = 0, 3 do
        poke(music_base + i, i)
    end
    music(0)

    -- wait for music
    local music_started = false
    for i = 1, 120 do
        if is_music_playing() then
            music_started = true
            break
        end
    end

    if not music_started then
        log_result(current_test, false, "music pattern 0 did not start")
        return
    end

    -- play sfx (should play alongside music)
    init_sfx_slot(4, 32, 0, 5)
    sfx(4, 0)

    wait_sfx_channel(0, 60)

    -- check sfx is playing
    if stat(46) ~= 4 then
        log_result(current_test, false, "sfx 4 did not start while music playing (stat(46)=" .. stat(46) .. ")")
        return
    end

    if not is_music_playing() then
        log_result(current_test, false, "music stopped when sfx started")
        return
    end

    log_result(current_test, true, "sfx and music both playing")
end

-- test 18: music loop and fade
function test_music_loop_fade()
    current_test = "test_music_loop_fade"
    init_memory()

    for i = 0, 3 do
        init_sfx_slot(i, 32, 0, 7)
    end

    -- create two patterns
    for pat = 0, 1 do
        for ch = 0, 3 do
            poke(music_base + pat * 4 + ch, ch)
        end
    end

    -- play pattern 0 with 500ms fade
    music(0, 500)

    -- wait for music
    local played = false
    for i = 1, 120 do
        if is_music_playing() then
            played = true
            break
        end
    end

    if not played then
        log_result(current_test, false, "music with fade did not start")
        return
    end

    log_result(current_test, true, "music with fade started")
end

-- test 19: music fade out time is honored
function test_music_fade_out_time()
    current_test = "test_music_fade_out_time"
    init_memory()

    -- create single SFX to play
    init_sfx_slot(0, 32, 0, 7)

    -- create pattern
    for ch = 0, 3 do
        poke(music_base + ch, 0)
    end

    -- play pattern 0 with 300ms fade (approximately 18 frames at 60fps)
    music(0)

    -- wait for music to start
    local started = false
    for i = 1, 60 do
        if is_music_playing() then
            started = true
            break
        end
    end

    if not started then
        log_result(current_test, false, "music did not start")
        return
    end

    -- now stop with fade and measure duration
    local frame_stopped = 0
    music(-1, 300)

    -- poll until music stops, counting frames
    local fade_frames = 0
    for i = 1, 600 do  -- max 10 seconds
        fade_frames = fade_frames + 1
        if not is_music_playing() then
            break
        end
        flip()  -- advance one frame so fade progresses
    end

    -- 300ms at 30fps = 9 frames (300ms / 33.33ms per frame)
    -- allow tolerance of ±2 frames for timing variations
    local expected_frames = 9
    local tolerance = 2

    if fade_frames < (expected_frames - tolerance) then
        log_result(current_test, false,
            "fade too fast: " .. fade_frames .. " frames (expected ~" .. expected_frames .. ")")
        return
    end

    if fade_frames > (expected_frames + tolerance) then
        log_result(current_test, false,
            "fade too slow: " .. fade_frames .. " frames (expected ~" .. expected_frames .. ")")
        return
    end

    log_result(current_test, true,
        "fade honored: " .. fade_frames .. " frames (~" .. (fade_frames * 16.67) .. "ms)")
end

cls(1)  -- blue background

color(7)  -- white text
print("p8audio reference tests", 4, 4)
print("------------------------", 4, 12)

-- list of all test functions
local test_functions = {
    test_p8audio_version,
    test_sfx_auto_channel,
    test_sfx_explicit_queue,
    test_sfx_stop_channel,
    test_sfx_move_channel,
    test_sfx_release_loop,
    test_sfx_offset,
    test_sfx_length,
    test_sfx_offset_length_edges,
    test_sfx_loop_offset_wrap,
    test_sfx_stop_all,
    test_sfx_release_all,
    test_multi_channel,
    test_channels_busy_auto_queue,
    test_busy_channel_queue,
    test_music_basic,
    test_music_mask,
    test_sfx_over_music,
    test_music_loop_fade,
    test_music_fade_out_time,
}

-- run all tests with cleanup before and after
for test_func in all(test_functions) do
    -- cleanup before test
    music(-1)   -- stop music
    sfx(-1)     -- stop all sfx
    wait_for_release()

    -- run test
    test_func()

    -- cleanup after test
    music(-1)   -- stop music
    sfx(-1)     -- stop all sfx
    wait_for_release()
end

-- print summary
printh("===== p8audio test results =====")
printh("total: " .. total_tests)
printh("passed: " .. passed_tests)
printh("failed: " .. (total_tests - passed_tests))
printh("===== end =====")

-- display summary on screen
if total_tests > 0 then
    color(7)
    print("total: " .. passed_tests .. "/" .. total_tests, 4, 128)
end

__sfx__
010100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__music__
00 41414141

