-- tb_cordic_ec_mult.vhd
-- Testbench for GF(2^255-19) field multiplier
-- 5 tests with self-checking assertions

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_cordic_ec_mult is
end entity;

architecture sim of tb_cordic_ec_mult is

    constant CLK_PERIOD : time := 10 ns;

    -- p = 2^255 - 19 (defined as 256-bit, then truncated to 255-bit since p < 2^255)
    constant CURVE25519_P_256 : unsigned(255 downto 0) :=
        x"7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFED";
    constant CURVE25519_P : unsigned(254 downto 0) := CURVE25519_P_256(254 downto 0);

    signal clk    : std_logic := '0';
    signal rst    : std_logic := '1';
    signal a_in   : unsigned(254 downto 0) := (others => '0');
    signal b_in   : unsigned(254 downto 0) := (others => '0');
    signal start  : std_logic := '0';
    signal result : unsigned(254 downto 0);
    signal done   : std_logic;

    signal pass_count : integer := 0;
    signal fail_count : integer := 0;

begin

    -- Clock generation
    clk <= not clk after CLK_PERIOD / 2;

    -- DUT instantiation
    uut : entity work.cordic_ec_mult
        port map (
            clk    => clk,
            rst    => rst,
            a      => a_in,
            b      => b_in,
            start  => start,
            result => result,
            done   => done
        );

    -- Test process
    stim : process
        variable expected : unsigned(254 downto 0);

        procedure wait_done is
        begin
            while done /= '1' loop
                wait until rising_edge(clk);
            end loop;
            wait until rising_edge(clk);  -- one extra cycle after done
        end procedure;

        procedure pulse_start is
        begin
            start <= '1';
            wait until rising_edge(clk);
            start <= '0';
        end procedure;

    begin
        -- Reset for 5 clocks
        rst <= '1';
        for i in 0 to 4 loop
            wait until rising_edge(clk);
        end loop;
        rst <= '0';
        wait until rising_edge(clk);
        wait until rising_edge(clk);

        -------------------------------------------------
        -- Test 1: 0 * anything = 0
        -------------------------------------------------
        a_in <= (others => '0');
        b_in <= to_unsigned(12345, 255);
        pulse_start;
        wait_done;

        expected := (others => '0');
        if result = expected then
            report "Test 1: PASSED (0 * 12345 = 0)" severity note;
            pass_count <= pass_count + 1;
        else
            report "Test 1: FAILED (0 * 12345: expected 0)" severity error;
            fail_count <= fail_count + 1;
        end if;
        wait until rising_edge(clk);

        -------------------------------------------------
        -- Test 2: 1 * 9 = 9
        -------------------------------------------------
        a_in <= to_unsigned(1, 255);
        b_in <= to_unsigned(9, 255);
        pulse_start;
        wait_done;

        expected := to_unsigned(9, 255);
        if result = expected then
            report "Test 2: PASSED (1 * 9 = 9)" severity note;
            pass_count <= pass_count + 1;
        else
            report "Test 2: FAILED (1 * 9: expected 9)" severity error;
            fail_count <= fail_count + 1;
        end if;
        wait until rising_edge(clk);

        -------------------------------------------------
        -- Test 3: commutativity A*B = B*A (7*13 = 13*7 = 91)
        -------------------------------------------------
        -- First: 7 * 13
        a_in <= to_unsigned(7, 255);
        b_in <= to_unsigned(13, 255);
        pulse_start;
        wait_done;

        expected := to_unsigned(91, 255);
        if result = expected then
            report "Test 3a: PASSED (7 * 13 = 91)" severity note;
        else
            report "Test 3a: FAILED (7 * 13: expected 91)" severity error;
            fail_count <= fail_count + 1;
        end if;
        wait until rising_edge(clk);

        -- Second: 13 * 7
        a_in <= to_unsigned(13, 255);
        b_in <= to_unsigned(7, 255);
        pulse_start;
        wait_done;

        if result = expected then
            report "Test 3b: PASSED (13 * 7 = 91, commutativity verified)" severity note;
            pass_count <= pass_count + 1;
        else
            report "Test 3b: FAILED (13 * 7: expected 91)" severity error;
            fail_count <= fail_count + 1;
        end if;
        wait until rising_edge(clk);

        -------------------------------------------------
        -- Test 4: 9 * 9 mod p = 81
        -------------------------------------------------
        a_in <= to_unsigned(9, 255);
        b_in <= to_unsigned(9, 255);
        pulse_start;
        wait_done;

        expected := to_unsigned(81, 255);
        if result = expected then
            report "Test 4: PASSED (9 * 9 = 81)" severity note;
            pass_count <= pass_count + 1;
        else
            report "Test 4: FAILED (9 * 9: expected 81)" severity error;
            fail_count <= fail_count + 1;
        end if;
        wait until rising_edge(clk);

        -------------------------------------------------
        -- Test 5: (p-1) * 2 mod p = p - 2
        -- Since (p-1)*2 = 2p - 2 ≡ -2 mod p ≡ p - 2
        -------------------------------------------------
        a_in <= CURVE25519_P - 1;
        b_in <= to_unsigned(2, 255);
        pulse_start;
        wait_done;

        expected := CURVE25519_P - 2;
        if result = expected then
            report "Test 5: PASSED ((p-1) * 2 mod p = p - 2)" severity note;
            pass_count <= pass_count + 1;
        else
            report "Test 5: FAILED ((p-1) * 2 mod p: expected p-2)" severity error;
            fail_count <= fail_count + 1;
        end if;
        wait until rising_edge(clk);

        -------------------------------------------------
        -- Summary
        -------------------------------------------------
        wait until rising_edge(clk);  -- let counts settle
        if fail_count = 0 then
            report "=== ALL CORDIC_EC_MULT TESTS PASSED ===" severity note;
        else
            report "=== SOME TESTS FAILED ===" severity error;
        end if;

        wait for 100 ns;
        std.env.stop;
    end process;

end architecture;
