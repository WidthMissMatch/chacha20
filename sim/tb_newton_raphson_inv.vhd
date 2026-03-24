--------------------------------------------------------------------------------
-- tb_newton_raphson_inv.vhd
--
-- Testbench for newton_raphson_inv (GF(2^255-19) modular inverse via
-- Fermat's little theorem).
--
-- Four tests:
--   1. inv(1) = 1            (multiplicative identity)
--   2. inv(2) = (p+1)/2      (known closed-form: 2^254 - 9)
--   3. inv(p-1) = p-1        (self-inverse: (p-1)^2 = 1 mod p)
--   4. inv(9) verified by    9 * inv(9) mod p = 1 (multiply-back check)
--
-- Uses --stop-time=10ms with GHDL (10 ns clock, ~99K clocks per inversion).
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.chacha20_pkg.all;

entity tb_newton_raphson_inv is
end entity tb_newton_raphson_inv;

architecture sim of tb_newton_raphson_inv is

    constant CLK_PERIOD : time := 10 ns;

    ---------------------------------------------------------------------------
    -- DUT signals
    ---------------------------------------------------------------------------
    signal clk       : std_logic := '0';
    signal rst       : std_logic := '1';
    signal dut_a     : unsigned(254 downto 0) := (others => '0');
    signal dut_start : std_logic := '0';
    signal dut_res   : unsigned(254 downto 0);
    signal dut_done  : std_logic;
    signal dut_conv  : std_logic;

    ---------------------------------------------------------------------------
    -- Verification multiplier signals (for test 4: a * inv(a) = 1)
    ---------------------------------------------------------------------------
    signal ver_a      : unsigned(254 downto 0) := (others => '0');
    signal ver_b      : unsigned(254 downto 0) := (others => '0');
    signal ver_start  : std_logic := '0';
    signal ver_result : unsigned(254 downto 0);
    signal ver_done   : std_logic;

    ---------------------------------------------------------------------------
    -- Test tracking
    ---------------------------------------------------------------------------
    signal test_num    : integer := 0;
    signal tests_pass  : integer := 0;
    signal tests_fail  : integer := 0;
    signal sim_done    : boolean := false;

    ---------------------------------------------------------------------------
    -- Known constants
    ---------------------------------------------------------------------------
    -- p - 1 = 2^255 - 20
    -- Hex: 7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEC
    constant P_MINUS_1 : unsigned(254 downto 0) :=
        "111" &
        x"FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF" &
        x"EC";

    -- inv(2) = (p+1)/2 = 2^254 - 9
    -- Hex: 3FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF7
    constant INV_2_EXPECTED : unsigned(254 downto 0) :=
        "011" &
        x"FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF" &
        x"F7";

    -- The value 1
    constant ONE_255 : unsigned(254 downto 0) := to_unsigned(1, 255);

    -- The value 2
    constant TWO_255 : unsigned(254 downto 0) := to_unsigned(2, 255);

    -- The value 9
    constant NINE_255 : unsigned(254 downto 0) := to_unsigned(9, 255);

begin

    ---------------------------------------------------------------------------
    -- Clock generation
    ---------------------------------------------------------------------------
    clk <= not clk after CLK_PERIOD / 2 when not sim_done else '0';

    ---------------------------------------------------------------------------
    -- DUT: newton_raphson_inv
    ---------------------------------------------------------------------------
    u_dut : entity work.newton_raphson_inv
        port map (
            clk       => clk,
            rst       => rst,
            a         => dut_a,
            start     => dut_start,
            result    => dut_res,
            done      => dut_done,
            converged => dut_conv
        );

    ---------------------------------------------------------------------------
    -- Verification multiplier (used in test 4 to check a * inv(a) = 1)
    ---------------------------------------------------------------------------
    u_verify : entity work.cordic_ec_mult
        port map (
            clk    => clk,
            rst    => rst,
            a      => ver_a,
            b      => ver_b,
            start  => ver_start,
            result => ver_result,
            done   => ver_done
        );

    ---------------------------------------------------------------------------
    -- Stimulus process
    ---------------------------------------------------------------------------
    p_stim : process
        variable pass : boolean;
    begin
        -- Reset
        rst <= '1';
        dut_start <= '0';
        ver_start <= '0';
        wait for CLK_PERIOD * 5;
        rst <= '0';
        wait for CLK_PERIOD * 2;

        -----------------------------------------------------------------------
        -- Test 1: inv(1) = 1
        -----------------------------------------------------------------------
        test_num <= 1;
        report "Test 1: inv(1) -- expecting 1";

        dut_a     <= ONE_255;
        dut_start <= '1';
        wait for CLK_PERIOD;
        dut_start <= '0';

        -- Wait for done
        wait until dut_done = '1';
        wait for CLK_PERIOD;

        pass := (dut_res = ONE_255) and (dut_conv = '1');
        if pass then
            report "Test 1: PASSED -- inv(1) = 1";
            tests_pass <= tests_pass + 1;
        else
            report "Test 1: FAILED -- inv(1) /= 1" severity error;
            tests_fail <= tests_fail + 1;
        end if;

        wait for CLK_PERIOD * 5;

        -----------------------------------------------------------------------
        -- Test 2: inv(2) = 2^254 - 9
        -----------------------------------------------------------------------
        test_num <= 2;
        report "Test 2: inv(2) -- expecting 2^254 - 9";

        dut_a     <= TWO_255;
        dut_start <= '1';
        wait for CLK_PERIOD;
        dut_start <= '0';

        wait until dut_done = '1';
        wait for CLK_PERIOD;

        pass := (dut_res = INV_2_EXPECTED) and (dut_conv = '1');
        if pass then
            report "Test 2: PASSED -- inv(2) = 2^254 - 9";
            tests_pass <= tests_pass + 1;
        else
            report "Test 2: FAILED -- inv(2) incorrect" severity error;
            tests_fail <= tests_fail + 1;
        end if;

        wait for CLK_PERIOD * 5;

        -----------------------------------------------------------------------
        -- Test 3: inv(p-1) = p-1 (self-inverse)
        -----------------------------------------------------------------------
        test_num <= 3;
        report "Test 3: inv(p-1) -- expecting p-1";

        dut_a     <= P_MINUS_1;
        dut_start <= '1';
        wait for CLK_PERIOD;
        dut_start <= '0';

        wait until dut_done = '1';
        wait for CLK_PERIOD;

        pass := (dut_res = P_MINUS_1) and (dut_conv = '1');
        if pass then
            report "Test 3: PASSED -- inv(p-1) = p-1";
            tests_pass <= tests_pass + 1;
        else
            report "Test 3: FAILED -- inv(p-1) incorrect" severity error;
            tests_fail <= tests_fail + 1;
        end if;

        wait for CLK_PERIOD * 5;

        -----------------------------------------------------------------------
        -- Test 4: 9 * inv(9) mod p = 1 (multiply-back verification)
        -----------------------------------------------------------------------
        test_num <= 4;
        report "Test 4: inv(9) -- verifying 9 * inv(9) mod p = 1";

        dut_a     <= NINE_255;
        dut_start <= '1';
        wait for CLK_PERIOD;
        dut_start <= '0';

        wait until dut_done = '1';
        wait for CLK_PERIOD;

        -- Check converged
        if dut_conv /= '1' then
            report "Test 4: FAILED -- did not converge" severity error;
            tests_fail <= tests_fail + 1;
        else
            -- Use verification multiplier: 9 * inv(9) should equal 1
            ver_a     <= NINE_255;
            ver_b     <= dut_res;
            ver_start <= '1';
            wait for CLK_PERIOD;
            ver_start <= '0';

            wait until ver_done = '1';
            wait for CLK_PERIOD;

            if ver_result = ONE_255 then
                report "Test 4: PASSED -- 9 * inv(9) mod p = 1";
                tests_pass <= tests_pass + 1;
            else
                report "Test 4: FAILED -- 9 * inv(9) mod p /= 1" severity error;
                tests_fail <= tests_fail + 1;
            end if;
        end if;

        -----------------------------------------------------------------------
        -- Summary
        -----------------------------------------------------------------------
        wait for CLK_PERIOD * 5;

        if tests_fail = 0 and (tests_pass + tests_fail) = 4 then
            report "=== ALL NEWTON_RAPHSON_INV TESTS PASSED ===";
        else
            report "=== NEWTON_RAPHSON_INV: " &
                   integer'image(tests_pass) & " passed, " &
                   integer'image(tests_fail) & " failed ===" severity error;
        end if;

        sim_done <= true;
        wait;
    end process p_stim;

end architecture sim;
