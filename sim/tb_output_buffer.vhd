-- Testbench: Output Buffer
-- Tests: Write 1 word -> read 64 bytes, fill FIFO (8 words), drain
-- Verifies byte ordering, full/empty flags

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_output_buffer is
end entity tb_output_buffer;

architecture sim of tb_output_buffer is
    constant CLK_PERIOD : time := 10 ns;

    signal clk         : std_logic := '0';
    signal rst         : std_logic := '1';
    signal wr_data     : std_logic_vector(511 downto 0) := (others => '0');
    signal wr_en       : std_logic := '0';
    signal rd_data     : std_logic_vector(7 downto 0);
    signal rd_en       : std_logic := '0';
    signal rd_valid    : std_logic;
    signal full        : std_logic;
    signal empty       : std_logic;
    signal almost_full : std_logic;

    signal test_pass : boolean := true;

begin

    clk <= not clk after CLK_PERIOD / 2;

    uut: entity work.output_buffer
        port map (
            clk         => clk,
            rst         => rst,
            wr_data     => wr_data,
            wr_en       => wr_en,
            rd_data     => rd_data,
            rd_en       => rd_en,
            rd_valid    => rd_valid,
            full        => full,
            empty       => empty,
            almost_full => almost_full
        );

    process
        variable expected_byte : std_logic_vector(7 downto 0);
        variable fail_count : integer := 0;
    begin
        report "=== Output Buffer Testbench ===" severity note;

        -- Reset
        rst <= '1';
        wait for CLK_PERIOD * 2;
        rst <= '0';
        wait for CLK_PERIOD * 2;

        -- Verify initial state
        assert empty = '1' report "FAIL: Not empty after reset" severity error;
        assert full = '0' report "FAIL: Full after reset" severity error;

        -----------------------------------------------------------------------
        -- Test 1: Write 1 word, read 64 bytes (LSB first)
        -----------------------------------------------------------------------
        report "--- Test 1: Write 1 word, read 64 bytes ---" severity note;

        -- Build a test pattern: byte 0 = 0x00, byte 1 = 0x01, ..., byte 63 = 0x3F
        for i in 0 to 63 loop
            wr_data(i*8+7 downto i*8) <= std_logic_vector(to_unsigned(i, 8));
        end loop;
        wr_en <= '1';
        wait for CLK_PERIOD;
        wr_en <= '0';
        -- Wait for auto-load (word is loaded from FIFO into shift reg)
        wait for CLK_PERIOD * 3;

        -- Read 64 bytes: assert rd_en, wait for the clock edge to process,
        -- then check rd_valid/rd_data on the same cycle
        for i in 0 to 63 loop
            rd_en <= '1';
            wait for CLK_PERIOD;
            -- rd_valid and rd_data are now set (registered output from the rising_edge that saw rd_en)
            -- Check them before deasserting rd_en
            if rd_valid /= '1' then
                report "FAIL: rd_valid not asserted at byte " & integer'image(i) severity error;
                fail_count := fail_count + 1;
            else
                expected_byte := std_logic_vector(to_unsigned(i, 8));
                if rd_data /= expected_byte then
                    report "FAIL: byte " & integer'image(i) &
                        " expected 0x" & to_hstring(unsigned(expected_byte)) &
                        " got 0x" & to_hstring(unsigned(rd_data)) severity error;
                    fail_count := fail_count + 1;
                end if;
            end if;
            rd_en <= '0';
            wait for CLK_PERIOD;
        end loop;

        -- After reading all 64 bytes, buffer should be empty
        wait for CLK_PERIOD * 2;
        if empty /= '1' then
            report "FAIL: Not empty after draining" severity error;
            fail_count := fail_count + 1;
        end if;

        if fail_count = 0 then
            report "Test 1 PASSED: 64 bytes read correctly" severity note;
        else
            report "Test 1 FAILED: " & integer'image(fail_count) & " errors" severity error;
            test_pass <= false;
        end if;

        wait for CLK_PERIOD * 4;

        -----------------------------------------------------------------------
        -- Test 2: Fill FIFO with 8 words, check flags, drain all
        -----------------------------------------------------------------------
        report "--- Test 2: Fill FIFO (8 words) ---" severity note;
        fail_count := 0;

        for w in 0 to 7 loop
            -- Each word: all bytes = word index
            for i in 0 to 63 loop
                wr_data(i*8+7 downto i*8) <= std_logic_vector(to_unsigned(w, 8));
            end loop;
            wr_en <= '1';
            wait for CLK_PERIOD;
            wr_en <= '0';
            wait for CLK_PERIOD;
        end loop;

        -- Wait for auto-load
        wait for CLK_PERIOD * 2;

        if empty = '1' then
            report "FAIL: Buffer empty after writing 8 words" severity error;
            fail_count := fail_count + 1;
        end if;

        -- Drain all 8 words (512 bytes total)
        for w in 0 to 7 loop
            for i in 0 to 63 loop
                rd_en <= '1';
                wait for CLK_PERIOD;
                -- Just drain; spot-check first byte of word 1
                if w = 1 and i = 0 and rd_valid = '1' then
                    if rd_data /= x"01" then
                        report "FAIL: word 1 first byte got 0x" &
                            to_hstring(unsigned(rd_data)) severity error;
                        fail_count := fail_count + 1;
                    end if;
                end if;
                rd_en <= '0';
                wait for CLK_PERIOD;
            end loop;
        end loop;

        wait for CLK_PERIOD * 2;
        if empty /= '1' then
            report "FAIL: Not empty after draining all 8 words" severity error;
            fail_count := fail_count + 1;
        end if;

        if fail_count = 0 then
            report "Test 2 PASSED: FIFO fill/drain correct" severity note;
        else
            report "Test 2 FAILED: " & integer'image(fail_count) & " errors" severity error;
            test_pass <= false;
        end if;

        wait for CLK_PERIOD * 4;

        -----------------------------------------------------------------------
        -- Summary
        -----------------------------------------------------------------------
        if test_pass then
            report "=== ALL OUTPUT BUFFER TESTS PASSED ===" severity note;
        else
            report "=== OUTPUT BUFFER TESTS FAILED ===" severity error;
        end if;

        wait;
    end process;

end architecture sim;
