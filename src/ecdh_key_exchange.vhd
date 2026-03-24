--------------------------------------------------------------------------------
-- ecdh_key_exchange.vhd
-- X25519 scalar multiplication using Montgomery ladder (RFC 7748)
-- Two sequential scalar multiplications:
--   Phase 0: shared_secret = clamp(private_key) * peer_public_key
--   Phase 1: public_key_out = clamp(private_key) * CURVE25519_BASE_U (=9)
-- VHDL-2008
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.chacha20_pkg.all;

entity ecdh_key_exchange is
    port (
        clk             : in  std_logic;
        rst             : in  std_logic;
        private_key     : in  unsigned(254 downto 0);
        peer_public_key : in  unsigned(254 downto 0);
        start           : in  std_logic;
        shared_secret   : out unsigned(254 downto 0);
        public_key_out  : out unsigned(254 downto 0);
        done            : out std_logic
    );
end entity ecdh_key_exchange;

architecture rtl of ecdh_key_exchange is

    -- FSM states
    type state_t is (
        IDLE,
        CLAMP_KEY,
        LADDER_INIT,
        LADDER_CSWAP,
        START_OPS,
        WAIT_ADD,
        CAPTURE_ADD,
        START_DBL,
        WAIT_DBL,
        CAPTURE_DBL,
        CSWAP_BACK,
        NEXT_BIT,
        INV_START,
        WAIT_INV,
        FINAL_MUL_START,
        WAIT_FINAL_MUL,
        SAVE_RESULT,
        CHECK_PHASE,
        DONE_STATE
    );

    signal state     : state_t := IDLE;

    -- Clamped key
    signal k_clamped : unsigned(254 downto 0) := (others => '0');

    -- Montgomery ladder registers: R0 = (r0x, r0z), R1 = (r1x, r1z)
    signal r0x_reg   : unsigned(254 downto 0) := (others => '0');
    signal r0z_reg   : unsigned(254 downto 0) := (others => '0');
    signal r1x_reg   : unsigned(254 downto 0) := (others => '0');
    signal r1z_reg   : unsigned(254 downto 0) := (others => '0');

    -- Saved copies for sequential add then double (double uses original R0)
    signal r0x_save  : unsigned(254 downto 0) := (others => '0');
    signal r0z_save  : unsigned(254 downto 0) := (others => '0');

    -- Base point for current ladder (peer_public_key or BASE_U)
    signal base_u    : unsigned(254 downto 0) := (others => '0');

    -- Bit counter for ladder
    signal bit_idx   : integer range 0 to 254 := 254;

    -- Phase: 0 = shared_secret computation, 1 = public_key computation
    signal phase     : std_logic := '0';

    -- Result registers
    signal ss_reg    : unsigned(254 downto 0) := (others => '0');
    signal pk_reg    : unsigned(254 downto 0) := (others => '0');

    -- Inverse result register
    signal z_inv_reg : unsigned(254 downto 0) := (others => '0');

    -- point_add signals
    signal pa_x_m    : unsigned(254 downto 0) := (others => '0');
    signal pa_z_m    : unsigned(254 downto 0) := (others => '0');
    signal pa_x_n    : unsigned(254 downto 0) := (others => '0');
    signal pa_z_n    : unsigned(254 downto 0) := (others => '0');
    signal pa_x_mn   : unsigned(254 downto 0) := (others => '0');
    signal pa_z_mn   : unsigned(254 downto 0) := (others => '0');
    signal pa_start  : std_logic := '0';
    signal pa_x_out  : unsigned(254 downto 0);
    signal pa_z_out  : unsigned(254 downto 0);
    signal pa_done   : std_logic;

    -- point_double signals
    signal pd_x_in   : unsigned(254 downto 0) := (others => '0');
    signal pd_z_in   : unsigned(254 downto 0) := (others => '0');
    signal pd_start  : std_logic := '0';
    signal pd_x_out  : unsigned(254 downto 0);
    signal pd_z_out  : unsigned(254 downto 0);
    signal pd_done   : std_logic;

    -- newton_raphson_inv signals
    signal nr_a      : unsigned(254 downto 0) := (others => '0');
    signal nr_start  : std_logic := '0';
    signal nr_result : unsigned(254 downto 0);
    signal nr_done   : std_logic;
    signal nr_conv   : std_logic;

    -- cordic_ec_mult signals (for final X * Z_inv)
    signal cm_a      : unsigned(254 downto 0) := (others => '0');
    signal cm_b      : unsigned(254 downto 0) := (others => '0');
    signal cm_start  : std_logic := '0';
    signal cm_result : unsigned(254 downto 0);
    signal cm_done   : std_logic;

