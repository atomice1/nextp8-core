------------------------------------------------------------------
-- p8video.vhd
--
-- Copyright (C) 2025 Chris January
--
-- This source file is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published
-- by the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This source file is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.
--
------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

package palette is
    type Palette_Array is array(0 to 15) of Std_logic_vector(23 downto 0);
end package palette;

use work.palette.all;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
USE ieee.std_logic_unsigned.all;
USE ieee.numeric_std.all;
use IEEE.std_logic_textio.all;
use std.textio.all;

entity p8video is
generic (
    VRAM_PIPELINE_LATENCY_PIXELS : natural := 6
);
port (
    -- Clock and reset
    mclk:         IN Std_logic;  -- CPU clock domain (~30MHz)
    clk_video:    IN Std_logic;  -- Video clock domain (10.78MHz = 64.71MHz/6)
    reset_sys:    IN Std_logic;  -- Synchronized reset for mclk domain
    reset_video:  IN Std_logic;  -- Synchronized reset for clk_video domain

    -- MMIO palette interface (mclk domain)
    address:      IN Std_logic_vector(2 downto 0);   -- Palette register address (0-7)
    din:          IN Std_logic_vector(15 downto 0);  -- Write data
    dout:         OUT Std_logic_vector(15 downto 0); -- Read data
    nUDS:         IN Std_logic;  -- Upper data strobe (active low)
    nLDS:         IN Std_logic;  -- Lower data strobe (active low)
    write_en:     IN Std_logic;  -- Write enable
    read_en:      IN Std_logic;  -- Read enable
    pal_sel:      IN Std_logic;  -- Palette select

    -- Overlay control (clk_video domain)
    overlay_enable:  IN Std_logic;  -- Overlay enable
    overlay_key_colour: IN Std_logic_vector(3 downto 0);  -- Overlay key colour index

    -- Video ram interface (clk_video domain)
    vaddress_main:     OUT Std_logic_vector(12 downto 0);  -- Main vram address
    vdin_main:         IN  Std_logic_vector(15 downto 0);  -- Main vram data
    vaddress_overlay:  OUT Std_logic_vector(12 downto 0);  -- Overlay vram address
    vdin_overlay:      IN  Std_logic_vector(15 downto 0);  -- Overlay vram data

    -- Double buffering interface (clk_video domain)
    vfronto:      OUT Std_logic;
    vfrontreq:    IN Std_logic;

    -- Screen transform (quasi-static, CDC'd internally)
    screen_transform : IN Std_logic_vector(7 downto 0);

    -- High-color mode (quasi-static, CDC'd internally)
    high_color_mode : IN Std_logic_vector(7 downto 0);

    -- Secondary palette write interface (mclk domain)
    sec_pal_write_en : IN Std_logic;
    sec_pal_sel      : IN Std_logic;

    -- High-color bitfield write interface (mclk domain)
    hc_bf_write_en   : IN Std_logic;
    hc_bf_sel        : IN Std_logic;

    -- Video output signals (clk_video domain)
    VSB,HS:       buffer Std_logic;
    iblank:       OUT Std_logic;
    VR,VG,VB:     OUT Std_logic_vector(7 downto 0):="00000000"
    );
end p8video;

architecture Behavioral of p8video is

-- XGA timing constants (1024x768 @ 60Hz)
-- Total: 1344 pixels x 806 lines
-- Visible: 1024 pixels x 768 lines
-- Hsync: 136 pixels, starts at pixel 0
-- Vsync: 6 lines, starts at line 0
-- Visible region starts at: pixel 264 (136+128), line 35 (6+29)
constant l1:natural:=35;     -- vsync + vback porch
constant lno:natural:=768;   -- visible lines
constant p1_main:natural:=136+160+128;-- hsync + hback porch + left border
constant pno_main:natural:=768;   -- visible pixels
constant p2_main:natural:=p1_main+pno_main;
constant p1_overlay:natural:=136+160+128;-- hsync + hback porch + left border
constant pno_overlay:natural:=768;   -- visible pixels
constant p2_overlay:natural:=p1_overlay+pno_overlay;
constant l2:natural:=l1+lno;  --
constant xdim:natural:=1343; --pixels-1
constant ydim:natural:=805; --lines

type PaletteArray is array(0 to 31) of Std_logic_vector(23 downto 0);
CONSTANT SystemPalette : PaletteArray := (
    x"000000", x"1D2B53", x"7E2553",
    x"008751", x"AB5236", x"5F574F",
    x"C2C3C7", x"FFF1E8", x"FF004D",
    x"FFA300", x"FFEC27", x"00E436",
    x"29ADFF", x"83769C", x"FF77A8",
    x"FFCCAA", x"291814", x"111D35",
    x"422136", x"125359", x"742F29",
    x"49333B", x"A28879", x"F3EF7D",
    x"BE1250", x"FF6C24", x"A8E72E",
    x"00B54E", x"065AB5", x"754665",
    x"FF6E59", x"FF9D81"
);

-- Screen palette storage (mclk domain)
type ScreenPalette is array(0 to 15) of Std_logic_vector(4 downto 0);
signal screen_palette0_sys : ScreenPalette := (
    "00000", "00001", "00010", "00011",
    "00100", "00101", "00110", "00111",
    "01000", "01001", "01010", "01011",
    "01100", "01101", "01110", "01111"
);
signal screen_palette1_sys : ScreenPalette := (
    "00000", "00001", "00010", "00011",
    "00100", "00101", "00110", "00111",
    "01000", "01001", "01010", "01011",
    "01100", "01101", "01110", "01111"
);

-- Pack palettes for CDC transfer
signal palette0_sys_packed : Std_logic_vector(79 downto 0);
signal palette1_sys_packed : Std_logic_vector(79 downto 0);

-- CDC signals
-- Palette data synchronized to clk_video domain (multi-cycle path)
-- These are quasi-static - only change on palette writes
signal palette0_video : Std_logic_vector(79 downto 0);
signal palette1_video : Std_logic_vector(79 downto 0);
signal palette0_video_d : Std_logic_vector(79 downto 0);
signal palette1_video_d : Std_logic_vector(79 downto 0);

-- ASYNC_REG attribute for CDC synchronizers
attribute ASYNC_REG : string;
attribute ASYNC_REG of palette0_video : signal is "TRUE";
attribute ASYNC_REG of palette1_video : signal is "TRUE";

-- CDC for vfrontreq crossing mclk -> clk_video (simple level synchronizer)
signal vfrontreq_q : Std_logic := '0';
signal vfrontreq_d : Std_logic := '0';
signal vfrontreq_video : Std_logic := '0';
attribute ASYNC_REG of vfrontreq_q : signal is "TRUE";
attribute ASYNC_REG of vfrontreq_d : signal is "TRUE";

-- CDC for vfronto crossing clk_video -> mclk (simple level synchronizer)
signal vfronto_q : Std_logic := '0';
signal vfronto_d : Std_logic := '0';
signal vfronto_sys : Std_logic := '0';
signal vfront : Std_logic := '0';
attribute ASYNC_REG of vfronto_q : signal is "TRUE";
attribute ASYNC_REG of vfronto_d : signal is "TRUE";

-- CDC for screen_transform crossing mclk -> clk_video (quasi-static)
signal screen_transform_video : Std_logic_vector(7 downto 0) := (others => '0');
signal screen_transform_video_d : Std_logic_vector(7 downto 0) := (others => '0');
signal screen_transform_active : Std_logic_vector(7 downto 0) := (others => '0');
attribute ASYNC_REG of screen_transform_video : signal is "TRUE";

-- ============================================================================
-- High-color mode support
-- ============================================================================

-- Secondary palette storage (mclk domain), same format as main palette
signal sec_palette0_sys : ScreenPalette := (
    "00000", "00001", "00010", "00011",
    "00100", "00101", "00110", "00111",
    "01000", "01001", "01010", "01011",
    "01100", "01101", "01110", "01111"
);
signal sec_palette1_sys : ScreenPalette := (
    "00000", "00001", "00010", "00011",
    "00100", "00101", "00110", "00111",
    "01000", "01001", "01010", "01011",
    "01100", "01101", "01110", "01111"
);

-- Pack secondary palettes for CDC transfer
signal sec_palette0_sys_packed : Std_logic_vector(79 downto 0);
signal sec_palette1_sys_packed : Std_logic_vector(79 downto 0);

-- CDC for secondary palette
signal sec_palette0_video : Std_logic_vector(79 downto 0);
signal sec_palette1_video : Std_logic_vector(79 downto 0);
signal sec_palette0_video_d : Std_logic_vector(79 downto 0);
signal sec_palette1_video_d : Std_logic_vector(79 downto 0);
attribute ASYNC_REG of sec_palette0_video : signal is "TRUE";
attribute ASYNC_REG of sec_palette1_video : signal is "TRUE";

-- High-color bitfield storage (mclk domain), 16 bytes = 128 bits
type BitfieldArray is array(0 to 15) of Std_logic_vector(7 downto 0);
signal hc_bitfield0_sys : BitfieldArray := (others => (others => '0'));
signal hc_bitfield1_sys : BitfieldArray := (others => (others => '0'));

-- Pack bitfields for CDC transfer
signal hc_bf0_sys_packed : Std_logic_vector(127 downto 0);
signal hc_bf1_sys_packed : Std_logic_vector(127 downto 0);

-- CDC for bitfield
signal hc_bf0_video : Std_logic_vector(127 downto 0);
signal hc_bf1_video : Std_logic_vector(127 downto 0);
signal hc_bf0_video_d : Std_logic_vector(127 downto 0);
signal hc_bf1_video_d : Std_logic_vector(127 downto 0);
attribute ASYNC_REG of hc_bf0_video : signal is "TRUE";
attribute ASYNC_REG of hc_bf1_video : signal is "TRUE";

-- CDC for high_color_mode crossing mclk -> clk_video (quasi-static)
signal hc_mode_video : Std_logic_vector(7 downto 0) := (others => '0');
signal hc_mode_video_d : Std_logic_vector(7 downto 0) := (others => '0');
signal hc_mode_active : Std_logic_vector(7 downto 0) := (others => '0');
attribute ASYNC_REG of hc_mode_video : signal is "TRUE";

-- Mode 0x20 hidden pixel line buffer (16 words = 64 pixels)
type HiddenPixelBuf is array(0 to 15) of Std_logic_vector(15 downto 0);
signal hidden_buf : HiddenPixelBuf := (others => (others => '0'));

-- Overlay support (clk_video domain)
signal overlay_vdin : Std_logic_vector(15 downto 0) := (others => '0');
signal reading_overlay : Std_logic := '0';

-- Screen transform: maps output coordinates (ox, oy) to source coordinates (sx, sy)
procedure screen_xform(
    mode_val : in natural;
    ox       : in natural;
    oy       : in natural;
    sx       : out natural;
    sy       : out natural
) is
begin
    case mode_val is
        when 1 =>      -- horizontal stretch: 64x128
            sx := ox / 2; sy := oy;
        when 2 =>      -- vertical stretch: 128x64
            sx := ox; sy := oy / 2;
        when 3 =>      -- both stretch: 64x64
            sx := ox / 2; sy := oy / 2;
        when 5 =>      -- horizontal mirror
            if ox < 64 then sx := ox; else sx := 127 - ox; end if;
            sy := oy;
        when 6 =>      -- vertical mirror
            sx := ox;
            if oy < 64 then sy := oy; else sy := 127 - oy; end if;
        when 7 =>      -- both mirror
            if ox < 64 then sx := ox; else sx := 127 - ox; end if;
            if oy < 64 then sy := oy; else sy := 127 - oy; end if;
        when 129 =>    -- horizontal flip
            sx := 127 - ox; sy := oy;
        when 130 =>    -- vertical flip
            sx := ox; sy := 127 - oy;
        when 131 =>    -- both flip (180 degree rotation)
            sx := 127 - ox; sy := 127 - oy;
        when 133 =>    -- clockwise 90 degree rotation
            sx := 127 - oy; sy := ox;
        when 134 =>    -- 180 degree rotation
            sx := 127 - ox; sy := 127 - oy;
        when 135 =>    -- counterclockwise 90 degree rotation
            sx := oy; sy := 127 - ox;
        when others => -- normal (mode 0 and unrecognized)
            sx := ox; sy := oy;
    end case;
end procedure;

begin

-- ============================================================================
-- MMIO Register Interface (mclk domain)
-- ============================================================================
process(mclk)
    variable addr_idx : integer;
begin
    if rising_edge(mclk) then
        if reset_sys='1' then
            dout <= (others => '0');
            vfronto_q <= '0';
            vfronto_d <= '0';
            vfronto_sys <= '0';
        else
            dout <= (others => '0');

            if write_en = '1' then
                addr_idx := to_integer(unsigned(address(2 downto 0)));
                if pal_sel = '1' then
                    if nLDS = '0' then
                        screen_palette1_sys(addr_idx*2 + 1) <= din(7) & din(3 downto 0);
                    end if;
                    if nUDS = '0' then
                        screen_palette1_sys(addr_idx*2) <= din(15) & din(11 downto 8);
                    end if;
                else
                    if nLDS = '0' then
                        screen_palette0_sys(addr_idx*2 + 1) <= din(7) & din(3 downto 0);
                    end if;
                    if nUDS = '0' then
                        screen_palette0_sys(addr_idx*2) <= din(15) & din(11 downto 8);
                    end if;
                end if;
            end if;

            -- Secondary palette writes
            if sec_pal_write_en = '1' then
                addr_idx := to_integer(unsigned(address(2 downto 0)));
                if sec_pal_sel = '1' then
                    if nLDS = '0' then
                        sec_palette1_sys(addr_idx*2 + 1) <= din(7) & din(3 downto 0);
                    end if;
                    if nUDS = '0' then
                        sec_palette1_sys(addr_idx*2) <= din(15) & din(11 downto 8);
                    end if;
                else
                    if nLDS = '0' then
                        sec_palette0_sys(addr_idx*2 + 1) <= din(7) & din(3 downto 0);
                    end if;
                    if nUDS = '0' then
                        sec_palette0_sys(addr_idx*2) <= din(15) & din(11 downto 8);
                    end if;
                end if;
            end if;

            -- High-color bitfield writes (raw byte storage)
            if hc_bf_write_en = '1' then
                addr_idx := to_integer(unsigned(address(2 downto 0)));
                if hc_bf_sel = '1' then
                    if nLDS = '0' then
                        hc_bitfield1_sys(addr_idx*2 + 1) <= din(7 downto 0);
                    end if;
                    if nUDS = '0' then
                        hc_bitfield1_sys(addr_idx*2) <= din(15 downto 8);
                    end if;
                else
                    if nLDS = '0' then
                        hc_bitfield0_sys(addr_idx*2 + 1) <= din(7 downto 0);
                    end if;
                    if nUDS = '0' then
                        hc_bitfield0_sys(addr_idx*2) <= din(15 downto 8);
                    end if;
                end if;
            end if;

            vfronto_q <= vfront;
            vfronto_d <= vfronto_q;
            vfronto_sys <= vfronto_d;
            vfronto <= vfronto_sys;

            if read_en = '1' then
                addr_idx := to_integer(unsigned(address(2 downto 0)));
                if pal_sel = '1' then
                    if nLDS = '0' then
                        dout(7 downto 0) <= screen_palette1_sys(addr_idx*2 + 1)(4) & "000" &
                                           screen_palette1_sys(addr_idx*2 + 1)(3 downto 0);
                    end if;
                    if nUDS = '0' then
                        dout(15 downto 8) <= screen_palette1_sys(addr_idx*2)(4) & "000" &
                                            screen_palette1_sys(addr_idx*2)(3 downto 0);
                    end if;
                else
                    if nLDS = '0' then
                        dout(7 downto 0) <= screen_palette0_sys(addr_idx*2 + 1)(4) & "000" &
                                           screen_palette0_sys(addr_idx*2 + 1)(3 downto 0);
                    end if;
                    if nUDS = '0' then
                        dout(15 downto 8) <= screen_palette0_sys(addr_idx*2)(4) & "000" &
                                            screen_palette0_sys(addr_idx*2)(3 downto 0);
                    end if;
                end if;
            end if;
        end if;
    end if;
end process;

palette0_sys_packed <= screen_palette0_sys(15) & screen_palette0_sys(14) &
                       screen_palette0_sys(13) & screen_palette0_sys(12) &
                       screen_palette0_sys(11) & screen_palette0_sys(10) &
                       screen_palette0_sys(9) & screen_palette0_sys(8) &
                       screen_palette0_sys(7) & screen_palette0_sys(6) &
                       screen_palette0_sys(5) & screen_palette0_sys(4) &
                       screen_palette0_sys(3) & screen_palette0_sys(2) &
                       screen_palette0_sys(1) & screen_palette0_sys(0);

palette1_sys_packed <= screen_palette1_sys(15) & screen_palette1_sys(14) &
                       screen_palette1_sys(13) & screen_palette1_sys(12) &
                       screen_palette1_sys(11) & screen_palette1_sys(10) &
                       screen_palette1_sys(9) & screen_palette1_sys(8) &
                       screen_palette1_sys(7) & screen_palette1_sys(6) &
                       screen_palette1_sys(5) & screen_palette1_sys(4) &
                       screen_palette1_sys(3) & screen_palette1_sys(2) &
                       screen_palette1_sys(1) & screen_palette1_sys(0);

sec_palette0_sys_packed <= sec_palette0_sys(15) & sec_palette0_sys(14) &
                           sec_palette0_sys(13) & sec_palette0_sys(12) &
                           sec_palette0_sys(11) & sec_palette0_sys(10) &
                           sec_palette0_sys(9) & sec_palette0_sys(8) &
                           sec_palette0_sys(7) & sec_palette0_sys(6) &
                           sec_palette0_sys(5) & sec_palette0_sys(4) &
                           sec_palette0_sys(3) & sec_palette0_sys(2) &
                           sec_palette0_sys(1) & sec_palette0_sys(0);

sec_palette1_sys_packed <= sec_palette1_sys(15) & sec_palette1_sys(14) &
                           sec_palette1_sys(13) & sec_palette1_sys(12) &
                           sec_palette1_sys(11) & sec_palette1_sys(10) &
                           sec_palette1_sys(9) & sec_palette1_sys(8) &
                           sec_palette1_sys(7) & sec_palette1_sys(6) &
                           sec_palette1_sys(5) & sec_palette1_sys(4) &
                           sec_palette1_sys(3) & sec_palette1_sys(2) &
                           sec_palette1_sys(1) & sec_palette1_sys(0);

hc_bf0_sys_packed <= hc_bitfield0_sys(15) & hc_bitfield0_sys(14) &
                     hc_bitfield0_sys(13) & hc_bitfield0_sys(12) &
                     hc_bitfield0_sys(11) & hc_bitfield0_sys(10) &
                     hc_bitfield0_sys(9) & hc_bitfield0_sys(8) &
                     hc_bitfield0_sys(7) & hc_bitfield0_sys(6) &
                     hc_bitfield0_sys(5) & hc_bitfield0_sys(4) &
                     hc_bitfield0_sys(3) & hc_bitfield0_sys(2) &
                     hc_bitfield0_sys(1) & hc_bitfield0_sys(0);

hc_bf1_sys_packed <= hc_bitfield1_sys(15) & hc_bitfield1_sys(14) &
                     hc_bitfield1_sys(13) & hc_bitfield1_sys(12) &
                     hc_bitfield1_sys(11) & hc_bitfield1_sys(10) &
                     hc_bitfield1_sys(9) & hc_bitfield1_sys(8) &
                     hc_bitfield1_sys(7) & hc_bitfield1_sys(6) &
                     hc_bitfield1_sys(5) & hc_bitfield1_sys(4) &
                     hc_bitfield1_sys(3) & hc_bitfield1_sys(2) &
                     hc_bitfield1_sys(1) & hc_bitfield1_sys(0);

-- ============================================================================
-- Video Rendering Process (clk_video domain)
-- ============================================================================
process (clk_video)
    variable screen_index: integer range 0 to 15;
    variable overlay_pixel_index: integer range 0 to 15;
    variable system_index: integer range 0 to 31;
    variable vdata: Std_logic_vector(23 downto 0);
    variable px_main, px_next_main: natural range 0 to 2047:=0;
    variable px_overlay, px_next_overlay: natural range 0 to 2047:=0;
    variable pixel: natural range 0 to 2047:=0;
    variable lin: natural range 0 to 1023:=0;
    variable ln_main, ln_overlay: natural range 0 to 1023:=0;
    variable src_x, src_y: natural range 0 to 127:=0;
    variable src_x_next, src_y_next: natural range 0 to 127:=0;
    variable xform_mode: natural range 0 to 255:=0;
    -- High-color mode variables
    variable hc_mode_val: natural range 0 to 255:=0;
    variable bf_byte: Std_logic_vector(7 downto 0);
    variable section: integer range 0 to 15;
    variable replace_color: integer range 0 to 15;
    variable hidden_word: Std_logic_vector(15 downto 0);
    variable hidden_pix: integer range 0 to 15;
    variable use_secondary: boolean;
    variable hpb_word_idx: natural range 0 to 15;
    variable ln_current: natural range 0 to 127;
begin
    if rising_edge(clk_video) then
        if reset_video='1' then
            pixel := 0;
            lin := 0;
            ln_main := 0;
            ln_overlay := 0;
            px_main := 0;
            px_overlay := 0;
            VSB <= '1';
            HS <= '1';
            iblank <= '1';
            VR <= (others => '0');
            VG <= (others => '0');
            VB <= (others => '0');
            vaddress_main <= (others => '0');
            vaddress_overlay <= (others => '0');
            palette0_video <= "01111" & "01110" & "01101" & "01100" & "01011" & "01010" & "01001" & "01000" &
                              "00111" & "00110" & "00101" & "00100" & "00011" & "00010" & "00001" & "00000";
            palette1_video <= "01111" & "01110" & "01101" & "01100" & "01011" & "01010" & "01001" & "01000" &
                              "00111" & "00110" & "00101" & "00100" & "00011" & "00010" & "00001" & "00000";
            palette0_video_d <= "01111" & "01110" & "01101" & "01100" & "01011" & "01010" & "01001" & "01000" &
                                "00111" & "00110" & "00101" & "00100" & "00011" & "00010" & "00001" & "00000";
            palette1_video_d <= "01111" & "01110" & "01101" & "01100" & "01011" & "01010" & "01001" & "01000" &
                                "00111" & "00110" & "00101" & "00100" & "00011" & "00010" & "00001" & "00000";
            vfront <= '0';
            vfrontreq_q <= '0';
            vfrontreq_d <= '0';
            vfrontreq_video <= '0';
            screen_transform_video <= (others => '0');
            screen_transform_video_d <= (others => '0');
            screen_transform_active <= (others => '0');
            sec_palette0_video <= (others => '0');
            sec_palette1_video <= (others => '0');
            sec_palette0_video_d <= (others => '0');
            sec_palette1_video_d <= (others => '0');
            hc_bf0_video <= (others => '0');
            hc_bf1_video <= (others => '0');
            hc_bf0_video_d <= (others => '0');
            hc_bf1_video_d <= (others => '0');
            hc_mode_video <= (others => '0');
            hc_mode_video_d <= (others => '0');
            hc_mode_active <= (others => '0');
            hidden_buf <= (others => (others => '0'));
        else
            palette0_video <= palette0_sys_packed;
            palette1_video <= palette1_sys_packed;
            palette0_video_d <= palette0_video;
            palette1_video_d <= palette1_video;

            vfrontreq_q <= vfrontreq;
            vfrontreq_d <= vfrontreq_q;
            vfrontreq_video <= vfrontreq_d;

            screen_transform_video <= screen_transform;
            screen_transform_video_d <= screen_transform_video;

            -- CDC for secondary palette
            sec_palette0_video <= sec_palette0_sys_packed;
            sec_palette1_video <= sec_palette1_sys_packed;
            sec_palette0_video_d <= sec_palette0_video;
            sec_palette1_video_d <= sec_palette1_video;

            -- CDC for bitfield
            hc_bf0_video <= hc_bf0_sys_packed;
            hc_bf1_video <= hc_bf1_sys_packed;
            hc_bf0_video_d <= hc_bf0_video;
            hc_bf1_video_d <= hc_bf1_video;

            -- CDC for high-color mode
            hc_mode_video <= high_color_mode;
            hc_mode_video_d <= hc_mode_video;

            if lin < 6 then
                VSB <= '0';
            else
                VSB <= '1';
            end if;

            if pixel >= xdim - 1 then
                pixel := 0;
                if lin < ydim then
                    lin := lin + 1;
                else
                    lin := 0;
                    if vfront /= vfrontreq_video then
                        screen_transform_active <= screen_transform_video_d;
                        hc_mode_active <= hc_mode_video_d;
                    end if;
                    vfront <= vfrontreq_video;
                end if;
            else
                pixel := pixel + 2;
            end if;

            if pixel < 136 then
                HS <= '0';
            else
                HS <= '1';
            end if;

            xform_mode := to_integer(unsigned(screen_transform_active));
            hc_mode_val := to_integer(unsigned(hc_mode_active));

            if pixel >= p1_main - VRAM_PIPELINE_LATENCY_PIXELS and pixel < p2_main and lin >= l1 and lin < l2 then
                ln_main := (lin - l1) / 6;
                px_main := (pixel - p1_main) / 6;
                if pixel + VRAM_PIPELINE_LATENCY_PIXELS < p2_main then
                    px_next_main := (pixel + VRAM_PIPELINE_LATENCY_PIXELS - p1_main) / 6;
                    screen_xform(xform_mode, px_next_main, ln_main, src_x_next, src_y_next);
                    vaddress_main <= vfront & std_logic_vector(to_unsigned(32 * src_y_next + src_x_next / 4, 12));
                else
                    vaddress_main <= (others => '0');
                end if;
            else
                ln_main := 300;
                px_main := 800;
                -- Mode 0x20 prefetch: read hidden pixels during left border
                if hc_mode_val / 16 = 2 and
                   lin >= l1 and lin < l2 and
                   (lin - l1) mod 6 = 0 and
                   pixel >= 300 and pixel < 332 then
                    ln_current := (lin - l1) / 6;
                    hpb_word_idx := (pixel - 300) / 2;
                    vaddress_main <= vfront & std_logic_vector(to_unsigned(32 * ln_current + 16 + hpb_word_idx, 12));
                else
                    vaddress_main <= (others => '0');
                end if;
            end if;

            -- Mode 0x20 prefetch data capture (with VRAM pipeline latency)
            if hc_mode_val / 16 = 2 and
               lin >= l1 and lin < l2 and
               (lin - l1) mod 6 = 0 and
               pixel >= 300 + VRAM_PIPELINE_LATENCY_PIXELS and
               pixel < 332 + VRAM_PIPELINE_LATENCY_PIXELS then
                hpb_word_idx := (pixel - 300 - VRAM_PIPELINE_LATENCY_PIXELS) / 2;
                hidden_buf(hpb_word_idx) <= vdin_main;
            end if;

            if pixel >= p1_overlay - VRAM_PIPELINE_LATENCY_PIXELS and pixel < p2_overlay and lin >= l1 and lin < l2 then
                px_overlay := (pixel - p1_overlay) / 6;
                ln_overlay := (lin - l1) / 6;
                if pixel + VRAM_PIPELINE_LATENCY_PIXELS < p2_overlay then
                    px_next_overlay := (pixel + VRAM_PIPELINE_LATENCY_PIXELS - p1_overlay) / 6;
                    vaddress_overlay <= vfront & std_logic_vector(to_unsigned(32 * ln_overlay + px_next_overlay / 4, 12));
                else
                    vaddress_overlay <= (others => '0');
                end if;
            else
                px_overlay := 800;
                ln_overlay := 300;
                vaddress_overlay <= (others => '0');
            end if;

            -- Pixel output logic
            if pixel >= p1_main and pixel < p2_main and lin >= l1 and lin < l2 then
                screen_xform(xform_mode, px_main, ln_main, src_x, src_y);
                case src_x mod 4 is
                    when 0 =>
                        screen_index := to_integer(unsigned(vdin_main(11 downto 8)));
                    when 1 =>
                        screen_index := to_integer(unsigned(vdin_main(15 downto 12)));
                    when 2 =>
                        screen_index := to_integer(unsigned(vdin_main(3 downto 0)));
                    when 3 =>
                        screen_index := to_integer(unsigned(vdin_main(7 downto 4)));
                    when others =>
                        screen_index := 0;
                end case;
            else
                screen_index := 0;
            end if;
            if pixel >= p1_overlay and pixel < p2_overlay and lin >= l1 and lin < l2 then
                iblank <= '0';
                case px_overlay mod 4 is
                    when 0 =>
                        overlay_pixel_index := to_integer(unsigned(vdin_overlay(11 downto 8)));
                    when 1 =>
                        overlay_pixel_index := to_integer(unsigned(vdin_overlay(15 downto 12)));
                    when 2 =>
                        overlay_pixel_index := to_integer(unsigned(vdin_overlay(3 downto 0)));
                    when 3 =>
                        overlay_pixel_index := to_integer(unsigned(vdin_overlay(7 downto 4)));
                    when others =>
                        overlay_pixel_index := 0;
                end case;
            else
                iblank <= '1';
                overlay_pixel_index := 0;
            end if;
            if overlay_enable = '1' and overlay_pixel_index /= to_integer(unsigned(overlay_key_colour)) then
                system_index := overlay_pixel_index;
            else
                -- Primary palette lookup
                if vfront = '1' then
                    system_index := to_integer(unsigned(palette1_video_d(screen_index*5+4 downto screen_index*5)));
                else
                    system_index := to_integer(unsigned(palette0_video_d(screen_index*5+4 downto screen_index*5)));
                end if;

                -- High-color mode processing
                if hc_mode_val = 16#10# then
                    -- Mode 0x10: per-line palette swap using bitfield
                    if vfront = '1' then
                        bf_byte := hc_bf1_video_d((src_y/8)*8+7 downto (src_y/8)*8);
                    else
                        bf_byte := hc_bf0_video_d((src_y/8)*8+7 downto (src_y/8)*8);
                    end if;
                    if bf_byte(src_y mod 8) = '1' then
                        -- Use secondary palette
                        if vfront = '1' then
                            system_index := to_integer(unsigned(sec_palette1_video_d(screen_index*5+4 downto screen_index*5)));
                        else
                            system_index := to_integer(unsigned(sec_palette0_video_d(screen_index*5+4 downto screen_index*5)));
                        end if;
                    end if;

                elsif hc_mode_val = 16#20# then
                    -- Mode 0x20: 5-bitplane mode using hidden pixel from line buffer
                    hidden_pix := 0;
                    if src_x < 64 then
                        hidden_word := hidden_buf(src_x / 4);
                        case src_x mod 4 is
                            when 0 => hidden_pix := to_integer(unsigned(hidden_word(11 downto 8)));
                            when 1 => hidden_pix := to_integer(unsigned(hidden_word(15 downto 12)));
                            when 2 => hidden_pix := to_integer(unsigned(hidden_word(3 downto 0)));
                            when 3 => hidden_pix := to_integer(unsigned(hidden_word(7 downto 4)));
                            when others => hidden_pix := 0;
                        end case;
                    end if;
                    if hidden_pix /= 0 then
                        if vfront = '1' then
                            system_index := to_integer(unsigned(sec_palette1_video_d(screen_index*5+4 downto screen_index*5)));
                        else
                            system_index := to_integer(unsigned(sec_palette0_video_d(screen_index*5+4 downto screen_index*5)));
                        end if;
                    end if;

                elsif hc_mode_val / 16 = 3 then
                    -- Mode 0x30-0x3F: gradient fill replacing specific color
                    replace_color := hc_mode_val mod 16;
                    if (system_index mod 16) = replace_color then
                        section := src_y / 8;
                        if vfront = '1' then
                            bf_byte := hc_bf1_video_d((src_y/8)*8+7 downto (src_y/8)*8);
                        else
                            bf_byte := hc_bf0_video_d((src_y/8)*8+7 downto (src_y/8)*8);
                        end if;
                        if bf_byte(src_y mod 8) = '1' then
                            section := (section + 1) mod 16;
                        end if;
                        if vfront = '1' then
                            system_index := to_integer(unsigned(sec_palette1_video_d(section*5+4 downto section*5)));
                        else
                            system_index := to_integer(unsigned(sec_palette0_video_d(section*5+4 downto section*5)));
                        end if;
                    end if;
                end if;
            end if;

            vdata := SystemPalette(system_index);
            VR <= vdata(23 downto 16);
            VG <= vdata(15 downto 8);
            VB <= vdata(7 downto 0);
        end if;
    end if;
end process;

end Behavioral;
