-- Testbench: MATLAB UART Interface
-- Tests: Valid 110-byte packet (RFC key/nonce), bad checksum, garbage before header
-- Verifies data_ready pulse, checksum_err, field values

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_matlab_uart_interface is
end entity tb_matlab_uart_interface;

architecture sim of tb_matlab_uart_interface is
    constant CLK_PERIOD : time := 10 ns;
    constant CLK_FREQ   : positive := 100_000_000;
    constant BAUD_RATE  : positive := 1_000_000;
    constant BIT_PERIOD : time := 1 us;

    signal clk           : std_logic := '0';
    signal rst           : std_logic := '1';
    signal uart_rx_pin   : std_logic := '1';
    signal key_out       : std_logic_vector(255 downto 0);
    signal nonce_out     : std_logic_vector(95 downto 0);
    signal plaintext_out : std_logic_vector(511 downto 0);
    signal data_ready    : std_logic;
    signal checksum_err  : std_logic;

    signal test_pass : boolean := true;

    -- Monitor signals: capture data_ready/checksum_err asynchronously
    -- (These pulses may fire during uart_send_byte, before wait statements)
    signal got_ready     : std_logic := '0';
    signal got_chk_err   : std_logic := '0';
    signal monitor_clear : std_logic := '0';
    signal event_count   : integer := 0;

    -- RFC 8439 test key: 00:01:02:...:1f
    constant RFC_KEY : std_logic_vector(255 downto 0) :=
        x"1f1e1d1c1b1a191817161514131211100f0e0d0c0b0a09080706050403020100";

    -- RFC 8439 nonce: 00:00:00:00:00:00:00:4a:00:00:00:00
    constant RFC_NONCE : std_logic_vector(95 downto 0) :=
        x"000000004a000000" & x"00000000";

    -- Send a single byte over UART (8N1, LSB first)
    procedure uart_send_byte(
        signal rx_line : out std_logic;
        constant data  : in std_logic_vector(7 downto 0)
    ) is
    begin
        -- Start bit
        rx_line <= '0';
        wait for BIT_PERIOD;
        -- 8 data bits LSB first
        for i in 0 to 7 loop
            rx_line <= data(i);
            wait for BIT_PERIOD;
        end loop;
        -- Stop bit
        rx_line <= '1';
        wait for BIT_PERIOD;
    end procedure;

