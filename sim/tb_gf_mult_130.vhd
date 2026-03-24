-- Testbench: GF(2^130-5) Modular Multiplier
-- Verifies: zero, identity, and RFC-derived/random test vectors

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.poly1305_pkg.all;

entity tb_gf_mult_130 is
end entity tb_gf_mult_130;

architecture sim of tb_gf_mult_130 is
    constant CLK_PERIOD : time := 10 ns;

    signal clk     : std_logic := '0';
    signal rst     : std_logic := '1';
    signal a       : poly_word := (others => '0');
    signal b       : poly_word := (others => '0');
    signal start   : std_logic := '0';
    signal product : poly_word;
    signal done    : std_logic;

    signal test_pass : boolean := true;
    signal test_num  : integer := 0;

    -- Helper: run one multiplication and check result
    procedure run_test(
        signal   clk_s   : in  std_logic;
        signal   a_s     : out poly_word;
        signal   b_s     : out poly_word;
        signal   start_s : out std_logic;
        signal   done_s  : in  std_logic;
        signal   prod_s  : in  poly_word;
        constant a_val   : in  unsigned(129 downto 0);
        constant b_val   : in  unsigned(129 downto 0);
        constant exp_val : in  unsigned(129 downto 0);
        constant name    : in  string;
        signal   pass    : inout boolean
    ) is
    begin
        a_s <= a_val;
        b_s <= b_val;
        wait until rising_edge(clk_s);
        start_s <= '1';
        wait until rising_edge(clk_s);
        start_s <= '0';
        wait until done_s = '1';
        wait for 1 ns;

        if prod_s = exp_val then
            report name & ": PASSED" severity note;
        else
            report name & ": FAILED" severity error;
            report "  got:      " & to_hstring(prod_s) severity error;
            report "  expected: " & to_hstring(exp_val) severity error;
            pass <= false;
        end if;
        wait until rising_edge(clk_s);
    end procedure;

begin

    clk <= not clk after CLK_PERIOD / 2;

    uut: entity work.gf_mult_130
        port map (
            clk     => clk,
            rst     => rst,
            a       => a,
            b       => b,
            start   => start,
            product => product,
            done    => done
        );

    process
        -- Test vector constants
        constant ZERO : poly_word := (others => '0');
        constant ONE  : poly_word := to_unsigned(1, 130);

        -- X for identity test (fits in 128 bits, top 2 bits = 00)
        constant X_VAL : poly_word :=
            "00" & unsigned'(x"deadbeefcafebabe1234567890abcdef");

        -- RFC block0 * r_clamped
        constant RFC_A : poly_word :=
            "01" & unsigned'(x"6f4620636968706172676f7470797243");
        constant RFC_B : poly_word :=
            "00" & unsigned'(x"0806d5400e52447c036d555408bed685");
        constant RFC_EXP : poly_word :=
            "10" & unsigned'(x"c88c77849d64ae9147ddeb88e69c83fc");

        -- Random test 0 (seed=42)
        constant R0_A : poly_word :=
            "01" & unsigned'(x"bdd640fb06671ad11c80317fa3b1799d");
        constant R0_B : poly_word :=
            "00" & unsigned'(x"bc8960a923b8c1e9392456de3eb13b90");
        constant R0_EXP : poly_word :=
            "01" & unsigned'(x"9e1bf47b68fc75e381f55ea2d3c82144");

        -- Random test 1
        constant R1_A : poly_word :=
            "00" & unsigned'(x"8b9d2434e465e150bd9c66b3ad3c2d6d");
        constant R1_B : poly_word :=
            "00" & unsigned'(x"07a0ca6e0822e8f36c031199972a8469");
        constant R1_EXP : poly_word :=
            "01" & unsigned'(x"b024e1a1861701e18617714373705d2e");

        -- Random test 2
        constant R2_A : poly_word :=
            "00" & unsigned'(x"9a1de644815ef6d13b8faa1837f8a88b");
        constant R2_B : poly_word :=
            "10" & unsigned'(x"a65ed389b74d0fb132e706298fadc1a6");
        constant R2_EXP : poly_word :=
            "00" & unsigned'(x"de15632b84deae20189f52bc083e73b1");

    begin
        report "=== GF(2^130-5) Multiplier Testbench ===" severity note;

        -- Reset
        rst <= '1';
        wait for CLK_PERIOD * 3;
        rst <= '0';
        wait for CLK_PERIOD;

        -- Test 1: 0 * 0 = 0
        run_test(clk, a, b, start, done, product, ZERO, ZERO, ZERO, "0*0=0", test_pass);

        -- Test 2: 0 * X = 0
        run_test(clk, a, b, start, done, product, ZERO, X_VAL, ZERO, "0*X=0", test_pass);

        -- Test 3: 1 * X = X
        run_test(clk, a, b, start, done, product, ONE, X_VAL, X_VAL, "1*X=X", test_pass);

        -- Test 4: X * 1 = X (commutativity with 1)
        run_test(clk, a, b, start, done, product, X_VAL, ONE, X_VAL, "X*1=X", test_pass);

        -- Test 5: RFC block0 * r_clamped
        run_test(clk, a, b, start, done, product, RFC_A, RFC_B, RFC_EXP, "RFC_block0*r", test_pass);

        -- Test 6: Random 0
        run_test(clk, a, b, start, done, product, R0_A, R0_B, R0_EXP, "Random0", test_pass);

        -- Test 7: Random 1
        run_test(clk, a, b, start, done, product, R1_A, R1_B, R1_EXP, "Random1", test_pass);

        -- Test 8: Random 2
        run_test(clk, a, b, start, done, product, R2_A, R2_B, R2_EXP, "Random2", test_pass);

        -- Summary
        if test_pass then
            report "=== ALL GF_MULT_130 TESTS PASSED ===" severity note;
        else
            report "=== GF_MULT_130 TESTS FAILED ===" severity error;
        end if;

        wait;
    end process;

end architecture sim;
