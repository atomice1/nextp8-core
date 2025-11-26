-- nextp8 FPGA Top Level for ZX Spectrum Next Issue 4 PCB
-- Copyright 2025 Chris January
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

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

library UNISIM;
use UNISIM.VComponents.all;

entity nextp8_top_issue4 is
   port (
      -- Clocks
      clock_50_i        : in    std_logic;

      -- SRAM (IS61WV204816BLL-10BLI)
      ram_addr_o        : out   std_logic_vector(20 downto 0)  := (others => '0');
      ram_data_io       : inout std_logic_vector(15 downto 0)  := (others => 'Z');
      ram_lb_n_o        : out   std_logic                      := '1';
      ram_ub_n_o        : out   std_logic                      := '1';
      ram_oe_n_o        : out   std_logic                      := '1';
      ram_we_n_o        : out   std_logic                      := '1';
      ram_cs_n_o        : out   std_logic                      := '1';

      -- PS2
      ps2_clk_io        : inout std_logic                      := 'Z';
      ps2_data_io       : inout std_logic                      := 'Z';
      ps2_pin6_io       : inout std_logic                      := 'Z';
      ps2_pin2_io       : inout std_logic                      := 'Z';

      -- SD Card
      sd_cs0_n_o        : out   std_logic                      := '1';
      sd_cs1_n_o        : out   std_logic                      := '1';
      sd_sclk_o         : out   std_logic                      := '0';
      sd_mosi_o         : out   std_logic                      := '0';
      sd_miso_i         : in    std_logic;

      -- Flash
      flash_cs_n_o      : out   std_logic                      := '1';
      flash_sclk_o      : out   std_logic                      := '0';
      flash_mosi_o      : out   std_logic                      := '0';
      flash_miso_i      : in    std_logic;
      flash_wp_o        : out   std_logic                      := '0';
      flash_hold_o      : out   std_logic                      := '1';

      -- Joystick
      joyp1_i           : in    std_logic;
      joyp2_i           : in    std_logic;
      joyp3_i           : in    std_logic;
      joyp4_i           : in    std_logic;
      joyp6_i           : in    std_logic;
      joyp7_o           : out   std_logic                      := '1';
      joyp9_i           : in    std_logic;
      joysel_o          : out   std_logic                      := '0';

      -- Audio
      audioext_l_o      : out   std_logic                      := '0';
      audioext_r_o      : out   std_logic                      := '0';
      audioint_o        : out   std_logic                      := '0';

      -- K7
      ear_port_i        : in    std_logic;
      mic_port_o        : out   std_logic                      := '0';

      -- Buttons
      btn_divmmc_n_i    : in    std_logic;
      btn_multiface_n_i : in    std_logic;
      btn_reset_n_i     : in    std_logic;

      -- Matrix keyboard
      keyb_row_o        : out   std_logic_vector( 7 downto 0)  := (others => 'Z');
      keyb_col_i        : in    std_logic_vector( 6 downto 0);

      -- Bus
      bus_rst_n_io      : inout std_logic                      := 'Z';
      bus_clk35_o       : out   std_logic                      := '1';
      bus_addr_o        : out   std_logic_vector(15 downto 0)  := (others => 'Z');
      bus_data_io       : inout std_logic_vector( 7 downto 0)  := (others => 'Z');
      bus_int_in_i      : in    std_logic;
      bus_int_n_o       : out   std_logic                      := 'Z';
      bus_nmi_n_i       : in    std_logic;
      bus_ramcs_io      : inout std_logic                      := 'Z';
      bus_romcs_i       : in    std_logic;
      bus_wait_n_i      : in    std_logic;
      bus_halt_n_o      : out   std_logic                      := '1';
      bus_iorq_n_o      : out   std_logic                      := '1';
      bus_m1_n_o        : out   std_logic                      := '1';
      bus_mreq_n_o      : out   std_logic                      := '1';
      bus_rd_n_io       : inout std_logic                      := '1';
      bus_wr_n_o        : out   std_logic                      := '1';
      bus_rfsh_n_o      : out   std_logic                      := '1';
      bus_busreq_n_i    : in    std_logic;
      bus_busack_n_o    : out   std_logic                      := '1';
      bus_iorqula_n_i   : in    std_logic;
      bus_y_o           : out   std_logic                      := '1';
      bus_p3_mtr_n_o    : out   std_logic                      := '1';
      bus_p3_drd_n_o    : out   std_logic                      := '1';
      bus_p3_dwr_n_o    : out   std_logic                      := '1';

      -- VGA
      rgb_r_o           : out   std_logic_vector( 3 downto 0)  := (others => '0');
      rgb_g_o           : out   std_logic_vector( 3 downto 0)  := (others => '0');
      rgb_b_o           : out   std_logic_vector( 3 downto 0)  := (others => '0');
      hsync_o           : out   std_logic                      := '1';
      vsync_o           : out   std_logic                      := '1';
      vgaclk_o          : out   std_logic                      := '0';
      vgaclkn_o         : out   std_logic                      := '0';

      -- HDMI
      hdmi_p_o          : out   std_logic_vector(3 downto 0);
      hdmi_n_o          : out   std_logic_vector(3 downto 0);

      -- I2C (RTC and HDMI)
      i2c_scl_io        : inout std_logic                      := 'Z';
      i2c_sda_io        : inout std_logic                      := 'Z';

      -- ESP
      esp_gpio0_io      : inout std_logic                      := 'Z';
      esp_gpio2_io      : inout std_logic                      := 'Z';
      esp_rx_i          : in    std_logic;
      esp_tx_o          : out   std_logic                      := '1';
      esp_cts_n_o       : out   std_logic                      := '1';
      esp_rtr_n_i       : in    std_logic;

      -- PI GPIO
      accel_io          : inout std_logic_vector(27 downto 0)  := (others => 'Z');

      -- XADC Analog to Digital Conversion
      
      XADC_VP           : in    std_logic;
      XADC_VN           : in    std_logic;
      
      XADC_15P          : in    std_logic;
      XADC_15N          : in    std_logic;
      
      XADC_7P           : in    std_logic;
      XADC_7N           : in    std_logic;
      
      adc_control_o     : out   std_logic := 'Z';

      -- Vacant pins
      extras_o          : out   std_logic := 'Z';
      extras_2_io       : inout std_logic := 'Z';
      extras_3_io       : inout std_logic := 'Z'
   );
