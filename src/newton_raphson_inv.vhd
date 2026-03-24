--------------------------------------------------------------------------------
-- newton_raphson_inv.vhd
--
-- Modular inverse in GF(2^255-19) using Fermat's little theorem:
--   a^(-1) = a^(p-2) mod p
--
-- Implemented as binary exponentiation (square-and-multiply) using a single
-- cordic_ec_mult instance for all GF(2^255-19) multiplications.
--
-- For each bit of the exponent (p-2), from bit 254 down to 0:
--   1. Square the accumulator:  accum = accum * accum mod p
--   2. If exponent bit is 1:   accum = accum * a     mod p
--
-- Total operations: 254 squarings + ~127 multiplies (Hamming weight of p-2).
-- Each multiply takes ~259 clocks in cordic_ec_mult, so total ~99K clocks.
--
-- The converged output is always '1' for non-zero input (Fermat's theorem
-- guarantees correctness). For a = 0, the output is 0 (no inverse exists).
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.chacha20_pkg.all;

entity newton_raphson_inv is
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        a         : in  unsigned(254 downto 0);
        start     : in  std_logic;
        result    : out unsigned(254 downto 0);
        done      : out std_logic;
        converged : out std_logic
    );
end entity newton_raphson_inv;

architecture rtl of newton_raphson_inv is

    ---------------------------------------------------------------------------
    -- Exponent: p - 2 = 2^255 - 19 - 2 = 2^255 - 21
    -- Hex: 7FFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFEB
    -- This is 256 bits wide; we only use bits 254 downto 0 (bit 255 is 0).
    ---------------------------------------------------------------------------
    constant P_MINUS_2 : unsigned(254 downto 0) :=
        "111" &                                             -- bits 254..252
        x"FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF" &
        x"EB";                                              -- bits 251..0
    -- Full value: 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEB

    ---------------------------------------------------------------------------
    -- FSM states
    ---------------------------------------------------------------------------
    type state_t is (
        IDLE,
        INIT,
        SQUARE_START,
        WAIT_SQUARE,
        CHECK_MUL,
        MUL_START,
        WAIT_MUL,
        NEXT_BIT,
        DONE_STATE
    );

    signal fsm_state : state_t;

    ---------------------------------------------------------------------------
    -- Internal registers
    ---------------------------------------------------------------------------
    signal a_reg       : unsigned(254 downto 0);  -- latched input
    signal accum       : unsigned(254 downto 0);  -- running accumulator
    signal bit_idx     : integer range -1 to 254; -- current exponent bit index

    ---------------------------------------------------------------------------
    -- Multiplier interface signals
    ---------------------------------------------------------------------------
    signal mult_a      : unsigned(254 downto 0);
    signal mult_b      : unsigned(254 downto 0);
    signal mult_start  : std_logic;
    signal mult_result : unsigned(254 downto 0);
    signal mult_done   : std_logic;

    ---------------------------------------------------------------------------
    -- Zero check
    ---------------------------------------------------------------------------
    signal a_is_zero   : std_logic;

begin

    ---------------------------------------------------------------------------
    -- Single cordic_ec_mult instance, time-shared for squares and multiplies
    ---------------------------------------------------------------------------
    u_mult : entity work.cordic_ec_mult
        port map (
            clk    => clk,
            rst    => rst,
            a      => mult_a,
            b      => mult_b,
            start  => mult_start,
            result => mult_result,
            done   => mult_done
        );

    ---------------------------------------------------------------------------
    -- Main FSM
    ---------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                fsm_state  <= IDLE;
                done       <= '0';
                converged  <= '0';
                result     <= (others => '0');
                mult_start <= '0';
                mult_a     <= (others => '0');
                mult_b     <= (others => '0');
                a_reg      <= (others => '0');
                accum      <= (others => '0');
                bit_idx    <= 254;
                a_is_zero  <= '0';
            else
                -- Default: deassert one-shot signals
                mult_start <= '0';
                done       <= '0';

                case fsm_state is

                    -------------------------------------------------------
                    -- IDLE: wait for start pulse
                    -------------------------------------------------------
                    when IDLE =>
                        converged <= '0';
                        if start = '1' then
                            fsm_state <= INIT;
                        end if;

                    -------------------------------------------------------
                    -- INIT: latch input, initialise accumulator to 1
                    -------------------------------------------------------
                    when INIT =>
                        a_reg   <= a;
                        accum   <= to_unsigned(1, 255);
                        bit_idx <= 254;

                        -- Check for zero input (no inverse exists)
                        if a = to_unsigned(0, 255) then
                            a_is_zero <= '1';
                        else
                            a_is_zero <= '0';
                        end if;

                        fsm_state <= SQUARE_START;

                    -------------------------------------------------------
                    -- SQUARE_START: accum = accum * accum mod p
                    -------------------------------------------------------
                    when SQUARE_START =>
                        mult_a     <= accum;
                        mult_b     <= accum;
                        mult_start <= '1';
                        fsm_state  <= WAIT_SQUARE;

                    -------------------------------------------------------
                    -- WAIT_SQUARE: wait for squaring to complete
                    -------------------------------------------------------
                    when WAIT_SQUARE =>
                        if mult_done = '1' then
                            accum     <= mult_result;
                            fsm_state <= CHECK_MUL;
                        end if;

                    -------------------------------------------------------
                    -- CHECK_MUL: if exponent bit is 1, multiply by a
                    -------------------------------------------------------
                    when CHECK_MUL =>
                        if P_MINUS_2(bit_idx) = '1' then
                            fsm_state <= MUL_START;
                        else
                            fsm_state <= NEXT_BIT;
                        end if;

                    -------------------------------------------------------
                    -- MUL_START: accum = accum * a_reg mod p
                    -------------------------------------------------------
                    when MUL_START =>
                        mult_a     <= accum;
                        mult_b     <= a_reg;
                        mult_start <= '1';
                        fsm_state  <= WAIT_MUL;

                    -------------------------------------------------------
                    -- WAIT_MUL: wait for multiplication to complete
                    -------------------------------------------------------
                    when WAIT_MUL =>
                        if mult_done = '1' then
                            accum     <= mult_result;
                            fsm_state <= NEXT_BIT;
                        end if;

                    -------------------------------------------------------
                    -- NEXT_BIT: advance to next exponent bit or finish
                    -------------------------------------------------------
                    when NEXT_BIT =>
                        if bit_idx = 0 then
                            fsm_state <= DONE_STATE;
                        else
                            bit_idx   <= bit_idx - 1;
                            fsm_state <= SQUARE_START;
                        end if;

                    -------------------------------------------------------
                    -- DONE_STATE: output result, assert done
                    -------------------------------------------------------
                    when DONE_STATE =>
                        if a_is_zero = '1' then
                            result    <= (others => '0');
                            converged <= '0';
                        else
                            result    <= accum;
                            converged <= '1';
                        end if;
                        done      <= '1';
                        fsm_state <= IDLE;

                end case;
            end if;
        end if;
    end process;

end architecture rtl;
