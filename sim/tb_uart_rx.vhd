-- Testbench: UART Receiver
-- Tests: 0x55, 0xAA, back-to-back, framing error (bad stop bit)
-- Drives rx_in at baud timing, verifies data_out/rx_valid/rx_error

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_uart_rx is
end entity tb_uart_rx;

architecture sim of tb_uart_rx is
    constant CLK_PERIOD : time := 10 ns;
    constant CLK_FREQ   : positive := 100_000_000;
    constant BAUD_RATE  : positive := 1_000_000;
    constant BIT_PERIOD : time := 1 us;  -- 1/1M

    signal clk      : std_logic := '0';
    signal rst      : std_logic := '1';
    signal rx_in    : std_logic := '1';  -- Idle high
    signal data_out : std_logic_vector(7 downto 0);
    signal rx_valid : std_logic;
    signal rx_error : std_logic;

    signal test_pass : boolean := true;

    -- Capture signals from monitor process
    signal cap_data   : std_logic_vector(7 downto 0) := (others => '0');
    signal cap_valid  : std_logic := '0';
    signal cap_error  : std_logic := '0';
    signal cap_count  : integer := 0;

    -- Procedure to send a byte on rx_in (8N1, LSB first)
    procedure send_byte(
        signal rx_line : out std_logic;
        constant data  : in std_logic_vector(7 downto 0);
        constant bad_stop : in boolean := false
    ) is
    begin
        -- Start bit
        rx_line <= '0';
        wait for BIT_PERIOD;
        -- Data bits (LSB first)
        for i in 0 to 7 loop
            rx_line <= data(i);
            wait for BIT_PERIOD;
        end loop;
        -- Stop bit
        if bad_stop then
            rx_line <= '0';  -- Framing error
        else
            rx_line <= '1';
        end if;
        wait for BIT_PERIOD;
        -- Return to idle
        rx_line <= '1';
    end procedure;

begin

    clk <= not clk after CLK_PERIOD / 2;

    uut: entity work.uart_rx
        generic map (
            CLK_FREQ  => CLK_FREQ,
            BAUD_RATE => BAUD_RATE
        )
        port map (
            clk      => clk,
            rst      => rst,
            rx_in    => rx_in,
            data_out => data_out,
            rx_valid => rx_valid,
            rx_error => rx_error
        );

    -- Monitor process: captures rx_valid/rx_error events
    monitor_proc: process
    begin
        loop
            wait until rx_valid = '1' or rx_error = '1';
            cap_data  <= data_out;
            cap_valid <= rx_valid;
            cap_error <= rx_error;
            cap_count <= cap_count + 1;
            wait for CLK_PERIOD;
        end loop;
    end process;

    -- Stimulus process
    stim_proc: process
        variable expected_count : integer;
    begin
        report "=== UART RX Testbench ===" severity note;

        -- Reset
        rst <= '1';
        wait for CLK_PERIOD * 5;
        rst <= '0';
        wait for CLK_PERIOD * 5;

        -----------------------------------------------------------------------
        -- Test 1: Receive 0x55
        -----------------------------------------------------------------------
        report "--- Test 1: Receive 0x55 ---" severity note;
        expected_count := cap_count + 1;
        send_byte(rx_in, x"55");

        wait until cap_count = expected_count for BIT_PERIOD * 5;
        wait for 1 ns;
        if cap_count /= expected_count then
            report "FAIL: No response for 0x55" severity error;
            test_pass <= false;
        elsif cap_valid /= '1' then
            report "FAIL: rx_valid not asserted for 0x55" severity error;
            test_pass <= false;
        elsif cap_data /= x"55" then
            report "FAIL: Expected 0x55, got 0x" & to_hstring(unsigned(cap_data)) severity error;
            test_pass <= false;
        else
            report "Test 1 PASSED: 0x55" severity note;
        end if;
        wait for BIT_PERIOD * 2;

        -----------------------------------------------------------------------
        -- Test 2: Receive 0xAA
        -----------------------------------------------------------------------
        report "--- Test 2: Receive 0xAA ---" severity note;
        expected_count := cap_count + 1;
        send_byte(rx_in, x"AA");

        wait until cap_count = expected_count for BIT_PERIOD * 5;
        wait for 1 ns;
        if cap_count /= expected_count then
            report "FAIL: No response for 0xAA" severity error;
            test_pass <= false;
        elsif cap_valid /= '1' then
            report "FAIL: rx_valid not asserted for 0xAA" severity error;
            test_pass <= false;
        elsif cap_data /= x"AA" then
            report "FAIL: Expected 0xAA, got 0x" & to_hstring(unsigned(cap_data)) severity error;
            test_pass <= false;
        else
            report "Test 2 PASSED: 0xAA" severity note;
        end if;
        wait for BIT_PERIOD * 2;

        -----------------------------------------------------------------------
        -- Test 3: Framing error (bad stop bit)
        -----------------------------------------------------------------------
        report "--- Test 3: Framing error ---" severity note;
        expected_count := cap_count + 1;
        send_byte(rx_in, x"42", bad_stop => true);

        wait until cap_count = expected_count for BIT_PERIOD * 5;
        wait for 1 ns;
        if cap_count /= expected_count then
            report "FAIL: No response for framing error test" severity error;
            test_pass <= false;
        elsif cap_error /= '1' then
            report "FAIL: rx_error not asserted on bad stop bit" severity error;
            test_pass <= false;
        else
            report "Test 3 PASSED: framing error detected" severity note;
        end if;
        wait for BIT_PERIOD * 2;

        -----------------------------------------------------------------------
        -- Test 4: Back-to-back (0xDE then 0xAD)
        -----------------------------------------------------------------------
        report "--- Test 4: Back-to-back ---" severity note;
        expected_count := cap_count + 1;
        send_byte(rx_in, x"DE");
        wait until cap_count = expected_count for BIT_PERIOD * 5;
        wait for 1 ns;
        if cap_data /= x"DE" then
            report "FAIL: Expected 0xDE" severity error;
            test_pass <= false;
        end if;

        expected_count := cap_count + 1;
        send_byte(rx_in, x"AD");
        wait until cap_count = expected_count for BIT_PERIOD * 5;
        wait for 1 ns;
        if cap_data /= x"AD" then
            report "FAIL: Expected 0xAD" severity error;
            test_pass <= false;
        else
            report "Test 4 PASSED: back-to-back" severity note;
        end if;
        wait for BIT_PERIOD * 2;

        -----------------------------------------------------------------------
        -- Summary
        -----------------------------------------------------------------------
        if test_pass then
            report "=== ALL UART RX TESTS PASSED ===" severity note;
        else
            report "=== UART RX TESTS FAILED ===" severity error;
        end if;

        wait;
    end process;

end architecture sim;