end entity;

architecture rtl of nextp8_top_issue4 is

   -- Postcode from nextp8 core
   signal postcode_o          : std_logic_vector(5 downto 0);
   
   -- PI GPIO signals for connecting to core
   signal pi_gpio_i           : std_logic_vector(21 downto 0);
   signal pi_gpio_o           : std_logic_vector(21 downto 0);
   signal pi_gpio_en          : std_logic_vector(5 downto 0);

   -- Component declaration for nextp8 core
   component nextp8
   port (
      clock_50_i        : in    std_logic;
      ram_addr_o        : out   std_logic_vector(20 downto 0);
      ram_data_io       : inout std_logic_vector(15 downto 0);
      ram_lb_n_o        : out   std_logic;
      ram_ub_n_o        : out   std_logic;
      ram_oe_n_o        : out   std_logic;
      ram_we_n_o        : out   std_logic;
      ram_cs_n_o        : out   std_logic;
      ps2_clk_io        : inout std_logic;
      ps2_data_io       : inout std_logic;
      ps2_pin6_io       : inout std_logic;
      ps2_pin2_io       : inout std_logic;
      sd_cs0_n_o        : out   std_logic;
      sd_cs1_n_o        : out   std_logic;
      sd_sclk_o         : out   std_logic;
      sd_mosi_o         : out   std_logic;
      sd_miso_i         : in    std_logic;
      joyp1_i           : in    std_logic;
      joyp2_i           : in    std_logic;
      joyp3_i           : in    std_logic;
      joyp4_i           : in    std_logic;
      joyp6_i           : in    std_logic;
      joyp7_o           : out   std_logic;
      joyp9_i           : in    std_logic;
      joysel_o          : out   std_logic;
      audioext_l_o      : out   std_logic;
      audioext_r_o      : out   std_logic;
      ear_port_i        : in    std_logic;
      btn_divmmc_n_i    : in    std_logic;
      btn_multiface_n_i : in    std_logic;
      btn_reset_n_i     : in    std_logic;
      keyb_row_o        : out   std_logic_vector( 7 downto 0);
      keyb_col_i        : in    std_logic_vector( 6 downto 0);
      i2c_scl_io        : inout std_logic;
      i2c_sda_io        : inout std_logic;
      rgb_r_o           : out   std_logic_vector( 3 downto 0);
      rgb_g_o           : out   std_logic_vector( 3 downto 0);
      rgb_b_o           : out   std_logic_vector( 3 downto 0);
      hsync_o           : out   std_logic;
      vsync_o           : out   std_logic;
      vgaclk_o          : out   std_logic;
      vgaclkn_o         : out   std_logic;
      hdmi_p_o          : out   std_logic_vector(3 downto 0);
      hdmi_n_o          : out   std_logic_vector(3 downto 0);
      esp_rx_i          : in    std_logic;
      esp_tx_o          : out   std_logic;
      XADC_VP           : in    std_logic;
      XADC_VN           : in    std_logic;
      XADC_15P          : in    std_logic;
      XADC_15N          : in    std_logic;
      XADC_7P           : in    std_logic;
      XADC_7N           : in    std_logic;
      postcode_o        : out   std_logic_vector(5 downto 0)
   );
   end component;