begin

    clk <= not clk after CLK_PERIOD / 2;

    uut: entity work.matlab_uart_interface
        generic map (
            CLK_FREQ  => CLK_FREQ,
            BAUD_RATE => BAUD_RATE
        )
        port map (
            clk           => clk,
            rst           => rst,
            uart_rx_pin   => uart_rx_pin,
            key_out       => key_out,
            nonce_out     => nonce_out,
            plaintext_out => plaintext_out,
            data_ready    => data_ready,
            checksum_err  => checksum_err
        );

    -- Monitor process: captures data_ready and checksum_err asynchronously
    -- This is needed because the 1-clock pulse may fire during uart_send_byte
    monitor_proc: process
    begin
        loop
            -- Clear flags when requested by stimulus process
            if monitor_clear = '1' then
                got_ready   <= '0';
                got_chk_err <= '0';
            end if;

            wait until data_ready = '1' or checksum_err = '1' or monitor_clear = '1';

            if data_ready = '1' then
                got_ready   <= '1';
                event_count <= event_count + 1;
            end if;
            if checksum_err = '1' then
                got_chk_err <= '1';
                event_count <= event_count + 1;
            end if;

            wait for CLK_PERIOD;
        end loop;
    end process;

    process
        variable xor_sum : std_logic_vector(7 downto 0);
    begin
        report "=== MATLAB UART Interface Testbench ===" severity note;

        -- Reset
        rst <= '1';
        wait for CLK_PERIOD * 5;
        rst <= '0';
        wait for CLK_PERIOD * 5;

        -----------------------------------------------------------------------
        -- Test 1: Valid packet with RFC 8439 key/nonce
        -----------------------------------------------------------------------
        report "--- Test 1: Valid 110-byte packet ---" severity note;

        -- Clear monitor flags
        monitor_clear <= '1';
        wait for CLK_PERIOD;
        monitor_clear <= '0';
        wait for CLK_PERIOD;

        -- Initialize checksum
        xor_sum := x"AA";  -- Header contributes to checksum

        -- Send header
        uart_send_byte(uart_rx_pin, x"AA");

        -- Send 32 key bytes (00, 01, ..., 1F)
        for i in 0 to 31 loop
            uart_send_byte(uart_rx_pin, std_logic_vector(to_unsigned(i, 8)));
            xor_sum := xor_sum xor std_logic_vector(to_unsigned(i, 8));
        end loop;

        -- Send 12 nonce bytes: 00 00 00 00 00 00 00 4A 00 00 00 00
        uart_send_byte(uart_rx_pin, x"00"); xor_sum := xor_sum xor x"00";
        uart_send_byte(uart_rx_pin, x"00"); xor_sum := xor_sum xor x"00";
        uart_send_byte(uart_rx_pin, x"00"); xor_sum := xor_sum xor x"00";
        uart_send_byte(uart_rx_pin, x"00"); xor_sum := xor_sum xor x"00";
        uart_send_byte(uart_rx_pin, x"00"); xor_sum := xor_sum xor x"00";
        uart_send_byte(uart_rx_pin, x"00"); xor_sum := xor_sum xor x"00";
        uart_send_byte(uart_rx_pin, x"00"); xor_sum := xor_sum xor x"00";
        uart_send_byte(uart_rx_pin, x"4A"); xor_sum := xor_sum xor x"4A";
        uart_send_byte(uart_rx_pin, x"00"); xor_sum := xor_sum xor x"00";
        uart_send_byte(uart_rx_pin, x"00"); xor_sum := xor_sum xor x"00";
        uart_send_byte(uart_rx_pin, x"00"); xor_sum := xor_sum xor x"00";
        uart_send_byte(uart_rx_pin, x"00"); xor_sum := xor_sum xor x"00";

        -- Send 64 plaintext bytes (all 0xBB for simplicity)
        for i in 0 to 63 loop
            uart_send_byte(uart_rx_pin, x"BB");
            xor_sum := xor_sum xor x"BB";
        end loop;

        -- Send checksum
        uart_send_byte(uart_rx_pin, xor_sum);

        -- Wait a bit for FSM to finish (pulse may have already fired)
        wait for BIT_PERIOD * 2;

        if got_ready /= '1' then
            report "FAIL: data_ready not asserted" severity error;
            test_pass <= false;
        else
            -- Verify key (bytes 0-31 = 0x00..0x1F, little-endian in vector)
            if key_out /= RFC_KEY then
                report "FAIL: Key mismatch" severity error;
                test_pass <= false;
            else
                report "Key matches RFC 8439" severity note;
            end if;

            -- Verify nonce
            if nonce_out /= RFC_NONCE then
                report "FAIL: Nonce mismatch" severity error;
                report "  Got:    0x" & to_hstring(unsigned(nonce_out)) severity note;
                report "  Expect: 0x" & to_hstring(unsigned(RFC_NONCE)) severity note;
                test_pass <= false;
            else
                report "Nonce matches RFC 8439" severity note;
            end if;

            report "Test 1 PASSED" severity note;
        end if;

        wait for BIT_PERIOD * 5;

        -----------------------------------------------------------------------
        -- Test 2: Bad checksum
        -----------------------------------------------------------------------
        report "--- Test 2: Bad checksum ---" severity note;

        -- Clear monitor flags
        monitor_clear <= '1';
        wait for CLK_PERIOD;
        monitor_clear <= '0';
        wait for CLK_PERIOD;

        -- Header
        uart_send_byte(uart_rx_pin, x"AA");

        -- 32 key bytes (all zeros)
        for i in 0 to 31 loop
            uart_send_byte(uart_rx_pin, x"00");
        end loop;

        -- 12 nonce bytes (all zeros)
        for i in 0 to 11 loop
            uart_send_byte(uart_rx_pin, x"00");
        end loop;

        -- 64 plaintext bytes (all zeros)
        for i in 0 to 63 loop
            uart_send_byte(uart_rx_pin, x"00");
        end loop;

        -- Wrong checksum (correct would be 0xAA since XOR of AA and 108 zeros = AA)
        uart_send_byte(uart_rx_pin, x"FF");

        -- Wait for response
        wait for BIT_PERIOD * 2;

        if got_chk_err /= '1' then
            report "FAIL: checksum_err not asserted on bad checksum" severity error;
            test_pass <= false;
        else
            report "Test 2 PASSED: checksum error detected" severity note;
        end if;

        wait for BIT_PERIOD * 5;

        -----------------------------------------------------------------------
        -- Test 3: Garbage before header (should be ignored)
        -----------------------------------------------------------------------
        report "--- Test 3: Garbage before header ---" severity note;

        -- Clear monitor flags
        monitor_clear <= '1';
        wait for CLK_PERIOD;
        monitor_clear <= '0';
        wait for CLK_PERIOD;

        -- Send garbage bytes
        uart_send_byte(uart_rx_pin, x"11");
        uart_send_byte(uart_rx_pin, x"22");
        uart_send_byte(uart_rx_pin, x"33");

        -- Now send valid header + all-zero data + correct checksum
        uart_send_byte(uart_rx_pin, x"AA");

        for i in 0 to 31 loop
            uart_send_byte(uart_rx_pin, x"00");
        end loop;
        for i in 0 to 11 loop
            uart_send_byte(uart_rx_pin, x"00");
        end loop;
        for i in 0 to 63 loop
            uart_send_byte(uart_rx_pin, x"00");
        end loop;

        -- Checksum: XOR of AA and 108 zeros = AA
        uart_send_byte(uart_rx_pin, x"AA");

        -- Wait for response
        wait for BIT_PERIOD * 2;

        if got_ready /= '1' then
            report "FAIL: data_ready not asserted after garbage" severity error;
            test_pass <= false;
        else
            report "Test 3 PASSED: garbage ignored, valid packet accepted" severity note;
        end if;

        wait for BIT_PERIOD * 5;

        -----------------------------------------------------------------------
        -- Summary
        -----------------------------------------------------------------------
        if test_pass then
            report "=== ALL MATLAB UART INTERFACE TESTS PASSED ===" severity note;
        else
            report "=== MATLAB UART INTERFACE TESTS FAILED ===" severity error;
        end if;

        wait;
    end process;

end architecture sim;
