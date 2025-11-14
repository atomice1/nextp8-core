------------------------------------------------------------------
-- p8video.v
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
	clk325:   IN Std_logic;
	reset:    IN Std_logic;
	vaddress: OUT Std_logic_vector(12 downto 0);
	vdin:     IN  Std_logic_vector(15 downto 0);
	vfronto:  OUT Std_logic;
	vfrontreq: IN Std_logic;
	VSB,HS:   buffer Std_logic;
	iblank:   OUT Std_logic;
	VR,VG,VB: OUT Std_logic_vector(7 downto 0):="00000000";
	screen_palette:  IN std_logic_vector(0 to 79)
	--px_debug: OUT Std_logic_vector(10 downto 0);
	--pixel_debug: OUT Std_logic_vector(10 downto 0);
	--ln_debug: OUT Std_logic_vector(9 downto 0);
	--lin_debug: OUT Std_logic_vector(9 downto 0)
	);
end p8video;

architecture Behavioral of p8video is

constant l1:natural:=36; --12
constant lno:natural:=768;
constant p1:natural :=427;
constant pno:natural:=768;
constant p2:natural:=p1+pno;
constant l2:natural:=l1+lno;  --
constant xdim:natural:=1343; --pixels-1
constant ydim:natural:=806; --lines
shared variable px,px_next,pixel: natural range 0 to 2047:=0;
shared variable ln,lin: natural range 0 to 1023:=0;
shared variable vbuffer: Std_logic_vector(15 downto 0);
shared variable vfront: Std_logic:='0';

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

begin
process (clk325)
    variable screen_index: integer;
    variable system_index: integer;
    variable vdata: Std_logic_vector(23 downto 0);    
begin
if rising_edge(clk325) then
	if reset='1' then
		pixel:=0;
		lin:=0; ln:=0;
		vfront:='0';
	else
		if lin<6 then VSB<='0'; else VSB<='1'; end if;
		if pixel<136 then HS<='0'; else HS<='1'; end if;
		
		if pixel=xdim-1 then
			pixel:=0;
			if lin<ydim then
				lin:=lin+1;
			else
				lin:=0;
				vfront:=vfrontreq;
			end if;
		else
			pixel:=pixel+2;
		end if;
	
        if pixel>=p1-6 and pixel<p2+6 and lin>=l1 and lin<l2	then
            px:=(pixel-p1)/6; ln:=(lin-l1)/6;
            px_next:=(pixel+2-p1)/6;
            vaddress<=vfront & std_logic_vector(to_unsigned(32*ln + (px_next)/4, 12));
        else
            px:=800; ln:=300;
        end if;
    end if;

    vfronto <= vfront;

    --px_debug <= std_logic_vector(to_unsigned(px, 11));
    --pixel_debug <= std_logic_vector(to_unsigned(pixel, 11));
    --ln_debug <= std_logic_vector(to_unsigned(ln, 10));
    --lin_debug <= std_logic_vector(to_unsigned(lin, 10));
end if;
if falling_edge(clk325) then
	vbuffer(15 downto 0):=vdin;
	if pixel>=p1 and pixel<p2 and lin>=l1 and lin<l2 then
        iblank<='0'; 
        case px mod 4 is
			when 0 => screen_index:=to_integer(unsigned(vbuffer(11 downto 8)));
			when 1 => screen_index:=to_integer(unsigned(vbuffer(15 downto 12)));
			when 2 => screen_index:=to_integer(unsigned(vbuffer(3 downto 0)));
			when 3 => screen_index:=to_integer(unsigned(vbuffer(7 downto 4)));
			when others =>
		end case;
		system_index:=to_integer(unsigned(screen_palette(screen_index*5 to screen_index*5+4)));
		vdata:=SystemPalette(system_index);
		VR<=vdata(23 downto 16);
		VG<=vdata(15 downto 8);
		VB<=vdata(7 downto 0);
	else
	    iblank<='1';
		VR<="00000000"; VG<="00000000"; VB<="00000000";
	end if;
end if;
end process;

end Behavioral;

