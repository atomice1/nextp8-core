-----------------------------------------------------
------- Copyright (c) Theodoulos Liontakis  2024 ----
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

entity ps2_read_mouse is
	port
	(
		Rx : IN std_logic ;
		PSclk : IN std_logic ;
		Rxo : OUT std_logic ;
		PSclko : OUT std_logic ;
		clk, reset, rack : IN std_logic ;
		init_flag : out std_logic_vector (1 downto 0);
		data_ready : buffer std_logic:='0';
		data_out :OUT std_logic_vector (7 downto 0)
	);
end ps2_read_mouse;


Architecture Behavior of ps2_read_mouse is

Signal inb: std_logic_vector(9 downto 1);  
Signal fdiv: natural range 0 to 2047 :=0;
signal rstate,istate: natural range 0 to 15 :=0 ;
Signal initi,k0,k1,k2,k3,k4: std_logic:='1';
constant init:std_logic_vector(9 downto 0):="1011110100";
Signal inhibit:std_logic;
begin

init_flag<=inhibit&initi;

process (clk,PSclk,reset)
begin
	if reset='1' then 
		data_ready<='0'; rstate<=0; initi<='1'; istate<=0; inhibit<='0'; fdiv<=0; PSclko<='Z'; rxo<='Z';
	elsif  falling_edge(clk) then
		if initi='1' then 
			if inhibit='0' and fdiv<366 then
				psclko<='0'; rxo<='0'; fdiv<=fdiv+1;
			else	
				if inhibit='0' then 
					inhibit<='1'; istate<=0; psclko<='Z'; 
				elsif (k0='1') and ((k1 or k2 or k3 or k4)='0') then
					if istate=10 then rxo<='Z'; initi<='0'; else Rxo<=init(istate); istate<=istate+1; end if;
				end if;
			end if;
		else
			if (data_ready='0') and (k0='1') and ((k1 or k2 or k3 or k4)='0') then	
				if rstate=0 and Rx='0' then
					rstate<=1; 
				elsif rstate>0 and rstate<10 then
					inb(rstate)<=Rx;
					rstate<=rstate+1;
				elsif rstate=10 and Rx='1' then
					rstate<=0;
					data_out<=inb(8 downto 1);
					data_ready<='1'; 
				else
					rstate<=0;
				end if;
			end if;
			if rack='1' then data_ready<='0'; end if;
		end if;
		k4<=PSclk; k3<=k4; k2<=k3;	k1<=k2;	k0<=k1;
	end if;
end process;

end behavior;
