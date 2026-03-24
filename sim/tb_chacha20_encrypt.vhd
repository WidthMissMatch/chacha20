-- Testbench: ChaCha20 Full Encryption
-- RFC 8439 Section 2.4.2 — "Sunscreen" message (114 bytes, 2 blocks)
-- Verifies multi-block encryption with counter increment and round-trip decrypt

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.chacha20_pkg.all;

entity tb_chacha20_encrypt is
end entity tb_chacha20_encrypt;

architecture sim of tb_chacha20_encrypt is
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

    -- RFC 8439 Section 2.4.2 test vector
    -- Key: 00:01:02:...:1f
    -- Nonce: 00:00:00:00:00:00:00:4a:00:00:00:00
    -- Initial counter: 1

    -- Block 1 plaintext (64 bytes): "Ladies and Gentlemen of the class of '99: If I could offer you o"
    constant PT_BLOCK1 : std_logic_vector(511 downto 0) :=
        x"6f20756f" & x"79207265" & x"66666f20" & x"646c756f" &  -- words 15-12
        x"63204920" & x"6649203a" & x"39392720" & x"666f2073" &  -- words 11-8
        x"73616c63" & x"20656874" & x"20666f20" & x"6e656d65" &  -- words 7-4
        x"6c746e65" & x"4720646e" & x"61207365" & x"6964614c";   -- words 3-0

    -- Block 1 expected ciphertext (RFC 8439 Section 2.4.2, bytes 0-63)
    constant CT_BLOCK1 : std_logic_vector(511 downto 0) :=
        x"d861089f" & x"350c538f" & x"ab5251e6" & x"24d63916" &  -- words 15-12
        x"57b362cd" & x"ab3d598f" & x"ab334752" & x"c5651bf9" &  -- words 11-8
        x"0bae9ffd" & x"ccaf270a" & x"c260431d" & x"ec7a7ee9" &  -- words 7-4
        x"81690ddd" & x"2807ba41" & x"80f96825" & x"9a352e6e";   -- words 3-0

    -- Block 2 plaintext (50 bytes + 14 zero-pad): "nly one tip for the future, sunscreen would be it."
    constant PT_BLOCK2 : std_logic_vector(511 downto 0) :=
        x"00000000" & x"00000000" & x"00000000" & x"00002e74" &  -- words 15-12
        x"69206562" & x"20646c75" & x"6f77206e" & x"65657263" &  -- words 11-8
        x"736e7573" & x"202c6572" & x"75747566" & x"20656874" &  -- words 7-4
        x"20726f66" & x"20706974" & x"20656e6f" & x"20796c6e";   -- words 3-0

    -- Block 2 expected ciphertext (RFC 8439 Section 2.4.2, bytes 64-113 + keystream XOR 0 for padding)
    constant CT_BLOCK2 : std_logic_vector(511 downto 0) :=
        x"edc49139" & x"e8bcfb88" & x"a11a2073" & x"03744d87" &  -- words 15-12
        x"425e78f2" & x"ed8e0bb4" & x"e65ba374" & x"bf0bf95a" &  -- words 11-8
        x"363779b7" & x"1ae98c81" & x"06f8cc16" & x"4d51bc52" &  -- words 7-4
        x"5eb6228a" & x"088ea356" & x"616a0d50" & x"bf0dca07";   -- words 3-0

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
        variable block1_ct : std_logic_vector(511 downto 0);
    begin
        report "=== ChaCha20 Encryption Testbench ===" severity note;

        -- Key: 00:01:02:...:1f
        key <= x"1f1e1d1c" & x"1b1a1918" & x"17161514" & x"13121110" &
               x"0f0e0d0c" & x"0b0a0908" & x"07060504" & x"03020100";

        -- Nonce: 00:00:00:00:00:00:00:4a:00:00:00:00
        nonce <= x"00000000" & x"4a000000" & x"00000000";

        -- Reset
        rst <= '1';
        wait for CLK_PERIOD * 2;
        rst <= '0';
        wait for CLK_PERIOD;

        -----------------------------------------------------------------------
        -- Block 1: counter = 1
        -----------------------------------------------------------------------
        report "--- Block 1 (counter=1) ---" severity note;
        counter_in <= x"00000001";
        plaintext  <= PT_BLOCK1;

        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';

        wait until done = '1';
        wait for 1 ns;

        block1_ct := ciphertext;

        -- Check against expected
        if ciphertext /= CT_BLOCK1 then
            report "FAIL: Block 1 ciphertext mismatch!" severity error;
            for i in 0 to 15 loop
                if ciphertext(i*32+31 downto i*32) /= CT_BLOCK1(i*32+31 downto i*32) then
                    report "  word " & integer'image(i) &
                        " got " & to_hstring(unsigned(ciphertext(i*32+31 downto i*32))) &
                        " exp " & to_hstring(unsigned(CT_BLOCK1(i*32+31 downto i*32)))
                        severity error;
                end if;
            end loop;
            test_pass <= false;
        else
            report "Block 1 ciphertext MATCHES RFC 8439" severity note;
        end if;

        wait for CLK_PERIOD * 2;

        -----------------------------------------------------------------------
        -- Decrypt block 1 (round-trip test)
        -----------------------------------------------------------------------
        report "--- Block 1 Decrypt (round-trip) ---" severity note;
        counter_in <= x"00000001";
        plaintext  <= block1_ct;

        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';

        wait until done = '1';
        wait for 1 ns;

        if ciphertext = PT_BLOCK1 then
            report "Block 1 round-trip decrypt PASSED" severity note;
        else
            report "FAIL: Block 1 round-trip decrypt" severity error;
            test_pass <= false;
        end if;

        wait for CLK_PERIOD * 2;

        -----------------------------------------------------------------------
        -- Block 2: counter = 2
        -----------------------------------------------------------------------
        report "--- Block 2 (counter=2) ---" severity note;
        counter_in <= x"00000002";
        plaintext  <= PT_BLOCK2;

        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';

        wait until done = '1';
        wait for 1 ns;

        if ciphertext /= CT_BLOCK2 then
            report "FAIL: Block 2 ciphertext mismatch!" severity error;
            for i in 0 to 15 loop
                if ciphertext(i*32+31 downto i*32) /= CT_BLOCK2(i*32+31 downto i*32) then
                    report "  word " & integer'image(i) &
                        " got " & to_hstring(unsigned(ciphertext(i*32+31 downto i*32))) &
                        " exp " & to_hstring(unsigned(CT_BLOCK2(i*32+31 downto i*32)))
                        severity error;
                end if;
            end loop;
            test_pass <= false;
        else
            report "Block 2 ciphertext MATCHES RFC 8439" severity note;
        end if;

        wait for CLK_PERIOD * 2;

        -----------------------------------------------------------------------
        -- Summary
        -----------------------------------------------------------------------
        if test_pass then
            report "=== ALL CHACHA20 ENCRYPT TESTS PASSED ===" severity note;
        else
            report "=== CHACHA20 ENCRYPT TESTS FAILED ===" severity error;
        end if;

        wait;
    end process;

end architecture sim;