begin

   -- Fixed bus signal assignments (not used by nextp8)
   bus_rst_n_io      <= 'Z';
   bus_clk35_o       <= 'Z';
   bus_addr_o        <= (others => 'Z');
   bus_data_io       <= (others => 'Z');
   bus_int_n_o       <= 'Z';
   bus_ramcs_io      <= 'Z';
   bus_halt_n_o      <= 'Z';
   bus_iorq_n_o      <= 'Z';
   bus_m1_n_o        <= 'Z';
   bus_mreq_n_o      <= 'Z';
   bus_rd_n_io       <= 'Z';
   bus_wr_n_o        <= 'Z';
   bus_rfsh_n_o      <= 'Z';
   bus_busack_n_o    <= 'Z';
   bus_y_o           <= 'Z';
   bus_p3_mtr_n_o    <= '1';
   bus_p3_drd_n_o    <= '1';
   bus_p3_dwr_n_o    <= '1';

   -- Fixed ESP GPIO assignments (not used by nextp8)
   esp_gpio0_io      <= 'Z';
   esp_gpio2_io      <= 'Z';
   esp_cts_n_o       <= '0';

   -- Fixed K7 and audio assignments (not used by nextp8)
   audioint_o        <= 'Z';
   mic_port_o        <= '0';

   -- Fixed flash assignments (not used by nextp8)
   flash_hold_o      <= '1';
   flash_wp_o        <= '1';
   flash_cs_n_o      <= '1';
   flash_sclk_o      <= '1';
   flash_mosi_o      <= '1';

   -- Fixed vacant pin assignments
   extras_o          <= 'Z';
   extras_2_io       <= 'Z';
   extras_3_io       <= 'Z';
   adc_control_o     <= 'Z';

   -- PI GPIO: bits [21:0] are inputs (read from accel_io), bits [27:22] output postcode
   pi_gpio_i <= accel_io(21 downto 0);
   
   accel_io(27 downto 22) <= postcode_o;
   accel_io(21 downto 0)  <= (others => 'Z');

   ------------------------------------------------------------
   -- NEXTP8 CORE ---------------------------------------------
   ------------------------------------------------------------

   nextp8_inst : nextp8
   port map (
      clock_50_i        => clock_50_i,
      ram_addr_o        => ram_addr_o,
      ram_data_io       => ram_data_io,
      ram_lb_n_o        => ram_lb_n_o,
      ram_ub_n_o        => ram_ub_n_o,
      ram_oe_n_o        => ram_oe_n_o,
      ram_we_n_o        => ram_we_n_o,
      ram_cs_n_o        => ram_cs_n_o,
      ps2_clk_io        => ps2_clk_io,
      ps2_data_io       => ps2_data_io,
      ps2_pin6_io       => ps2_pin6_io,
      ps2_pin2_io       => ps2_pin2_io,
      sd_cs0_n_o        => sd_cs0_n_o,
      sd_cs1_n_o        => sd_cs1_n_o,
      sd_sclk_o         => sd_sclk_o,
      sd_mosi_o         => sd_mosi_o,
      sd_miso_i         => sd_miso_i,
      joyp1_i           => joyp1_i,
      joyp2_i           => joyp2_i,
      joyp3_i           => joyp3_i,
      joyp4_i           => joyp4_i,
      joyp6_i           => joyp6_i,
      joyp7_o           => joyp7_o,
      joyp9_i           => joyp9_i,
      joysel_o          => joysel_o,
      audioext_l_o      => audioext_l_o,
      audioext_r_o      => audioext_r_o,
      ear_port_i        => ear_port_i,
      btn_divmmc_n_i    => btn_divmmc_n_i,
      btn_multiface_n_i => btn_multiface_n_i,
      btn_reset_n_i     => btn_reset_n_i,
      keyb_row_o        => keyb_row_o,
      keyb_col_i        => keyb_col_i,
      i2c_scl_io        => i2c_scl_io,
      i2c_sda_io        => i2c_sda_io,
      rgb_r_o           => rgb_r_o,
      rgb_g_o           => rgb_g_o,
      rgb_b_o           => rgb_b_o,
      hsync_o           => hsync_o,
      vsync_o           => vsync_o,
      vgaclk_o          => vgaclk_o,
      vgaclkn_o         => vgaclkn_o,
      hdmi_p_o          => hdmi_p_o,
      hdmi_n_o          => hdmi_n_o,
      esp_rx_i          => esp_rx_i,
      esp_tx_o          => esp_tx_o,
      XADC_VP           => XADC_VP,
      XADC_VN           => XADC_VN,
      XADC_15P          => XADC_15P,
      XADC_15N          => XADC_15N,
      XADC_7P           => XADC_7P,
      XADC_7N           => XADC_7N,
      postcode_o        => postcode_o
   );

end architecture;
