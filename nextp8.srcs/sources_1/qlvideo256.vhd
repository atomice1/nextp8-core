----------------------------------------------------------------------------------
-- Company: 
-- Engineer: Theodoulos Liontakis
-- 
-- Create Date:    12:40:44 03/08/2024 
-- Design Name: 
-- Module Name:    qlvideo - Behavioral 
-- Project Name: 
-- Target Devices: 
-- Tool versions: 
-- Description: 
--
-- Dependencies: 
--
-- Revision: 
-- Revision 0.01 - File Created
-- Additional Comments: 
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
USE ieee.std_logic_unsigned.all;
USE ieee.numeric_std.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity qlvideo256 is
port (
	clk325:   IN Std_logic;
	reset:    IN Std_logic;
	vaddress: OUT natural range 0 to 32767;
	vdin:     IN  Std_logic_vector(15 downto 0);
	VSB,HS:   buffer Std_logic;
	iblank:   OUT std_logic;
	mode:    IN  Std_logic;
	VDATA: OUT Std_logic_vector(7 downto 0)
	);
end qlvideo256;

architecture Behavioral of qlvideo256 is

constant l1:natural:=36; --12
constant lno:natural:=768;
constant p1:natural :=299;
constant pno:natural:=1024;
constant p2:natural:=p1+pno;
constant l2:natural:=l1+lno;  --
constant xdim:natural:=1343; --pixels-1
constant ydim:natural:=806; --lines
shared variable px,pixel: natural range 0 to 2047:=0;
shared variable ln,lin: natural range 0 to 1023:=0;
shared variable vbuffer: Std_logic_vector(15 downto 0);

begin


process (clk325)    
begin
if falling_edge(clk325) then
	if reset='1' then
		pixel:=0;
		lin:=0; ln:=0;
	else
		if lin<6 then VSB<='0'; else VSB<='1'; end if;
		if pixel<136 then HS<='0'; else HS<='1'; end if;
		
		if pixel=xdim-1 then
			pixel:=0;
			if lin<ydim then lin:=lin+1; else lin:=0; end if;
		else
			pixel:=pixel+2;
		end if;
	
        if pixel>=p1-10 and pixel<p2+12 and lin>=l1 and lin<l2	then
                px:=pixel/2-p1/2; ln:=lin/3-l1/3;
                vaddress<=128*ln + px/4;
        else
                px:=800; ln:=300;
        end if;
    end if;

end if;
if rising_edge(clk325) then
	vbuffer(15 downto 0):=vdin;
	if pixel>p1 and pixel<p2+1 and lin>=l1 and lin<l2 then
	   iblank<='0';
		if mode ='1' then 
			case (px-1) mod 4 is
			when 0 => vdata<=vbuffer(15 downto 8);
			when 1 => vdata<=vbuffer(15 downto 8);
			when 2 => vdata<=vbuffer(7 downto 0);
			when 3 => vdata<=vbuffer(7 downto 0);  
			when others =>
			end case;
		else 
			case (px-1) mod 4 is
			when 0 => 	vdata<=vbuffer(14)&vbuffer(15)&"0"&vbuffer(13)&vbuffer(15)&"0"&vbuffer(12)&vbuffer(15);
			when 1 => 	vdata<=vbuffer(10)&vbuffer(11)&"0"&vbuffer(9)&vbuffer(11)&"0"&vbuffer(8)&vbuffer(11);
			when 2 => 	vdata<=vbuffer(6)&vbuffer(7)&"0"&vbuffer(5)&vbuffer(7)&"0"&vbuffer(4)&vbuffer(7);
			when 3 => 	vdata<=vbuffer(2)&vbuffer(3)&"0"&vbuffer(1)&vbuffer(3)&"0"&vbuffer(0)&vbuffer(3);
			when others =>
			end case;
        end if;
	else
	    iblank<='1';
		vdata<="00000000";
	end if;
end if;
end process;

end Behavioral;

