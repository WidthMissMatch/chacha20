-- cordic_ec_mult.vhd
-- GF(2^255-19) field multiplier for Curve25519
-- 255-cycle shift-add with two-pass Barrett-style reduction
-- Latency: ~259 clocks (255 shift-add + 2 reduce + 1 cond_sub + 1 done)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cordic_ec_mult is
    port (
        clk    : in  std_logic;
        rst    : in  std_logic;
        a      : in  unsigned(254 downto 0);
        b      : in  unsigned(254 downto 0);
        start  : in  std_logic;
        result : out unsigned(254 downto 0);
        done   : out std_logic
    );
end entity;

architecture rtl of cordic_ec_mult is

    -- p = 2^255 - 19
    constant CURVE25519_P : unsigned(255 downto 0) :=
        x"7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFED";

    type state_t is (IDLE, SHIFT_ADD, REDUCE, COND_SUB, DONE_STATE);
    signal state     : state_t;

    signal acc       : unsigned(509 downto 0);  -- 510-bit accumulator
    signal shifted_a : unsigned(509 downto 0);  -- running double of a
    signal b_reg     : unsigned(254 downto 0);  -- shift register for b
    signal bit_cnt   : unsigned(7 downto 0);    -- 0..254

    -- Reduction intermediates
    signal sum1      : unsigned(259 downto 0);  -- first pass result (up to 260 bits)
    signal result_r  : unsigned(254 downto 0);

    -- Multiply by 19: 19*x = (x<<4) + (x<<1) + x
    function mult19(x : unsigned) return unsigned is
        variable x_ext : unsigned(x'length + 4 downto 0);
        variable s4    : unsigned(x'length + 4 downto 0);
        variable s1    : unsigned(x'length + 4 downto 0);
        variable s0    : unsigned(x'length + 4 downto 0);
    begin
        x_ext := resize(x, x'length + 5);
        s4 := shift_left(x_ext, 4);
        s1 := shift_left(x_ext, 1);
        s0 := x_ext;
        return s4 + s1 + s0;
    end function;

begin

    result <= result_r;

    process(clk)
        variable lo  : unsigned(254 downto 0);
        variable hi  : unsigned(254 downto 0);
        variable hi19 : unsigned(259 downto 0);  -- 19*hi can be up to 255+5=260 bits
        variable s1_v : unsigned(259 downto 0);
        variable lo2 : unsigned(254 downto 0);
        variable hi2 : unsigned(4 downto 0);
        variable hi2_19 : unsigned(9 downto 0);
        variable s2_v : unsigned(255 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state     <= IDLE;
                acc       <= (others => '0');
                shifted_a <= (others => '0');
                b_reg     <= (others => '0');
                bit_cnt   <= (others => '0');
                sum1      <= (others => '0');
                result_r  <= (others => '0');
                done      <= '0';
            else
                done <= '0';  -- default: deassert

                case state is

                    when IDLE =>
                        if start = '1' then
                            acc       <= (others => '0');
                            shifted_a <= resize(a, 510);
                            b_reg     <= b;
                            bit_cnt   <= (others => '0');
                            state     <= SHIFT_ADD;
                        end if;

                    when SHIFT_ADD =>
                        -- If LSB of b_reg is 1, accumulate shifted_a
                        if b_reg(0) = '1' then
                            acc <= acc + shifted_a;
                        end if;
                        -- Double shifted_a for next bit position
                        shifted_a <= shift_left(shifted_a, 1);
                        -- Shift b_reg right to expose next bit
                        b_reg <= shift_right(b_reg, 1);
                        -- Count bits processed
                        if bit_cnt = to_unsigned(254, 8) then
                            state <= REDUCE;
                        else
                            bit_cnt <= bit_cnt + 1;
                        end if;

                    when REDUCE =>
                        -- Two-pass reduction: acc mod (2^255 - 19)
                        -- Pass 1: split acc into lo[254:0] and hi[509:255]
                        lo  := acc(254 downto 0);
                        hi  := acc(509 downto 255);
                        -- sum1 = lo + 19*hi
                        hi19 := mult19(hi);
                        s1_v := resize(lo, 260) + hi19;
                        sum1 <= s1_v;
                        state <= COND_SUB;

                    when COND_SUB =>
                        -- Pass 2: sum1 may be up to ~260 bits
                        lo2 := sum1(254 downto 0);
                        hi2 := sum1(259 downto 255);
                        hi2_19 := mult19(hi2);
                        s2_v := resize(lo2, 256) + resize(hi2_19, 256);
                        -- Conditional subtract: if s2_v >= p then subtract p
                        if s2_v >= CURVE25519_P then
                            result_r <= resize(s2_v - CURVE25519_P, 255);
                        else
                            result_r <= resize(s2_v, 255);
                        end if;
                        state <= DONE_STATE;

                    when DONE_STATE =>
                        done  <= '1';
                        state <= IDLE;

                end case;
            end if;
        end if;
    end process;

end architecture;
