-- Testbench: ChaCha20 Block Function
-- RFC 7539 Appendix A.1 — single block keystream verification via chacha20_core

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.chacha20_pkg.all;

entity tb_chacha20_block is
end entity tb_chacha20_block;

architecture sim of tb_chacha20_block is
    constant CLK_PERIOD : time := 10 ns;

    signal clk        : std_logic := '0';
    signal rst        : std_logic := '1';
    signal start      : std_logic := '0';
    signal done       : std_logic;
    signal key        : std_logic_vector(255 downto 0);
    signal nonce      : std_logic_vector(95 downto 0);
    signal counter_in : std_logic_vector(31 downto 0);
    signal plaintext  : std_logic_vector(511 downto 0);
    signal ciphertext : std_logic_vector(511 downto 0);
    signal keystream  : std_logic_vector(511 downto 0);
    signal test_pass  : boolean := true;

    -- Expected keystream from RFC 7539 A.1 (serialized little-endian)
    -- Words: e4e7f110 15593bd1 1fdd0f50 c47120a3 ...
    -- As bytes (little-endian per word): 10 f1 e7 e4  d1 3b 59 15 ...
    -- In our state_to_slv format: word0 at bits 31:0, word1 at 63:32, etc.
    constant EXPECTED_KS : std_logic_vector(511 downto 0) :=
        -- Word 15 (bits 511:480) ... Word 0 (bits 31:0)
        x"4e3c50a2" & x"e883d0cb" & x"b94e16de" & x"d19c12b5" &
        x"a2028bd9" & x"05d7c214" & x"09aa9f07" & x"466482d2" &
        x"4e6cd4c3" & x"9aaa2204" & x"0368c033" & x"c7f4d1c7" &
        x"c47120a3" & x"1fdd0f50" & x"15593bd1" & x"e4e7f110";

begin

    clk <= not clk after CLK_PERIOD / 2;

    uut: entity work.chacha20_core
        port map (
            clk        => clk,
            rst        => rst,
            start      => start,
            done       => done,
            key        => key,
            nonce      => nonce,
            counter_in => counter_in,
            plaintext  => plaintext,
            ciphertext => ciphertext,
            keystream_out => keystream
        );

    process
    begin
        report "=== ChaCha20 Block Testbench ===" severity note;

        -- Key: 00:01:02:...:1f (little-endian words)
        -- Word 0 = 0x03020100, Word 1 = 0x07060504, ...
        key <= x"1f1e1d1c" & x"1b1a1918" & x"17161514" & x"13121110" &
               x"0f0e0d0c" & x"0b0a0908" & x"07060504" & x"03020100";

        -- Nonce: 00:00:00:09:00:00:00:4a:00:00:00:00 (little-endian words)
        -- Word 0 = 0x09000000, Word 1 = 0x4a000000, Word 2 = 0x00000000
        nonce <= x"00000000" & x"4a000000" & x"09000000";

        -- Counter = 1
        counter_in <= x"00000001";

        -- Plaintext = 0 (just checking keystream)
        plaintext <= (others => '0');

        -- Reset
        rst <= '1';
        wait for CLK_PERIOD * 2;
        rst <= '0';
        wait for CLK_PERIOD;

        -- Start
        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';

        -- Wait for done
        wait until done = '1';
        wait for 1 ns;

        -- With plaintext=0, ciphertext = keystream
        if keystream /= EXPECTED_KS then
            report "FAIL: Keystream mismatch!" severity error;
            -- Print first 4 words for debugging
            for i in 0 to 3 loop
                report "  word " & integer'image(i) & " = " &
                    to_hstring(unsigned(keystream(i*32+31 downto i*32))) &
                    " expected " &
                    to_hstring(unsigned(EXPECTED_KS(i*32+31 downto i*32)))
                    severity note;
            end loop;
            test_pass <= false;
        else
            report "Keystream matches RFC 7539 A.1" severity note;
        end if;

        wait for CLK_PERIOD;

        if test_pass then
            report "=== ALL CHACHA20 BLOCK TESTS PASSED ===" severity note;
        else
            report "=== CHACHA20 BLOCK TESTS FAILED ===" severity error;
        end if;

        wait;
    end process;

end architecture sim;
