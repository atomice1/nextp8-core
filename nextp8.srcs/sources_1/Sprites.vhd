----------------------------------------------------------------------------------
-- Company: 
-- Engineer: Theodoulos Liontakis 
-- 
-- Create Date: 05/06/2024 04:33:04 PM
-- Design Name: Sprites for QL 
-- Module Name: Sprites - Behavioral
-- Project Name: 
-- Target Devices: Spectrum Next KS2
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------
-----------------------------------------------------
------- Copyright (c) Theodoulos Liontakis  2024 -------------------
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

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
USE ieee.std_logic_unsigned.all;
USE ieee.numeric_std.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity Sprites is
    generic(
        spno: natural range 0 to 30 :=28
        );
    Port ( clk : in STD_LOGIC;
           reset : in STD_LOGIC;
           raddr : out natural range 0 to 511;
           rq    : in std_logic_vector(63 downto 0);
           SPRB,SPRG,SPRR,SPRF : out std_logic;
           spron : out std_logic
           );
end Sprites;

 

architecture Behavioral of Sprites is

constant l1:natural:=36; --12
constant lno:natural:=768;
constant p1:natural :=299;
constant pno:natural:=1024;
constant p2:natural:=p1+pno;
constant l2:natural:=l1+lno;  --
constant xdim:natural:=1343; --pixels-1
constant ydim:natural:=806; --lines
 attribute ramstyle : string;
--type dist is array (0 to spno-1) of natural range 0 to 511;
 signal state: std_LOGIC_VECTOR(1 downto 0):="00";

begin

process (clk)


type sprite_transp_data is array (spno-1 downto 0) of std_logic_vector(15 downto 0);
variable transp:sprite_transp_data;
--    attribute ramstyle of transp : variable is "DISTRIBUTED";
type sprite_dim is array (0 to spno-1) of natural range 0 to 255;
type sprite_enable is array (0 to spno-1) of std_logic;
variable spx,spy: sprite_dim; 
--    attribute ramstyle of spx : variable is "DISTRIBUTED";
--    attribute ramstyle of spy : variable is "DISTRIBUTED";
 variable spen:sprite_enable;
 variable blvec:natural range 0 to spno:=spno;
 variable coldata: std_LOGIC_VECTOR(3 downto 0);
 variable l:std_LOGIC_VECTOR(1 downto 0);
 variable v: natural range 0 to 31:=0;
 variable pixe,ln,px: natural range 0 to 511:=0;
 variable vlin: natural range 0 to 511:=0;
 variable d1,d2: natural  range 0 to 511;
 variable dx,dy: natural  range 0 to 15;

begin


if falling_edge(clk) then
    if reset='1' then
	   pixe:=0;	vlin:=0;
	   l:="00"; blvec:=spno; state<="00"; 
	else
	   state<=state+1;
	   case state is
	   when "00" =>
	        if blvec/=spno then
                coldata:=RQ(63-dx*4 downto 60-dx*4);
                sprf<=coldata(3);
                sprR<=coldata(2); sprG<=coldata(1);  sprB<=coldata(0);
                spron<='1';
            else
                spron<='0';
            end if;
	   
            if pixe>=xdim/4 then
                pixe:=0;
                if l<"10" then l:=l+1; else l:="00"; 
			     if vlin<ydim/3 then vlin:=vlin+1; else vlin:=0; end if; end if;
            else
                pixe:=pixe+1; 
            end if;
            px:=pixe-p1/4; ln:=vlin-l1/3;
            if pixe<spno/2 then --sprite paramweters
                raddr<=pixe;
            end if;
--            for i in spno-1 downto 0 loop
--                 d2(i)<=ln-spy(i); --d1(i)<=px-spx(i);
--            end loop;
        when "01" =>
            if pixe<spno/2 then 
                spen(1+pixe*2):=RQ(32);  
                spY(1+pixe*2):=to_integer(unsigned(RQ(32+23 downto 32+16)));
                spX(1+pixe*2):=to_integer(unsigned(RQ(32+15 downto 32+8)));
                spen(pixe*2):=RQ(0);
                spY(pixe*2):=to_integer(unsigned(RQ(23 downto 16)));
                spX(pixe*2):=to_integer(unsigned(RQ(15 downto 8)));
            elsif pixe<=spno+spno/2 and vlin>=l1/3 and vlin<l2/3 then  
                v:=pixe-spno/2;
                raddr<=16+v*16+(ln-spy(v));
            end if;

        when "10" =>
           blvec:=spno;
		   if pixe>=spno/2 and pixe<=spno+spno/2 and vlin>=l1/3 and vlin<l2/3 then
				v:=pixe-spno/2;
				for i in 0 to 15 loop
					transp(v)(i):=not (RQ(63-i*4) and RQ(62-i*4) and RQ(61-i*4) and RQ(60-i*4));
				end loop;
		   end if;
    
        when "11" =>
            --if pixe>p1+1 and pixe<p2+2 and vlin>=l1 and vlin<l2 then
            for i in spno-1 downto 0 loop
                d1:=px-spx(i); d2:=ln-spy(i);
                if (d1<16)  and (d2<16)  and (spen(i)='1')  and transp(i)(d1)='1' then blvec:=i; dx:=d1; dy:=d2; end if;
            end loop;
			--end if;
        
            if blvec<spno then raddr<=16+blvec*16+dy; end if;

        end case;
    end if;
end if;
end process;

end Behavioral;



