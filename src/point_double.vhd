-------------------------------------------------------------------------------
-- point_double.vhd
-- Montgomery point doubling on Curve25519
-- [2]P from P in projective (X:Z) coordinates
-- Uses one time-shared cordic_ec_mult for 5 field multiplications
-- VHDL-2008
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.chacha20_pkg.all;

entity point_double is
    port (
        clk    : in  std_logic;
        rst    : in  std_logic;
        X_in   : in  unsigned(254 downto 0);
        Z_in   : in  unsigned(254 downto 0);
        start  : in  std_logic;
        X_out  : out unsigned(254 downto 0);
        Z_out  : out unsigned(254 downto 0);
        done   : out std_logic
    );
end entity;

architecture rtl of point_double is

    -- FSM states
    type state_t is (
        IDLE,
        LATCH_INPUTS,
        MUL1_START, WAIT_MUL1,   -- sum_sq = sum * sum = (X+Z)^2
        MUL2_START, WAIT_MUL2,   -- diff_sq = diff * diff = (X-Z)^2
        COMPUTE_4XZ,             -- four_xz = sum_sq - diff_sq
        MUL3_START, WAIT_MUL3,   -- x_out = sum_sq * diff_sq
        MUL4_START, WAIT_MUL4,   -- a24_4xz = A24 * four_xz
        COMPUTE_SUM,             -- tmp = diff_sq + a24_4xz
        MUL5_START, WAIT_MUL5,   -- z_out = four_xz * tmp
        DONE_STATE
    );
    signal state : state_t := IDLE;

    -- Multiplier interface
    signal mul_a     : unsigned(254 downto 0);
    signal mul_b     : unsigned(254 downto 0);
    signal mul_start : std_logic;
    signal mul_result: unsigned(254 downto 0);
    signal mul_done  : std_logic;

    -- Precomputed values from LATCH_INPUTS
    signal sum_val  : unsigned(254 downto 0);  -- X + Z
    signal diff_val : unsigned(254 downto 0);  -- X - Z

    -- Intermediate results
    signal sum_sq_reg   : unsigned(254 downto 0);  -- (X+Z)^2
    signal diff_sq_reg  : unsigned(254 downto 0);  -- (X-Z)^2
    signal four_xz_reg  : unsigned(254 downto 0);  -- (X+Z)^2 - (X-Z)^2 = 4XZ
    signal a24_4xz_reg  : unsigned(254 downto 0);  -- A24 * 4XZ
    signal tmp_reg      : unsigned(254 downto 0);  -- diff_sq + A24*4XZ

    -- Output registers
    signal x_out_reg : unsigned(254 downto 0);
    signal z_out_reg : unsigned(254 downto 0);

begin

    -- Instantiate single time-shared field multiplier
    mult_inst : entity work.cordic_ec_mult
        port map (
            clk    => clk,
            rst    => rst,
            a      => mul_a,
            b      => mul_b,
            start  => mul_start,
            result => mul_result,
            done   => mul_done
        );

    -- Output assignments
    X_out <= x_out_reg;
    Z_out <= z_out_reg;

    -- Main FSM
    process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state     <= IDLE;
                done      <= '0';
                mul_start <= '0';
                x_out_reg <= (others => '0');
                z_out_reg <= (others => '0');
            else
                -- Defaults
                done      <= '0';
                mul_start <= '0';

                case state is

                    when IDLE =>
                        if start = '1' then
                            state <= LATCH_INPUTS;
                        end if;

                    when LATCH_INPUTS =>
                        -- Precompute sum and difference
                        sum_val  <= gf25519_add(X_in, Z_in);
                        diff_val <= gf25519_sub(X_in, Z_in);
                        state    <= MUL1_START;

                    -----------------------------------------------------------
                    -- MUL1: sum_sq = (X + Z)^2
                    -----------------------------------------------------------
                    when MUL1_START =>
                        mul_a     <= sum_val;
                        mul_b     <= sum_val;
                        mul_start <= '1';
                        state     <= WAIT_MUL1;

                    when WAIT_MUL1 =>
                        if mul_done = '1' then
                            sum_sq_reg <= mul_result;
                            state      <= MUL2_START;
                        end if;

                    -----------------------------------------------------------
                    -- MUL2: diff_sq = (X - Z)^2
                    -----------------------------------------------------------
                    when MUL2_START =>
                        mul_a     <= diff_val;
                        mul_b     <= diff_val;
                        mul_start <= '1';
                        state     <= WAIT_MUL2;

                    when WAIT_MUL2 =>
                        if mul_done = '1' then
                            diff_sq_reg <= mul_result;
                            state       <= COMPUTE_4XZ;
                        end if;

                    -----------------------------------------------------------
                    -- Compute four_xz = sum_sq - diff_sq = 4*X*Z
                    -----------------------------------------------------------
                    when COMPUTE_4XZ =>
                        four_xz_reg <= gf25519_sub(sum_sq_reg, diff_sq_reg);
                        state       <= MUL3_START;

                    -----------------------------------------------------------
                    -- MUL3: X_{2m} = sum_sq * diff_sq
                    -----------------------------------------------------------
                    when MUL3_START =>
                        mul_a     <= sum_sq_reg;
                        mul_b     <= diff_sq_reg;
                        mul_start <= '1';
                        state     <= WAIT_MUL3;

                    when WAIT_MUL3 =>
                        if mul_done = '1' then
                            x_out_reg <= mul_result;
                            state     <= MUL4_START;
                        end if;

                    -----------------------------------------------------------
                    -- MUL4: a24_4xz = A24_CURVE25519 * four_xz
                    -----------------------------------------------------------
                    when MUL4_START =>
                        mul_a     <= A24_CURVE25519;
                        mul_b     <= four_xz_reg;
                        mul_start <= '1';
                        state     <= WAIT_MUL4;

                    when WAIT_MUL4 =>
                        if mul_done = '1' then
                            a24_4xz_reg <= mul_result;
                            state       <= COMPUTE_SUM;
                        end if;

                    -----------------------------------------------------------
                    -- Compute tmp = diff_sq + a24_4xz
                    -----------------------------------------------------------
                    when COMPUTE_SUM =>
                        tmp_reg <= gf25519_add(diff_sq_reg, a24_4xz_reg);
                        state   <= MUL5_START;

                    -----------------------------------------------------------
                    -- MUL5: Z_{2m} = four_xz * tmp
                    -----------------------------------------------------------
                    when MUL5_START =>
                        mul_a     <= four_xz_reg;
                        mul_b     <= tmp_reg;
                        mul_start <= '1';
                        state     <= WAIT_MUL5;

                    when WAIT_MUL5 =>
                        if mul_done = '1' then
                            z_out_reg <= mul_result;
                            state     <= DONE_STATE;
                        end if;

                    -----------------------------------------------------------
                    -- DONE: pulse done for one clock cycle
                    -----------------------------------------------------------
                    when DONE_STATE =>
                        done  <= '1';
                        state <= IDLE;

                end case;
            end if;
        end if;
    end process;

end architecture;
