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

entity qlvideo is
port (
	clk325:   IN Std_logic;
	reset:    IN Std_logic;
	vaddress: OUT natural range 0 to 32767;
	vdin:     IN  Std_logic_vector(15 downto 0);
	VSB,HS:   buffer Std_logic;
	iblank:   OUT std_logic;
	mode,membase,col16:    IN  Std_logic;
	palette: in std_logic_vector(5 downto 0);
	VR,VG,VB: OUT Std_logic_vector(2 downto 0):="000"
	);
end qlvideo;

architecture Behavioral of qlvideo is

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
shared variable ns7:std_logic:='0';
shared variable vbuffer: Std_logic_vector(15 downto 0);
Signal fcnt: Std_logic_vector(6 downto 0);
shared variable flash,BF,BB,GG,RR,FF,fr,fg,fb:std_logic:='0';
shared variable flon,fon:std_logic;

begin


fcnt<=fcnt+1 when rising_edge(VSB);

process (clk325)    
begin
if rising_edge(clk325) then
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
			if (membase='0') then vaddress<=64*ln + px/8; else vaddress<=16384 + 64*ln + px/8;  end if;
 	    else
			px:=800; ln:=300;
	   end if;
	end if;
end if;
if falling_edge(clk325) then
	vbuffer(15 downto 0):=vdin;
	if pixel>p1 and pixel<p2+1 and lin>=l1 and lin<l2 then
	   iblank<='0';
		ns7:='1';
		if mode ='1' then 
			case (px-1) mod 8 is
			when 0 => flash:=vbuffer(14); BB:=vbuffer(6); GG:=vbuffer(15); RR:=vbuffer(7);  --ff:=vbuffer2(7); 
			when 1 => flash:=vbuffer(14); BB:=vbuffer(6); GG:=vbuffer(15); RR:=vbuffer(7);  --ff:=vbuffer2(7); 
			when 2 => flash:=vbuffer(12); BB:=vbuffer(4); GG:=vbuffer(13); RR:=vbuffer(5);  --ff:=vbuffer2(5); 
			when 3 => flash:=vbuffer(12); BB:=vbuffer(4); GG:=vbuffer(13); RR:=vbuffer(5);  --ff:=vbuffer2(5); 
			when 4 => flash:=vbuffer(10); BB:=vbuffer(2); GG:=vbuffer(11); RR:=vbuffer(3);  --ff:=vbuffer2(3); 
			when 5 => flash:=vbuffer(10); BB:=vbuffer(2); GG:=vbuffer(11); RR:=vbuffer(3);  --ff:=vbuffer2(3); 
			when 6 => flash:=vbuffer( 8); BB:=vbuffer(0); GG:=vbuffer(9);  RR:=vbuffer(1); -- ff:=vbuffer2(1); 
			when 7 => flash:=vbuffer( 8); BB:=vbuffer(0); GG:=vbuffer(9);  RR:=vbuffer(1);  --ff:=vbuffer2(1); 
			when others =>
			end case;
			if fon='0' then fB:=BB; fG:=GG; fR:=RR; end if;
			if flash='1' and (px mod 2)=0  then fon:=not fon; end if;
			if (fon or flash)='1'  and fcnt(6)='1' and col16='0' then 
				VR(2)<=fr; VG(2)<=fg; VB(2)<=fb; VB(1)<=fb and ns7; VG(1)<=fg and ns7; VR(1)<=fr and ns7;
			else 
				if col16='1' then	
					if palette(3)='1' then 
						VB<=RR&GG&BB; VR(0)<=flash; VG(0)<=flash;
					elsif palette(4)='1' then
						VG<=RR&GG&BB; VB(0)<=flash; VR(0)<=flash;
					elsif palette(5)='1' then
						VR<=RR&GG&BB; VB(0)<=flash;  VG(0)<=flash;
					elsif RR='0' and BB='0' and GG='0' and palette(0)='0' and palette(1)='0' and palette(2)='0' and flash='1' then
						VR(2)<='1'; VG(2)<='1'; VB(2)<='0'; VB(1)<='0'; VG(1)<='0'; VR(1)<='1';
					else
						VR(2)<=RR; VG(2)<=GG; VB(2)<=BB; 
						VB(1)<=flash and not palette(0); VG(1)<=flash and not palette(1); VR(1)<=flash and not palette(2);
					end if;
				else 
					VR(2)<=RR; VG(2)<=GG; VB(2)<=BB;
					VB(1)<=BB and ns7; VG(1)<=GG and ns7; VR(1)<=RR and ns7;
				end if;
			end if;
		else 
			case (px-1) mod 8 is
			when 0 => 	GG:=vbuffer(15); RR:=vbuffer(7);  --ff:=vbuffer2(7); ff2:=vbuffer2(6);
			when 1 => 	GG:=vbuffer(14); RR:=vbuffer(6);  --ff:=vbuffer2(7); ff2:=vbuffer2(6);
			when 2 => 	GG:=vbuffer(13); RR:=vbuffer(5);  --ff:=vbuffer2(5); ff2:=vbuffer2(4);
			when 3 => 	GG:=vbuffer(12); RR:=vbuffer(4);  --ff:=vbuffer2(5); ff2:=vbuffer2(4);
			when 4 => 	GG:=vbuffer(11); RR:=vbuffer(3);  --ff:=vbuffer2(3); ff2:=vbuffer2(2);
			when 5 => 	GG:=vbuffer(10); RR:=vbuffer(2);  --ff:=vbuffer2(3); ff2:=vbuffer2(2);
			when 6 => 	GG:=vbuffer(9);  RR:=vbuffer(1);  --ff:=vbuffer2(1); ff2:=vbuffer2(0);
			when 7 => 	GG:=vbuffer(8);  RR:=vbuffer(0);  --ff:=vbuffer2(1); ff2:=vbuffer2(0);
			when others =>
			end case;

			if palette(0)='1' and palette(1)='1' and palette(2)='1'  then
				VB(2)<=(GG and RR); VG(2)<=GG; VR(2)<=RR;
				VB(1)<=(GG and RR); VG(1)<=GG; VR(1)<=GG; 
			elsif palette(0)='0' and palette(1)='1' and palette(2)='1'  then
				VB(2)<=(GG and RR); VG(2)<=GG; VR(2)<=RR;
				VB(1)<=(GG and RR); VG(1)<=RR; VR(1)<=RR; 
			elsif palette(0)='1' and palette(1)='0' and palette(2)='1' then
				VB(2)<=GG;  VG(2)<=RR; VR(2)<=RR ;  
				VB(1)<=GG and ns7; VG(1)<=RR and ns7; VR(1)<=RR and ns7; 
			elsif palette(0)='0' and palette(1)='0' and palette(2)='1'  then
				VB(2)<=RR;  VG(2)<=GG; VR(2)<=RR ;  
				VB(1)<=RR and ns7; VG(1)<=GG and ns7; VR(1)<=RR and ns7; 
			elsif palette(0)='1' and palette(1)='1' and palette(2)='0' then
				VB(2)<=GG;  VG(2)<=GG; VR(2)<=RR ;  
				VB(1)<=GG and ns7; VG(1)<=GG and ns7; VR(1)<=RR and ns7; 
			elsif palette(0)='0' and palette(1)='1' and palette(2)='0'  then
				VB(2)<=RR; VG(2)<=GG; VR(2)<=(GG and RR); 
				VB(1)<=RR and ns7; VG(1)<=GG and ns7; VR(1)<=(GG and RR) and ns7; 
			elsif palette(0)='1' and palette(1)='0' and palette(2)='0' then
				VB(2)<=GG; VG(2)<=(GG and RR); VR(2)<=RR;  
				VB(1)<=GG and ns7; VG(1)<=(GG and RR) and ns7; VR(1)<=RR and ns7; 
			else
				VB(2)<=(GG and RR); VG(2)<=GG; VR(2)<=RR;
				VB(1)<=(GG and RR) and ns7; VG(1)<=GG and ns7; VR(1)<=RR and ns7; 
			end if;
		end if;
	else
	    iblank<='1';
		if pixel mod 2=0 then VR<="000"; VG<="000"; VB<="000"; fon:='0'; end if;
	end if;
end if;
end process;

end Behavioral;

