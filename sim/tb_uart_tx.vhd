-- Testbench: UART Transmitter
-- Tests: 0x55, 0x00, 0xFF patterns + back-to-back transmission
-- Verifies tx_out at baud centers, reconstructs bytes

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_uart_tx is
end entity tb_uart_tx;

architecture sim of tb_uart_tx is
    constant CLK_PERIOD : time := 10 ns;
    constant CLK_FREQ   : positive := 100_000_000;  -- 100 MHz for faster sim
    constant BAUD_RATE  : positive := 1_000_000;     -- 1 Mbaud for faster sim
    constant BAUD_DIV   : positive := CLK_FREQ / BAUD_RATE;  -- 100 clocks
    constant BIT_PERIOD : time := CLK_PERIOD * BAUD_DIV;

    signal clk      : std_logic := '0';
    signal rst      : std_logic := '1';
    signal data_in  : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_start : std_logic := '0';
    signal tx_busy  : std_logic;
    signal tx_out   : std_logic;

    signal test_pass : boolean := true;

    -- Captured byte from receiver process
    signal rx_byte    : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_done    : std_logic := '0';
    signal rx_count   : integer := 0;

begin

    clk <= not clk after CLK_PERIOD / 2;

    uut: entity work.uart_tx
        generic map (
            CLK_FREQ  => CLK_FREQ,
            BAUD_RATE => BAUD_RATE
        )
        port map (
            clk      => clk,
            rst      => rst,
            data_in  => data_in,
            tx_start => tx_start,
            tx_busy  => tx_busy,
            tx_out   => tx_out
        );

    -- Receiver process: continuously captures bytes from tx_out
    rx_proc: process
        variable byte_val : std_logic_vector(7 downto 0);
    begin
        loop
            rx_done <= '0';
            -- Wait for start bit (falling edge from '1' to '0')
            wait until falling_edge(tx_out);
            -- Wait to center of start bit
            wait for BIT_PERIOD / 2;
            -- Sample 8 data bits (LSB first)
            for i in 0 to 7 loop
                wait for BIT_PERIOD;
                byte_val(i) := tx_out;
            end loop;
            -- Wait through stop bit
            wait for BIT_PERIOD;
            -- Output captured byte
            rx_byte  <= byte_val;
            rx_done  <= '1';
            rx_count <= rx_count + 1;
            wait for CLK_PERIOD;
        end loop;
    end process;

    -- Stimulus process
    stim_proc: process
        variable expected_count : integer := 0;
    begin
        report "=== UART TX Testbench ===" severity note;

        -- Reset
        rst <= '1';
        wait for CLK_PERIOD * 2;
        rst <= '0';
        wait for CLK_PERIOD * 2;

        -- Verify idle state
        assert tx_out = '1' report "FAIL: tx_out not high at idle" severity error;
        assert tx_busy = '0' report "FAIL: tx_busy asserted at idle" severity error;

        -----------------------------------------------------------------------
        -- Test 1: Send 0x55 (alternating bits)
        -----------------------------------------------------------------------
        report "--- Test 1: Send 0x55 ---" severity note;
        data_in  <= x"55";
        tx_start <= '1';
        wait for CLK_PERIOD;
        tx_start <= '0';

        expected_count := rx_count + 1;
        wait until rx_count = expected_count;
        wait for 1 ns;
        if rx_byte /= x"55" then
            report "FAIL: Expected 0x55, got 0x" & to_hstring(unsigned(rx_byte)) severity error;
            test_pass <= false;
        else
            report "Test 1 PASSED: 0x55 received correctly" severity note;
        end if;

        -- Wait for TX to finish (stop bit)
        wait until tx_busy = '0';
        wait for CLK_PERIOD * 2;

        -----------------------------------------------------------------------
        -- Test 2: Send 0x00
        -----------------------------------------------------------------------
        report "--- Test 2: Send 0x00 ---" severity note;
        data_in  <= x"00";
        tx_start <= '1';
        wait for CLK_PERIOD;
        tx_start <= '0';

        expected_count := rx_count + 1;
        wait until rx_count = expected_count;
        wait for 1 ns;
        if rx_byte /= x"00" then
            report "FAIL: Expected 0x00, got 0x" & to_hstring(unsigned(rx_byte)) severity error;
            test_pass <= false;
        else
            report "Test 2 PASSED: 0x00 received correctly" severity note;
        end if;

        wait until tx_busy = '0';
        wait for CLK_PERIOD * 2;

        -----------------------------------------------------------------------
        -- Test 3: Send 0xFF
        -----------------------------------------------------------------------
        report "--- Test 3: Send 0xFF ---" severity note;
        data_in  <= x"FF";
        tx_start <= '1';
        wait for CLK_PERIOD;
        tx_start <= '0';

        expected_count := rx_count + 1;
        wait until rx_count = expected_count;
        wait for 1 ns;
        if rx_byte /= x"FF" then
            report "FAIL: Expected 0xFF, got 0x" & to_hstring(unsigned(rx_byte)) severity error;
            test_pass <= false;
        else
            report "Test 3 PASSED: 0xFF received correctly" severity note;
        end if;

        wait until tx_busy = '0';
        wait for CLK_PERIOD * 2;

        -----------------------------------------------------------------------
        -- Test 4: Back-to-back (0xA5 then 0x5A)
        -----------------------------------------------------------------------
        report "--- Test 4: Back-to-back ---" severity note;
        data_in  <= x"A5";
        tx_start <= '1';
        wait for CLK_PERIOD;
        tx_start <= '0';

        expected_count := rx_count + 1;
        wait until rx_count = expected_count;
        wait for 1 ns;
        if rx_byte /= x"A5" then
            report "FAIL: Expected 0xA5" severity error;
            test_pass <= false;
        end if;

        -- Wait for TX idle, then immediately start next byte
        wait until tx_busy = '0';
        data_in  <= x"5A";
        tx_start <= '1';
        wait for CLK_PERIOD;
        tx_start <= '0';

        expected_count := rx_count + 1;
        wait until rx_count = expected_count;
        wait for 1 ns;
        if rx_byte /= x"5A" then
            report "FAIL: Expected 0x5A" severity error;
            test_pass <= false;
        else
            report "Test 4 PASSED: Back-to-back correct" severity note;
        end if;

        wait for CLK_PERIOD * 4;

        -----------------------------------------------------------------------
        -- Summary
        -----------------------------------------------------------------------
        if test_pass then
            report "=== ALL UART TX TESTS PASSED ===" severity note;
        else
            report "=== UART TX TESTS FAILED ===" severity error;
        end if;

        wait;
    end process;

end architecture sim;
