-----------------------------------------------------
------- Copyright (c) Theodoulos Liontakis  2016 ----
-----------------------------------------------------
--// This source file is free software: you can redistribute it and/or modify 
--// it under the terms of the GNU General Public License as published 
--// by the Free Software Foundation, either version 3 of the License, or 
--// (at your option) any later version. 
--// 
--// This source file is distributed in the hope that it will be useful,
--// but WITHOUT ANY WARRANTY; without even the implied warranty of 
--// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the 
--// GNU General Public License for more details.
--// 
--// You should have received a copy of the GNU General Public License 
--// along with this program.  If not, see <http://www.gnu.org/licenses/>. 
--// 

Library ieee;
USE ieee.std_logic_1164.all;
USE ieee.std_logic_unsigned.all ;
USE ieee.numeric_std.all ;

entity SPI is
	port
	(
		SCLKo : OUT std_logic ;
		MOSI : OUT std_logic:='1';
		MISO  : IN std_logic ;
		clk, reset, w : IN std_logic ;
		readyo : OUT std_logic;
		data_in : IN std_logic_vector (7 downto 0);
		data_out :OUT std_logic_vector (7 downto 0);
		divider: IN std_logic_vector (7 downto 0):="00000010"
	);
end SPI;

Architecture Behavior of SPI is

--constant divider:natural :=10; --36; --  74  124=200Khz
Signal rcounter :std_logic_vector (7 downto 0);
Signal state :natural range 0 to 7:=7;
shared variable ww:std_logic;
Signal SCLK,ready:std_logic;
begin
	SCLKo<=SCLK;
	readyo<=ready;
	process (clk,reset)
	begin
		if (reset='1') then 
			rcounter<="00000000"; ready<='0';
			SCLK<='0'; state<=7; ww:='0';
		elsif  rising_edge(clk) then
			rcounter<=rcounter+1; 
			MOSI<=data_in(state);
			if rcounter>=divider or (ww='0' and w='1' and ready='0') then
				rcounter<="00000000";
				if state=7 and SCLK='0' and ww='0' and w='1' then
					ready<='1'; 
					SCLK<='1';
					ww:=w;
				elsif state=7 and SCLK='1' then
					state<=6;
					data_out(state)<=MISO;
					SCLK<='0';
				elsif state=6 and SCLK='0' then
					SCLK<='1';
				elsif state=6 and SCLK='1' then
					state<=5;
					data_out(state)<=MISO;
					SCLK<='0';
				elsif state=5 and SCLK='0' then
					SCLK<='1';
				elsif state=5 and SCLK='1' then
					state<=4;
					data_out(state)<=MISO;
					SCLK<='0';
				elsif state=4 and SCLK='0' then
					SCLK<='1';
				elsif state=4 and SCLK='1' then
					state<=3;
					data_out(state)<=MISO;
					SCLK<='0';
				elsif state=3 and SCLK='0' then
					SCLK<='1';
				elsif state=3 and SCLK='1' then
					state<=2;
					data_out(state)<=MISO;
					SCLK<='0';
				elsif state=2 and SCLK='0' then
					SCLK<='1';
				elsif state=2 and SCLK='1' then
					state<=1;
					data_out(state)<=MISO;
					SCLK<='0';
				elsif state=1 and SCLK='0' then
					SCLK<='1';
				elsif state=1 and SCLK='1' then
					state<=0;
					data_out(state)<=MISO;
					SCLK<='0';
				elsif state=0 and SCLK='0' then
					SCLK<='1';
				elsif state=0 and SCLK='1' then
					data_out(state)<=MISO;
					SCLK<='0';
					state<=7;
					ready<='0';
					ww:=w;
				else	
					SCLK<='0';
					ready<='0';
					ww:=w;
				end if;
			end if;
		end if;
	end process;
end behavior;