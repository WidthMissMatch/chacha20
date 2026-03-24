-- Testbench: Poly1305 MAC
-- RFC 8439 Section 2.5.2 test vector
-- Key: 85d6be78...4149f51b, Msg: "Cryptographic Forum Research Group"
-- Expected tag: a8061dc1305136c6c22b8baf0c0127a9

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.poly1305_pkg.all;

entity tb_poly1305_mac is
end entity tb_poly1305_mac;

architecture sim of tb_poly1305_mac is
    constant CLK_PERIOD : time := 10 ns;

    signal clk        : std_logic := '0';
    signal rst        : std_logic := '1';
    signal poly_key   : std_logic_vector(255 downto 0);
    signal msg_block  : std_logic_vector(127 downto 0);
    signal msg_valid  : std_logic := '0';
    signal msg_last   : std_logic := '0';
    signal byte_count : std_logic_vector(4 downto 0) := "00000";
    signal tag_out    : std_logic_vector(127 downto 0);
    signal tag_valid  : std_logic;
    signal ready      : std_logic;

    signal test_pass  : boolean := true;

    -- RFC 8439 S2.5.2 key
    -- r = key[0:16] little-endian = 0xa806d542fe52447f336d555778bed685
    -- s = key[16:32] little-endian = 0x1bf54941aff6bf4afdb20dfb8a800301
    -- poly_key(127:0) = r, poly_key(255:128) = s
    constant TEST_KEY : std_logic_vector(255 downto 0) :=
        x"1bf54941aff6bf4afdb20dfb8a800301" &
        x"a806d542fe52447f336d555778bed685";

    -- "Cryptographic Forum Research Group" = 34 bytes
    -- Block 0 (16 bytes): "Cryptographic F" (little-endian)
    constant BLOCK0 : std_logic_vector(127 downto 0) :=
        x"6f4620636968706172676f7470797243";

    -- Block 1 (16 bytes): "orum Research Gr" (little-endian)
    constant BLOCK1 : std_logic_vector(127 downto 0) :=
        x"6f7247206863726165736552206d7572";

    -- Block 2 (2 bytes): "up" (little-endian, zero-padded)
    constant BLOCK2 : std_logic_vector(127 downto 0) :=
        x"00000000000000000000000000007075";

    -- Expected tag: a8061dc1305136c6c22b8baf0c0127a9 (little-endian)
    constant EXPECTED_TAG : std_logic_vector(127 downto 0) :=
        x"a927010caf8b2bc2c6365130c11d06a8";

begin

    clk <= not clk after CLK_PERIOD / 2;

    uut: entity work.poly1305_mac
        port map (
            clk        => clk,
            rst        => rst,
            poly_key   => poly_key,
            msg_block  => msg_block,
            msg_valid  => msg_valid,
            msg_last   => msg_last,
            byte_count => byte_count,
            tag_out    => tag_out,
            tag_valid  => tag_valid,
            ready      => ready
        );

    process
    begin
        report "=== Poly1305 MAC Testbench ===" severity note;
        report "RFC 8439 Section 2.5.2 test vector" severity note;

        poly_key <= TEST_KEY;

        -- Reset
        rst <= '1';
        wait for CLK_PERIOD * 3;
        rst <= '0';
        wait for CLK_PERIOD;

        ---------------------------------------------------------------
        -- Feed Block 0 (triggers CLAMP_R)
        ---------------------------------------------------------------
        report "--- Feeding Block 0 (16 bytes) ---" severity note;
        msg_block  <= BLOCK0;
        msg_valid  <= '1';
        msg_last   <= '0';
        byte_count <= "10000";  -- 0 means 16 bytes (full block)
        wait until rising_edge(clk);
        msg_valid  <= '0';

        -- Wait for block processing and ready signal
        wait until ready = '1';
        wait until rising_edge(clk);

        ---------------------------------------------------------------
        -- Feed Block 1
        ---------------------------------------------------------------
        report "--- Feeding Block 1 (16 bytes) ---" severity note;
        msg_block  <= BLOCK1;
        msg_valid  <= '1';
        msg_last   <= '0';
        byte_count <= "10000";
        wait until rising_edge(clk);
        msg_valid  <= '0';

        -- Wait for block processing and ready signal
        wait until ready = '1';
        wait until rising_edge(clk);

        ---------------------------------------------------------------
        -- Feed Block 2 (last, 2 bytes)
        ---------------------------------------------------------------
        report "--- Feeding Block 2 (2 bytes, last) ---" severity note;
        msg_block  <= BLOCK2;
        msg_valid  <= '1';
        msg_last   <= '1';
        byte_count <= "00010";
        wait until rising_edge(clk);
        msg_valid  <= '0';
        msg_last   <= '0';

        -- Wait for tag
        wait until tag_valid = '1';
        wait for 1 ns;

        ---------------------------------------------------------------
        -- Check result
        ---------------------------------------------------------------
        if tag_out = EXPECTED_TAG then
            report "Tag MATCHES RFC 8439 S2.5.2" severity note;
            report "  Tag: " & to_hstring(unsigned(tag_out)) severity note;
        else
            report "FAIL: Tag mismatch!" severity error;
            report "  Got:      " & to_hstring(unsigned(tag_out)) severity error;
            report "  Expected: " & to_hstring(unsigned(EXPECTED_TAG)) severity error;
            test_pass <= false;
        end if;

        ---------------------------------------------------------------
        -- Summary
        ---------------------------------------------------------------
        if test_pass then
            report "=== ALL POLY1305 MAC TESTS PASSED ===" severity note;
        else
            report "=== POLY1305 MAC TESTS FAILED ===" severity error;
        end if;

        wait;
    end process;

end architecture sim;
