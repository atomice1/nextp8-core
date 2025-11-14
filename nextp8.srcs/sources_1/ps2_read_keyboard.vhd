------------------------------------------------------------------
-- ps2_read_keyboard.vhd
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

-- PS/2 Input Receiver (VHDL)
-- Implements filtered PS/2 clock, falling-edge detection,
-- 11-bit frame receiver (start, 8 data LSB-first, parity, stop),
-- odd parity check, and single-cycle VALID/ERROR pulses.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ps2_read_keyboard is
  generic(
    FILTER_BITS : integer := 8  -- length of PS/2 clock debounce filter shift register
  );
  port(
    CLK      : in  std_logic;                 -- system clock
    nRESET   : in  std_logic;                 -- async active-low reset
    PS2_CLK  : in  std_logic;                 -- raw PS/2 clock
    PS2_DATA : in  std_logic;                 -- raw PS/2 data

    DATA     : out std_logic_vector(7 downto 0); -- received byte (valid for one CLK)
    VALID    : out std_logic;                    -- one-cycle pulse when DATA is valid
    ERROR    : out std_logic                     -- one-cycle pulse on framing/parity error
  );
end entity;

architecture rtl of ps2_read_keyboard is

  -- Synchronizers for asynchronous PS/2 signals (to system CLK domain)
  signal ps2c_sync  : std_logic_vector(1 downto 0) := (others => '1');
  signal ps2d_sync  : std_logic_vector(1 downto 0) := (others => '1');

  -- Debounce/filter shift register for PS/2 clock
  subtype filter_vec_t is std_logic_vector(FILTER_BITS-1 downto 0);
  signal clk_filter : filter_vec_t := (others => '1');

  -- Filtered PS/2 clock and edge detect
  signal ps2c_filt     : std_logic := '1';
  signal ps2c_filt_d   : std_logic := '1';
  signal ps2c_fall_p   : std_logic := '0';  -- single-cycle pulse on filtered falling edge

  -- Receiver state machine: 0..10 (idle/start, 8 data, parity, stop)
  signal bit_state     : unsigned(3 downto 0) := (others => '0'); -- 0..10
  signal parity_acc    : std_logic := '0';    -- odd parity accumulator
  signal shift         : std_logic_vector(7 downto 0) := (others => '0');
  signal data_reg      : std_logic_vector(7 downto 0) := (others => '0');

  -- Output pulses (registered)
  signal valid_pulse   : std_logic := '0';
  signal error_pulse   : std_logic := '0';

begin

  -- Drive outputs
  DATA  <= data_reg;
  VALID <= valid_pulse;
  ERROR <= error_pulse;

  ------------------------------------------------------------------------------
  -- Asynchronous input synchronizers (2-FF) to CLK domain
  ------------------------------------------------------------------------------
  sync_proc : process(CLK, nRESET)
  begin
    if nRESET = '0' then
      ps2c_sync <= (others => '1');
      ps2d_sync <= (others => '1');
    elsif rising_edge(CLK) then
      ps2c_sync(0) <= PS2_CLK;
      ps2c_sync(1) <= ps2c_sync(0);

      ps2d_sync(0) <= PS2_DATA;
      ps2d_sync(1) <= ps2d_sync(0);
    end if;
  end process;

  ------------------------------------------------------------------------------
  -- PS/2 clock filter (debounce) + falling-edge detection (single-cycle pulse)
  ------------------------------------------------------------------------------
  filter_proc : process(CLK, nRESET)
    variable all_ones : boolean;
    variable all_zeros: boolean;
  begin
    if nRESET = '0' then
      clk_filter   <= (others => '1');
      ps2c_filt    <= '1';
      ps2c_filt_d  <= '1';
      ps2c_fall_p  <= '0';
    elsif rising_edge(CLK) then
      -- shift in the synchronized PS/2 clock
      clk_filter <= clk_filter(FILTER_BITS-2 downto 0) & ps2c_sync(1);

      -- resolve filtered level
      all_ones  := (clk_filter = (clk_filter'range => '1'));
      all_zeros := (clk_filter = (clk_filter'range => '0'));

      if all_ones then
        ps2c_filt <= '1';
      elsif all_zeros then
        ps2c_filt <= '0';
      else
        -- retain previous ps2c_filt when not unanimously 0/1
        ps2c_filt <= ps2c_filt;
      end if;

      -- edge detect (single-cycle pulse on high->low)
      ps2c_filt_d <= ps2c_filt;
      if (ps2c_filt_d = '1' and ps2c_filt = '0') then
        ps2c_fall_p <= '1';
      else
        ps2c_fall_p <= '0';
      end if;
    end if;
  end process;

  ------------------------------------------------------------------------------
  -- PS/2 receiver FSM (samples on filtered falling edges)
  -- Frame: start(0), d0..d7 (LSB first), parity (odd), stop(1)
  ------------------------------------------------------------------------------
  rx_proc : process(CLK, nRESET)
    variable sampled_bit : std_logic;
    variable i           : integer;
  begin
    if nRESET = '0' then
      bit_state   <= (others => '0');
      parity_acc  <= '0';
      shift       <= (others => '0');
      data_reg    <= (others => '0');
      valid_pulse <= '0';
      error_pulse <= '0';
    elsif rising_edge(CLK) then
      -- default: pulses deassert unless set this cycle
      valid_pulse <= '0';
      error_pulse <= '0';

      -- sample PS/2 data only on the filtered falling edge of PS/2 clock
      if ps2c_fall_p = '1' then
        sampled_bit := ps2d_sync(1);

        case to_integer(bit_state) is

          -- State 0: Idle/Start detection (expect start bit = '0')
          when 0 =>
            if sampled_bit = '0' then
              parity_acc <= '0';          -- reset parity accumulator
              bit_state  <= to_unsigned(1, bit_state'length);
            else
              -- still idle
              bit_state  <= to_unsigned(0, bit_state'length);
            end if;

          -- States 1..8: Data bits (LSB first)
          when 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 =>
            -- shift incoming bit into MSB side of 8-bit shift reg
            shift <= sampled_bit & shift(7 downto 1);
            -- accumulate odd parity (xor of all data + parity)
            parity_acc <= parity_acc xor sampled_bit;
            bit_state <= bit_state + 1;

          -- State 9: Parity bit
          when 9 =>
            parity_acc <= parity_acc xor sampled_bit;     -- include parity bit
            bit_state <= to_unsigned(10, bit_state'length);

          -- State 10: Stop bit and frame check
          when 10 =>
            if (sampled_bit = '1') and (parity_acc = '1') then
              -- stop=1 and odd parity correct
              data_reg <= shift(7 downto 0);
              valid_pulse <= '1';
            else
              error_pulse <= '1';
            end if;

            -- return to idle for next frame
            bit_state  <= (others => '0');
            parity_acc <= '0';

          when others =>
            -- safety: return to idle
            bit_state  <= (others => '0');
            parity_acc <= '0';
        end case;
      end if; -- ps2c_fall_p
    end if;
  end process;

end architecture;