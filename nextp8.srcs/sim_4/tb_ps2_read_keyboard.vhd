-- filepath: /home/chris/code/nextp8-dev/nextp8-core/nextp8.srcs/sim_1/new/tb_ps2_read_keyboard.vhd
-- PS/2 Read Keyboard Testbench
-- Tests the ps2_read_keyboard module by driving PS/2 protocol frames
-- with various scan codes and verifying VALID/ERROR outputs.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_ps2_read_keyboard is
end entity;

architecture sim of tb_ps2_read_keyboard is
  signal reset_latch : std_logic := '0';
  -- Latched outputs for analysis
  signal latched_data : std_logic_vector(7 downto 0) := (others => '0');
  signal latched_valid : std_logic := '0';
  signal latched_error : std_logic := '0';
  signal prev_valid : std_logic := '0';
  signal prev_error : std_logic := '0';

  -- Component declaration
  component ps2_read_keyboard is
    generic(
      FILTER_BITS : integer := 8
    );
    port(
      CLK      : in  std_logic;
      nRESET   : in  std_logic;
      PS2_CLK  : in  std_logic;
      PS2_DATA : in  std_logic;
      DATA     : out std_logic_vector(7 downto 0);
      VALID    : out std_logic;
      ERROR    : out std_logic
    );
  end component;

  -- Testbench signals
  constant CLK_PERIOD : time := 10 ns;  -- 100 MHz system clock
  constant PS2_CLK_PERIOD : time := 100 us;  -- ~10 kHz PS/2 clock (typical range 10-16.7 kHz)

  signal clk      : std_logic := '0';
  signal nreset   : std_logic := '0';
  signal ps2_clk  : std_logic := '1';
  signal ps2_data : std_logic := '1';
  signal data_out : std_logic_vector(7 downto 0);
  signal valid    : std_logic;
  signal error_flag    : std_logic;

  signal test_done : boolean := false;

  -- Procedure to send one PS/2 frame (11 bits: start, 8 data LSB-first, parity, stop)
  procedure send_ps2_byte(
    constant byte_val : in std_logic_vector(7 downto 0);
    signal ps2_clk  : out std_logic;
    signal ps2_data : out std_logic
  ) is
    variable parity : std_logic;
  begin
    -- Calculate odd parity
    parity := '0';
    for i in 0 to 7 loop
      parity := parity xor byte_val(i);
    end loop;
    parity := not parity;  -- odd parity: invert so total 1s = odd

    -- Start bit (0)
    ps2_data <= '0';
    ps2_clk <= '0';
    wait for PS2_CLK_PERIOD / 2;
    ps2_clk <= '1';
    wait for PS2_CLK_PERIOD / 2;

    -- Data bits (LSB first)
    for i in 0 to 7 loop
      ps2_data <= byte_val(i);
      ps2_clk <= '0';
      wait for PS2_CLK_PERIOD / 2;
      ps2_clk <= '1';
      wait for PS2_CLK_PERIOD / 2;
    end loop;

    -- Parity bit
    ps2_data <= parity;
    ps2_clk <= '0';
    wait for PS2_CLK_PERIOD / 2;
    ps2_clk <= '1';
    wait for PS2_CLK_PERIOD / 2;

    -- Stop bit (1)
    ps2_data <= '1';
    ps2_clk <= '0';
    wait for PS2_CLK_PERIOD / 2;
    ps2_clk <= '1';
    wait for PS2_CLK_PERIOD / 2;
  end procedure;

  -- Procedure to send invalid frame (bad stop bit)
  procedure send_ps2_byte_bad_stop(
    constant byte_val : in std_logic_vector(7 downto 0);
    signal ps2_clk  : out std_logic;
    signal ps2_data : out std_logic
  ) is
    variable parity : std_logic;
  begin
    parity := '0';
    for i in 0 to 7 loop
      parity := parity xor byte_val(i);
    end loop;
    parity := not parity;

    -- Start bit
    ps2_data <= '0';
    ps2_clk <= '0';
    wait for PS2_CLK_PERIOD / 2;
    ps2_clk <= '1';
    wait for PS2_CLK_PERIOD / 2;

    -- Data bits
    for i in 0 to 7 loop
      ps2_data <= byte_val(i);
      ps2_clk <= '0';
      wait for PS2_CLK_PERIOD / 2;
      ps2_clk <= '1';
      wait for PS2_CLK_PERIOD / 2;
    end loop;

    -- Parity bit
    ps2_data <= parity;
    ps2_clk <= '0';
    wait for PS2_CLK_PERIOD / 2;
    ps2_clk <= '1';
    wait for PS2_CLK_PERIOD / 2;

    -- Bad stop bit (0 instead of 1)
    ps2_data <= '0';
    ps2_clk <= '0';
    wait for PS2_CLK_PERIOD / 2;
    ps2_clk <= '1';
    wait for PS2_CLK_PERIOD / 2;
  end procedure;

  -- Procedure to send invalid frame (bad parity)
  procedure send_ps2_byte_bad_parity(
    constant byte_val : in std_logic_vector(7 downto 0);
    signal ps2_clk  : out std_logic;
    signal ps2_data : out std_logic
  ) is
    variable parity : std_logic;
  begin
    parity := '0';
    for i in 0 to 7 loop
      parity := parity xor byte_val(i);
    end loop;
    -- Intentionally use wrong parity (don't invert)

    -- Start bit
    ps2_data <= '0';
    ps2_clk <= '0';
    wait for PS2_CLK_PERIOD / 2;
    ps2_clk <= '1';
    wait for PS2_CLK_PERIOD / 2;

    -- Data bits
    for i in 0 to 7 loop
      ps2_data <= byte_val(i);
      ps2_clk <= '0';
      wait for PS2_CLK_PERIOD / 2;
      ps2_clk <= '1';
      wait for PS2_CLK_PERIOD / 2;
    end loop;

    -- Bad parity bit
    ps2_data <= parity;
    ps2_clk <= '0';
    wait for PS2_CLK_PERIOD / 2;
    ps2_clk <= '1';
    wait for PS2_CLK_PERIOD / 2;

  -- Stop bit
  ps2_data <= '1';
  ps2_clk <= '0';
  wait for PS2_CLK_PERIOD / 2;
  ps2_clk <= '1';
  wait for PS2_CLK_PERIOD / 2;
  end procedure;

begin
  -- Latch data_out and error_flag on rising edge
  latch_proc : process(clk)
  begin
    if rising_edge(clk) then
      if reset_latch = '1' then
        latched_data <= (others => '0');
        latched_valid <= '0';
        latched_error <= '0';
      else
        -- Latch data_out on valid rising edge
        if (prev_valid = '0' and valid = '1') then
          latched_data <= data_out;
          latched_valid <= '1';
        end if;
        -- Latch error_flag on rising edge
        if (prev_error = '0' and error_flag = '1') then
          latched_error <= '1';
        end if;
      end if;
      prev_valid <= valid;
      prev_error <= error_flag;
    end if;
  end process;

  -- Instantiate DUT
  dut : ps2_read_keyboard
    generic map(
      FILTER_BITS => 8
    )
    port map(
      CLK      => clk,
      nRESET   => nreset,
      PS2_CLK  => ps2_clk,
      PS2_DATA => ps2_data,
      DATA     => data_out,
      VALID    => valid,
      ERROR    => error_flag
    );

  -- Clock generator
  clk_gen : process
  begin
    while not test_done loop
      clk <= '0';
      wait for CLK_PERIOD / 2;
      clk <= '1';
      wait for CLK_PERIOD / 2;
    end loop;
    wait;
  end process;

  -- Stimulus process
  stimulus : process
  begin
    -- Initialize
    ps2_clk <= '1';
    ps2_data <= '1';
    nreset <= '0';
    wait for 100 ns;
    nreset <= '1';
    wait for 200 ns;


  report "Test 1: Send valid scan code 0xF0 (break code)";
  send_ps2_byte(x"F0", ps2_clk, ps2_data);
  wait for 5 us;
  assert (latched_valid = '1') report "Expected VALID=1 for 0xF0" severity error;
  assert (latched_data = x"F0") report "Expected DATA=0xF0" severity error;
  assert (latched_error = '0') report "Expected ERROR=0 for valid frame" severity error;
  -- Reset latches
  reset_latch <= '1';
  wait for CLK_PERIOD;
  reset_latch <= '0';
  wait for CLK_PERIOD;


  report "Test 2: Send valid scan code 0x1C (A key make)";
  send_ps2_byte(x"1C", ps2_clk, ps2_data);
  wait for 5 us;
  assert (latched_valid = '1') report "Expected VALID=1 for 0x1C" severity error;
  assert (latched_data = x"1C") report "Expected DATA=0x1C" severity error;
  assert (latched_error = '0') report "Expected ERROR=0 for valid frame" severity error;
  reset_latch <= '1';
  wait for CLK_PERIOD;
  reset_latch <= '0';
  wait for CLK_PERIOD;


  report "Test 3: Send valid scan code 0x5A (Enter key)";
  send_ps2_byte(x"5A", ps2_clk, ps2_data);
  wait for 5 us;
  assert (latched_valid = '1') report "Expected VALID=1 for 0x5A" severity error;
  assert (latched_data = x"5A") report "Expected DATA=0x5A" severity error;
  assert (latched_error = '0') report "Expected ERROR=0 for valid frame" severity error;
  reset_latch <= '1';
  wait for CLK_PERIOD;
  reset_latch <= '0';
  wait for CLK_PERIOD;


  report "Test 4: Send frame with bad stop bit";
  send_ps2_byte_bad_stop(x"AA", ps2_clk, ps2_data);
  wait for 5 us;
  assert (latched_error = '1') report "Expected ERROR=1 for bad stop bit" severity error;
  assert (latched_valid = '0') report "Expected VALID=0 for bad stop bit" severity error;
  reset_latch <= '1';
  wait for CLK_PERIOD;
  reset_latch <= '0';
  wait for CLK_PERIOD;


  report "Test 5: Send frame with bad parity";
  send_ps2_byte_bad_parity(x"55", ps2_clk, ps2_data);
  wait for 5 us;
  assert (latched_error = '1') report "Expected ERROR=1 for bad parity" severity error;
  assert (latched_valid = '0') report "Expected VALID=0 for bad parity" severity error;
  reset_latch <= '1';
  wait for CLK_PERIOD;
  reset_latch <= '0';
  wait for CLK_PERIOD;


  report "Test 6: Send sequence (0xF0, 0x1C - A key break)";
  send_ps2_byte(x"F0", ps2_clk, ps2_data);
  wait for 5 us;
  assert (latched_valid = '1') report "Expected VALID=1 for 0xF0 in sequence" severity error;
  assert (latched_data = x"F0") report "Expected DATA=0xF0 in sequence" severity error;
  reset_latch <= '1';
  wait for CLK_PERIOD;
  reset_latch <= '0';
  wait for CLK_PERIOD;
  send_ps2_byte(x"1C", ps2_clk, ps2_data);
  wait for 5 us;
  assert (latched_valid = '1') report "Expected VALID=1 for 0x1C in sequence" severity error;
  assert (latched_data = x"1C") report "Expected DATA=0x1C in sequence" severity error;
  reset_latch <= '1';
  wait for CLK_PERIOD;
  reset_latch <= '0';
  wait for CLK_PERIOD;


  report "Test 7: Send all zeros (0x00)";
  send_ps2_byte(x"00", ps2_clk, ps2_data);
  wait for 5 us;
  assert (latched_valid = '1') report "Expected VALID=1 for 0x00" severity error;
  assert (latched_data = x"00") report "Expected DATA=0x00" severity error;
  reset_latch <= '1';
  wait for CLK_PERIOD;
  reset_latch <= '0';
  wait for CLK_PERIOD;


  report "Test 8: Send all ones (0xFF)";
  send_ps2_byte(x"FF", ps2_clk, ps2_data);
  wait for 5 us;
  assert (latched_valid = '1') report "Expected VALID=1 for 0xFF" severity error;
  assert (latched_data = x"FF") report "Expected DATA=0xFF" severity error;
  reset_latch <= '1';
  wait for CLK_PERIOD;
  reset_latch <= '0';
  wait for CLK_PERIOD;

    wait for 100 ns;
    report "All tests completed successfully!";
    test_done <= true;
    wait;
  end process;

end architecture;