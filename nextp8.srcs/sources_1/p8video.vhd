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
port (
    -- Clock and reset
    mclk:         IN Std_logic;  -- CPU clock domain (~30MHz)
    clk_video:    IN Std_logic;  -- Video clock domain (10.78MHz = 64.71MHz/6)
    reset:        IN Std_logic;  -- Async reset input

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
constant p1:natural:=264+128;-- hsync + hback porch + left border
constant pno:natural:=768;   -- visible pixels
constant p2:natural:=p1+pno;
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

-- Overlay support (clk_video domain)
signal overlay_vdin : Std_logic_vector(15 downto 0) := (others => '0');
signal reading_overlay : Std_logic := '0';

-- Reset synchronizers for each clock domain
signal reset_sys_d : Std_logic := '1';
signal reset_sys_q : Std_logic := '1';
signal reset_video_d : Std_logic := '1';
signal reset_video_q : Std_logic := '1';
attribute ASYNC_REG of reset_sys_d : signal is "TRUE";
attribute ASYNC_REG of reset_sys_q : signal is "TRUE";
attribute ASYNC_REG of reset_video_d : signal is "TRUE";
attribute ASYNC_REG of reset_video_q : signal is "TRUE";

begin

-- ============================================================================
-- Reset Synchronizers
-- ============================================================================

process(mclk, reset)
begin
    if reset = '1' then
        reset_sys_d <= '1';
        reset_sys_q <= '1';
    elsif rising_edge(mclk) then
        reset_sys_d <= '0';
        reset_sys_q <= reset_sys_d;
    end if;
end process;

process(clk_video, reset)
begin
    if reset = '1' then
        reset_video_d <= '1';
        reset_video_q <= '1';
    elsif rising_edge(clk_video) then
        reset_video_d <= '0';
        reset_video_q <= reset_video_d;
    end if;
end process;

-- ============================================================================
-- MMIO Register Interface (mclk domain)
-- ============================================================================
process(mclk)
    variable addr_idx : integer;
begin
    if rising_edge(mclk) then
        if reset_sys_q='1' then
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

-- ============================================================================
-- Video Rendering Process (clk_video domain)
-- ============================================================================
process (clk_video)
    variable screen_index: integer range 0 to 15;
    variable overlay_pixel_index: integer range 0 to 15;
    variable system_index: integer range 0 to 31;
    variable vdata: Std_logic_vector(23 downto 0);
    variable px, px_next: natural range 0 to 2047:=0;
    variable pixel: natural range 0 to 2047:=0;
    variable ln, lin: natural range 0 to 1023:=0;
begin
    if rising_edge(clk_video) then
        if reset_video_q='1' then
            pixel := 0;
            lin := 0;
            ln := 0;
            px := 0;
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
        else
            palette0_video <= palette0_sys_packed;
            palette1_video <= palette1_sys_packed;
            palette0_video_d <= palette0_video;
            palette1_video_d <= palette1_video;

            vfrontreq_q <= vfrontreq;
            vfrontreq_d <= vfrontreq_q;
            vfrontreq_video <= vfrontreq_d;

            if lin < 6 then
                VSB <= '0';
            else
                VSB <= '1';
            end if;

            if pixel < 136 then
                HS <= '0';
            else
                HS <= '1';
            end if;

            if pixel >= xdim - 5 then
                pixel := 0;
                if lin < ydim then
                    lin := lin + 1;
                else
                    lin := 0;
                    vfront <= vfrontreq_video;
                end if;
            else
                pixel := pixel + 6;
            end if;

            if pixel >= p1 - 36 and pixel < p2 + 6 and lin >= l1 and lin < l2 then
                px := (pixel - p1) / 6;
                ln := (lin - l1) / 6;
                px_next := px + 1;

                vaddress_main <= vfront & std_logic_vector(to_unsigned(32 * ln + px_next / 4, 12));
                vaddress_overlay <= '0' & std_logic_vector(to_unsigned(32 * ln + px_next / 4, 12));
            else
                px := 800;
                ln := 300;
                vaddress_main <= (others => '0');
                vaddress_overlay <= (others => '0');
            end if;

            -- Pixel output logic
            if pixel >= p1 and pixel < p2 and lin >= l1 and lin < l2 then
                iblank <= '0';

                case px mod 4 is
                    when 0 =>
                        screen_index := to_integer(unsigned(vdin_main(11 downto 8)));
                        overlay_pixel_index := to_integer(unsigned(vdin_overlay(11 downto 8)));
                    when 1 =>
                        screen_index := to_integer(unsigned(vdin_main(15 downto 12)));
                        overlay_pixel_index := to_integer(unsigned(vdin_overlay(15 downto 12)));
                    when 2 =>
                        screen_index := to_integer(unsigned(vdin_main(3 downto 0)));
                        overlay_pixel_index := to_integer(unsigned(vdin_overlay(3 downto 0)));
                    when 3 =>
                        screen_index := to_integer(unsigned(vdin_main(7 downto 4)));
                        overlay_pixel_index := to_integer(unsigned(vdin_overlay(7 downto 4)));
                    when others =>
                        screen_index := 0;
                        overlay_pixel_index := 0;
                end case;
                if overlay_enable = '1' and overlay_pixel_index /= to_integer(unsigned(overlay_key_colour)) then
                    system_index := overlay_pixel_index;
                else
                    if vfront = '1' then
                        system_index := to_integer(unsigned(palette1_video_d(screen_index*5+4 downto screen_index*5)));
                    else
                        system_index := to_integer(unsigned(palette0_video_d(screen_index*5+4 downto screen_index*5)));
                    end if;
                end if;

                vdata := SystemPalette(system_index);
                VR <= vdata(23 downto 16);
                VG <= vdata(15 downto 8);
                VB <= vdata(7 downto 0);
            else
                iblank <= '1';
                VR <= (others => '0');
                VG <= (others => '0');
                VB <= (others => '0');
            end if;
        end if;
    end if;
end process;

end Behavioral;
