--------------------------------------------------------------------------------
-- tb_diffusion_analyzer.vhd
-- Testbench for the diffusion analyzer (sim-only avalanche analysis module)
--
-- Test 1: 1-bit flip       → hamming=1,   coeff = 0x00000080 (1   * 128)
-- Test 2: 256-bit flip     → hamming=256, coeff = 0x00008000 (256 * 128)
-- Test 3: 512-bit flip     → hamming=512, coeff = 0x00010000 (512 * 128 = 1.0 in Q16.16)
--
-- VHDL-2008
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_diffusion_analyzer is
end entity tb_diffusion_analyzer;

architecture sim of tb_diffusion_analyzer is

    constant CLK_PERIOD : time := 10 ns;

    signal clk             : std_logic := '0';
    signal rst             : std_logic := '1';
    signal state_round_in  : std_logic_vector(511 downto 0) := (others => '0');
    signal round_num       : unsigned(3 downto 0) := (others => '0');
    signal avalanche_coeff : unsigned(31 downto 0);
    signal influence_valid : std_logic;

    -- All-zero reference state
    constant ZERO_STATE : std_logic_vector(511 downto 0) := (others => '0');

    -- 1-bit difference: bit 0 set
    constant ONE_BIT : std_logic_vector(511 downto 0) := (0 => '1', others => '0');

    -- 256-bit difference: alternating 0x55 pattern (each 0x55 byte = 0101_0101 = 4 ones)
    -- 64 bytes × 4 ones/byte = 256 ones
    constant HALF_BITS : std_logic_vector(511 downto 0) :=
        x"5555555555555555555555555555555555555555555555555555555555555555" &
        x"5555555555555555555555555555555555555555555555555555555555555555";

    -- 512-bit difference: all ones
    constant ALL_BITS : std_logic_vector(511 downto 0) := (others => '1');

    signal pass_count : integer := 0;
    signal fail_count : integer := 0;

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut: entity work.diffusion_analyzer
        port map (
            clk             => clk,
            rst             => rst,
            state_round_in  => state_round_in,
            round_num       => round_num,
            avalanche_coeff => avalanche_coeff,
            influence_valid => influence_valid
        );

    process
        -- Helper: set reference at round 0, then drive test state at given round
        -- and verify the resulting avalanche_coeff
        procedure run_test (
            test_num    : in integer;
            ref_state   : in std_logic_vector(511 downto 0);
            test_state  : in std_logic_vector(511 downto 0);
            test_round  : in unsigned(3 downto 0);
            expected    : in unsigned(31 downto 0)
        ) is
        begin
            -- Latch reference at round 0
            state_round_in <= ref_state;
            round_num      <= (others => '0');
            wait for CLK_PERIOD;   -- rising edge: reference_state latched

            -- Apply test state and change round number
            state_round_in <= test_state;
            round_num      <= test_round;
            wait for CLK_PERIOD;   -- rising edge: Hamming computed, outputs registered

            -- influence_valid and avalanche_coeff are now valid
            if influence_valid = '1' and avalanche_coeff = expected then
                report "Test " & integer'image(test_num) & " PASSED: coeff=0x" &
                       to_hstring(avalanche_coeff) severity note;
                pass_count <= pass_count + 1;
            else
                report "Test " & integer'image(test_num) & " FAILED: coeff=0x" &
                       to_hstring(avalanche_coeff) & " expected=0x" &
                       to_hstring(expected) & " valid=" &
                       std_logic'image(influence_valid) severity error;
                fail_count <= fail_count + 1;
            end if;

            -- Return round_num to 0 so next test can re-latch reference
            round_num <= (others => '0');
            wait for CLK_PERIOD;
        end procedure;

    begin
        -- Reset
        rst <= '1';
        wait for 3 * CLK_PERIOD;
        rst <= '0';
        wait for CLK_PERIOD;

        report "=== Diffusion Analyzer Testbench ===" severity note;

        -- Test 1: 1-bit flip → coeff = 1 * 128 = 0x00000080
        run_test(1, ZERO_STATE, ONE_BIT,
                 to_unsigned(1, 4),
                 to_unsigned(128, 32));

        -- Test 2: 256-bit flip (alternating 0x55) → coeff = 256 * 128 = 0x00008000
        run_test(2, ZERO_STATE, HALF_BITS,
                 to_unsigned(2, 4),
                 to_unsigned(32768, 32));

        -- Test 3: 512-bit flip (all ones) → coeff = 512 * 128 = 0x00010000
        run_test(3, ZERO_STATE, ALL_BITS,
                 to_unsigned(3, 4),
                 to_unsigned(65536, 32));

        -- Wait one more cycle for pass_count/fail_count signals to update
        wait for CLK_PERIOD;

        if fail_count = 0 then
            report "tb_diffusion_analyzer: PASSED (3/3)" severity note;
        else
            report "tb_diffusion_analyzer: FAILED (" &
                   integer'image(fail_count) & " failures)" severity failure;
        end if;

        wait;
    end process;

end architecture sim;