begin

    ----------------------------------------------------------------------------
    -- Component instantiations
    ----------------------------------------------------------------------------

    u_point_add : entity work.point_add
        port map (
            clk   => clk,
            rst   => rst,
            X_m   => pa_x_m,
            Z_m   => pa_z_m,
            X_n   => pa_x_n,
            Z_n   => pa_z_n,
            X_mn  => pa_x_mn,
            Z_mn  => pa_z_mn,
            start => pa_start,
            X_out => pa_x_out,
            Z_out => pa_z_out,
            done  => pa_done
        );

    u_point_double : entity work.point_double
        port map (
            clk   => clk,
            rst   => rst,
            X_in  => pd_x_in,
            Z_in  => pd_z_in,
            start => pd_start,
            X_out => pd_x_out,
            Z_out => pd_z_out,
            done  => pd_done
        );

    u_newton_inv : entity work.newton_raphson_inv
        port map (
            clk       => clk,
            rst       => rst,
            a         => nr_a,
            start     => nr_start,
            result    => nr_result,
            done      => nr_done,
            converged => nr_conv
        );

    u_final_mult : entity work.cordic_ec_mult
        port map (
            clk    => clk,
            rst    => rst,
            a      => cm_a,
            b      => cm_b,
            start  => cm_start,
            result => cm_result,
            done   => cm_done
        );

    ----------------------------------------------------------------------------
    -- Main FSM
    ----------------------------------------------------------------------------
    process(clk)
        variable swap_bit : std_logic;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state    <= IDLE;
                done     <= '0';
                pa_start <= '0';
                pd_start <= '0';
                nr_start <= '0';
                cm_start <= '0';
                phase    <= '0';
                shared_secret  <= (others => '0');
                public_key_out <= (others => '0');
            else
                -- Default: deassert start pulses
                pa_start <= '0';
                pd_start <= '0';
                nr_start <= '0';
                cm_start <= '0';

                case state is

                    --------------------------------------------------------
                    when IDLE =>
                        done <= '0';
                        if start = '1' then
                            state <= CLAMP_KEY;
                        end if;

                    --------------------------------------------------------
                    -- RFC 7748 key clamping: clear bits 0,1,2; set bit 254
                    --------------------------------------------------------
                    when CLAMP_KEY =>
                        k_clamped(254)          <= '1';
                        k_clamped(253 downto 3) <= private_key(253 downto 3);
                        k_clamped(2 downto 0)   <= "000";
                        phase <= '0';
                        state <= LADDER_INIT;

                    --------------------------------------------------------
                    -- Initialize ladder for current phase
                    --------------------------------------------------------
                    when LADDER_INIT =>
                        -- R0 = (1, 0) = point at infinity
                        r0x_reg <= to_unsigned(1, 255);
                        r0z_reg <= (others => '0');

                        if phase = '0' then
                            -- Phase 0: k * peer_public_key
                            base_u  <= peer_public_key;
                            r1x_reg <= peer_public_key;
                        else
                            -- Phase 1: k * BASE_U
                            base_u  <= CURVE25519_BASE_U;
                            r1x_reg <= CURVE25519_BASE_U;
                        end if;
                        r1z_reg <= to_unsigned(1, 255);

                        bit_idx <= 254;
                        state   <= LADDER_CSWAP;

                    --------------------------------------------------------
                    -- Constant-time conditional swap based on k_clamped(bit_idx)
                    --------------------------------------------------------
                    when LADDER_CSWAP =>
                        swap_bit := k_clamped(bit_idx);
                        -- Save original R0 for point_double (which runs after add)
                        r0x_save <= r0x_reg;
                        r0z_save <= r0z_reg;

                        if swap_bit = '1' then
                            -- Swap R0 and R1
                            r0x_reg <= r1x_reg;
                            r0z_reg <= r1z_reg;
                            r1x_reg <= r0x_reg;
                            r1z_reg <= r0z_reg;
                            -- Also update saved R0 to swapped value
                            r0x_save <= r1x_reg;
                            r0z_save <= r1z_reg;
                        end if;

                        state <= START_OPS;

                    --------------------------------------------------------
                    -- Start point_add(R0, R1, base_point)
                    -- After cswap, R0 and R1 may be swapped
                    --------------------------------------------------------
                    when START_OPS =>
                        -- point_add inputs: differential add of R0 and R1
                        -- X_mn, Z_mn = the base point (difference = R1 - R0 = P)
                        pa_x_m  <= r0x_reg;
                        pa_z_m  <= r0z_reg;
                        pa_x_n  <= r1x_reg;
                        pa_z_n  <= r1z_reg;
                        pa_x_mn <= base_u;
                        pa_z_mn <= to_unsigned(1, 255);
                        pa_start <= '1';
                        state    <= WAIT_ADD;

                    --------------------------------------------------------
                    when WAIT_ADD =>
                        if pa_done = '1' then
                            state <= CAPTURE_ADD;
                        end if;

                    --------------------------------------------------------
                    -- Save add result as new R1; set up inputs for double
                    --------------------------------------------------------
                    when CAPTURE_ADD =>
                        r1x_reg  <= pa_x_out;
                        r1z_reg  <= pa_z_out;
                        -- Feed R0 into point_double inputs, start next cycle
                        pd_x_in  <= r0x_reg;
                        pd_z_in  <= r0z_reg;
                        state    <= START_DBL;

                    --------------------------------------------------------
                    -- Start point_double on R0
                    --------------------------------------------------------
                    when START_DBL =>
                        pd_start <= '1';
                        state    <= WAIT_DBL;

                    --------------------------------------------------------
                    when WAIT_DBL =>
                        if pd_done = '1' then
                            state <= CAPTURE_DBL;
                        end if;

                    --------------------------------------------------------
                    -- Save double result as new R0
                    --------------------------------------------------------
                    when CAPTURE_DBL =>
                        r0x_reg <= pd_x_out;
                        r0z_reg <= pd_z_out;
                        state   <= CSWAP_BACK;

                    --------------------------------------------------------
                    -- Undo the conditional swap
                    --------------------------------------------------------
                    when CSWAP_BACK =>
                        swap_bit := k_clamped(bit_idx);
                        if swap_bit = '1' then
                            -- Swap back R0 and R1
                            r0x_reg <= r1x_reg;
                            r0z_reg <= r1z_reg;
                            r1x_reg <= r0x_reg;
                            r1z_reg <= r0z_reg;
                        end if;
                        state <= NEXT_BIT;

                    --------------------------------------------------------
                    -- Decrement bit counter or finish ladder
                    --------------------------------------------------------
                    when NEXT_BIT =>
                        if bit_idx = 0 then
                            -- Ladder complete, convert to affine
                            state <= INV_START;
                        else
                            bit_idx <= bit_idx - 1;
                            state   <= LADDER_CSWAP;
                        end if;

                    --------------------------------------------------------
                    -- Start modular inverse of R0.Z
                    --------------------------------------------------------
                    when INV_START =>
                        nr_a     <= r0z_reg;
                        nr_start <= '1';
                        state    <= WAIT_INV;

                    --------------------------------------------------------
                    when WAIT_INV =>
                        if nr_done = '1' then
                            z_inv_reg <= nr_result;
                            state     <= FINAL_MUL_START;
                        end if;

                    --------------------------------------------------------
                    -- Compute affine x = R0.X * Z_inv mod p
                    --------------------------------------------------------
                    when FINAL_MUL_START =>
                        cm_a     <= r0x_reg;
                        cm_b     <= z_inv_reg;
                        cm_start <= '1';
                        state    <= WAIT_FINAL_MUL;

                    --------------------------------------------------------
                    when WAIT_FINAL_MUL =>
                        if cm_done = '1' then
                            state <= SAVE_RESULT;
                        end if;

                    --------------------------------------------------------
                    -- Store result for current phase
                    --------------------------------------------------------
                    when SAVE_RESULT =>
                        if phase = '0' then
                            ss_reg <= cm_result;
                        else
                            pk_reg <= cm_result;
                        end if;
                        state <= CHECK_PHASE;

                    --------------------------------------------------------
                    -- If phase 0 done, start phase 1; else finish
                    --------------------------------------------------------
                    when CHECK_PHASE =>
                        if phase = '0' then
                            phase <= '1';
                            state <= LADDER_INIT;
                        else
                            shared_secret  <= ss_reg;
                            public_key_out <= pk_reg;
                            done  <= '1';
                            state <= DONE_STATE;
                        end if;

                    --------------------------------------------------------
                    when DONE_STATE =>
                        done <= '1';
                        if start = '0' then
                            state <= IDLE;
                        end if;

                end case;
            end if;
        end if;
    end process;

end architecture rtl;
