-------------------------------------------------------------------------------
-- point_add.vhd
-- Montgomery differential addition on Curve25519
-- P_{m+n} from P_m, P_n, P_{m-n} in projective (X:Z) coordinates
-- Uses one time-shared cordic_ec_mult for 6 field multiplications
-- VHDL-2008
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.chacha20_pkg.all;

entity point_add is
    port (
        clk    : in  std_logic;
        rst    : in  std_logic;
        -- Inputs: points P_m, P_n in projective coords, and P_{m-n} (base difference)
        X_m    : in  unsigned(254 downto 0);
        Z_m    : in  unsigned(254 downto 0);
        X_n    : in  unsigned(254 downto 0);
        Z_n    : in  unsigned(254 downto 0);
        X_mn   : in  unsigned(254 downto 0);  -- X of P_{m-n}
        Z_mn   : in  unsigned(254 downto 0);  -- Z of P_{m-n}
        start  : in  std_logic;
        -- Outputs: P_{m+n} in projective coords
        X_out  : out unsigned(254 downto 0);
        Z_out  : out unsigned(254 downto 0);
        done   : out std_logic
    );
end entity;

architecture rtl of point_add is

    -- FSM states
    type state_t is (
        IDLE,
        LATCH_INPUTS,
        MUL1_START, WAIT_MUL1,   -- u = (Xm - Zm) * (Xn + Zn)
        MUL2_START, WAIT_MUL2,   -- v = (Xm + Zm) * (Xn - Zn)
        COMPUTE_ADD_SUB,         -- add_val = u + v, sub_val = u - v
        MUL3_START, WAIT_MUL3,   -- add_sq = add_val * add_val
        MUL4_START, WAIT_MUL4,   -- sub_sq = sub_val * sub_val
        MUL5_START, WAIT_MUL5,   -- X_out = Z_mn * add_sq
        MUL6_START, WAIT_MUL6,   -- Z_out = X_mn * sub_sq
        DONE_STATE
    );
    signal state : state_t := IDLE;

    -- Multiplier interface
    signal mul_a     : unsigned(254 downto 0);
    signal mul_b     : unsigned(254 downto 0);
    signal mul_start : std_logic;
    signal mul_result: unsigned(254 downto 0);
    signal mul_done  : std_logic;

    -- Latched inputs
    signal xm_reg  : unsigned(254 downto 0);
    signal zm_reg  : unsigned(254 downto 0);
    signal xn_reg  : unsigned(254 downto 0);
    signal zn_reg  : unsigned(254 downto 0);
    signal xmn_reg : unsigned(254 downto 0);
    signal zmn_reg : unsigned(254 downto 0);

    -- Precomputed sums/differences for first two multiplications
    signal diff_m : unsigned(254 downto 0);  -- Xm - Zm
    signal sum_n  : unsigned(254 downto 0);  -- Xn + Zn
    signal sum_m  : unsigned(254 downto 0);  -- Xm + Zm
    signal diff_n : unsigned(254 downto 0);  -- Xn - Zn

    -- Intermediate results
    signal u_reg      : unsigned(254 downto 0);  -- (Xm-Zm)*(Xn+Zn)
    signal v_reg      : unsigned(254 downto 0);  -- (Xm+Zm)*(Xn-Zn)
    signal add_val    : unsigned(254 downto 0);  -- u + v
    signal sub_val    : unsigned(254 downto 0);  -- u - v
    signal add_sq_reg : unsigned(254 downto 0);  -- (u+v)^2
    signal sub_sq_reg : unsigned(254 downto 0);  -- (u-v)^2

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
                        -- Latch all inputs
                        xm_reg  <= X_m;
                        zm_reg  <= Z_m;
                        xn_reg  <= X_n;
                        zn_reg  <= Z_n;
                        xmn_reg <= X_mn;
                        zmn_reg <= Z_mn;
                        -- Precompute sums and differences
                        diff_m <= gf25519_sub(X_m, Z_m);
                        sum_n  <= gf25519_add(X_n, Z_n);
                        sum_m  <= gf25519_add(X_m, Z_m);
                        diff_n <= gf25519_sub(X_n, Z_n);
                        state  <= MUL1_START;

                    -----------------------------------------------------------
                    -- MUL1: u = (Xm - Zm) * (Xn + Zn)
                    -----------------------------------------------------------
                    when MUL1_START =>
                        mul_a     <= diff_m;
                        mul_b     <= sum_n;
                        mul_start <= '1';
                        state     <= WAIT_MUL1;

                    when WAIT_MUL1 =>
                        if mul_done = '1' then
                            u_reg <= mul_result;
                            state <= MUL2_START;
                        end if;

                    -----------------------------------------------------------
                    -- MUL2: v = (Xm + Zm) * (Xn - Zn)
                    -----------------------------------------------------------
                    when MUL2_START =>
                        mul_a     <= sum_m;
                        mul_b     <= diff_n;
                        mul_start <= '1';
                        state     <= WAIT_MUL2;

                    when WAIT_MUL2 =>
                        if mul_done = '1' then
                            v_reg <= mul_result;
                            state <= COMPUTE_ADD_SUB;
                        end if;

                    -----------------------------------------------------------
                    -- Compute add = u + v, sub = u - v
                    -----------------------------------------------------------
                    when COMPUTE_ADD_SUB =>
                        add_val <= gf25519_add(u_reg, mul_result);
                        sub_val <= gf25519_sub(u_reg, mul_result);
                        state   <= MUL3_START;

                    -----------------------------------------------------------
                    -- MUL3: add_sq = (u + v)^2
                    -----------------------------------------------------------
                    when MUL3_START =>
                        mul_a     <= add_val;
                        mul_b     <= add_val;
                        mul_start <= '1';
                        state     <= WAIT_MUL3;

                    when WAIT_MUL3 =>
                        if mul_done = '1' then
                            add_sq_reg <= mul_result;
                            state      <= MUL4_START;
                        end if;

                    -----------------------------------------------------------
                    -- MUL4: sub_sq = (u - v)^2
                    -----------------------------------------------------------
                    when MUL4_START =>
                        mul_a     <= sub_val;
                        mul_b     <= sub_val;
                        mul_start <= '1';
                        state     <= WAIT_MUL4;

                    when WAIT_MUL4 =>
                        if mul_done = '1' then
                            sub_sq_reg <= mul_result;
                            state      <= MUL5_START;
                        end if;

                    -----------------------------------------------------------
                    -- MUL5: X_{m+n} = Z_{m-n} * add_sq
                    -----------------------------------------------------------
                    when MUL5_START =>
                        mul_a     <= zmn_reg;
                        mul_b     <= add_sq_reg;
                        mul_start <= '1';
                        state     <= WAIT_MUL5;

                    when WAIT_MUL5 =>
                        if mul_done = '1' then
                            x_out_reg <= mul_result;
                            state     <= MUL6_START;
                        end if;

                    -----------------------------------------------------------
                    -- MUL6: Z_{m+n} = X_{m-n} * sub_sq
                    -----------------------------------------------------------
                    when MUL6_START =>
                        mul_a     <= xmn_reg;
                        mul_b     <= sub_sq_reg;
                        mul_start <= '1';
                        state     <= WAIT_MUL6;

                    when WAIT_MUL6 =>
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
