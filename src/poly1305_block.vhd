-- Poly1305 Single Block Processor
-- Computes: acc = (acc + padded_block) * r mod (2^130 - 5)
-- Latency: ~6 clocks (ADD -> MULTIPLY(4 clk) -> DONE)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.poly1305_pkg.all;

entity poly1305_block is
    port (
        clk        : in  std_logic;
        rst        : in  std_logic;
        -- Inputs
        acc_in     : in  poly_word;        -- Current accumulator
        block_in   : in  std_logic_vector(127 downto 0);  -- Message block
        byte_count : in  natural range 0 to 16;           -- Valid bytes in block
        r_clamped  : in  poly_word;        -- Clamped r key
        start      : in  std_logic;
        -- Outputs
        acc_out    : out poly_word;         -- Updated accumulator
        done       : out std_logic
    );
end entity poly1305_block;

architecture rtl of poly1305_block is

    type fsm_state is (IDLE, ADD_BLOCK, WAIT_MULT, CAPTURE, DONE_STATE);
    signal state : fsm_state := IDLE;

    signal padded   : poly_word;
    signal sum_val  : unsigned(130 downto 0);  -- acc + padded (131 bits)
    signal mult_a   : poly_word;
    signal mult_b   : poly_word;
    signal mult_start : std_logic;
    signal mult_prod  : poly_word;
    signal mult_done  : std_logic;

begin

    -- Instantiate multiplier
    mult_inst: entity work.gf_mult_130
        port map (
            clk     => clk,
            rst     => rst,
            a       => mult_a,
            b       => mult_b,
            start   => mult_start,
            product => mult_prod,
            done    => mult_done
        );

    mult_b <= r_clamped;

    process(clk)
        variable sum_reduced : poly_word;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state      <= IDLE;
                done       <= '0';
                mult_start <= '0';
            else
                done       <= '0';
                mult_start <= '0';

                case state is
                    when IDLE =>
                        if start = '1' then
                            -- Pad the block
                            padded <= poly_pad_block(block_in, byte_count);
                            state  <= ADD_BLOCK;
                        end if;

                    when ADD_BLOCK =>
                        -- acc + padded_block (mod p not needed here since
                        -- multiplier handles inputs up to 2^130-1)
                        sum_val <= resize(acc_in, 131) + resize(padded, 131);
                        state   <= WAIT_MULT;

                    when WAIT_MULT =>
                        -- Reduce sum to 130 bits if needed (simple: if >= P, subtract P)
                        if sum_val >= POLY_P then
                            mult_a <= resize(sum_val - POLY_P, 130);
                        else
                            mult_a <= sum_val(129 downto 0);
                        end if;
                        mult_start <= '1';
                        state      <= CAPTURE;

                    when CAPTURE =>
                        if mult_done = '1' then
                            acc_out <= mult_prod;
                            state   <= DONE_STATE;
                        end if;

                    when DONE_STATE =>
                        done  <= '1';
                        state <= IDLE;
                end case;
            end if;
        end if;
    end process;

end architecture rtl;
