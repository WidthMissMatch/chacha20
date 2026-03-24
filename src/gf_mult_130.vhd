-- GF(2^130-5) Modular Multiplier
-- Computes (a * b) mod (2^130 - 5) using 5-limb schoolbook multiplication
-- Latency: 7 clocks (IDLE->PP->ACCUM_1->ACCUM_2A->ACCUM_2B->REDUCE_STAGE->REDUCE_WAIT->DONE)
-- P1 change: REDUCE_WAIT added (extra cycle for combinational gf_reduce_130 to settle)
-- P6 change: ACCUMULATE split into ACCUM_1 (cols 0..4) + ACCUM_2 (cols 5..9 + carry)
-- P7 change: ACCUM_2 split into ACCUM_2A (high-col accumulate) + ACCUM_2B (carry-propagate)
--            Breaks the DSP->LUT->CARRY8 critical path that caused WNS=-0.825ns at 125MHz
-- Each limb is 26 bits; 5 limbs * 26 bits = 130 bits

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.poly1305_pkg.all;

entity gf_mult_130 is
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        a       : in  poly_word;
        b       : in  poly_word;
        start   : in  std_logic;
        product : out poly_word;
        done    : out std_logic
    );
end entity gf_mult_130;

architecture rtl of gf_mult_130 is

    type fsm_state is (IDLE, PARTIAL_PRODUCTS, ACCUM_1, ACCUM_2A, ACCUM_2B,
                       REDUCE_STAGE, REDUCE_WAIT, DONE_STATE);
    signal state : fsm_state := IDLE;

    -- 5 limbs of 26 bits each (limb 4 gets top 26 bits: bits 129..104)
    type limb_array is array(0 to 4) of unsigned(25 downto 0);
    signal a_limbs, b_limbs : limb_array;

    -- 25 partial products (52 bits each: 26 * 26)
    type pp_array is array(0 to 24) of unsigned(51 downto 0);
    signal pp : pp_array;

    -- Intermediate column sums from ACCUM_1 (columns 0..4)
    type col_lo_array is array(0 to 4) of unsigned(63 downto 0);
    signal cols_lo : col_lo_array;

    -- Intermediate column sums from ACCUM_2A (columns 5..9)
    type col_hi_array is array(5 to 9) of unsigned(63 downto 0);
    signal cols_hi : col_hi_array;

    -- Full 260-bit product for reduction
    signal full_product : unsigned(259 downto 0);

    -- Reduction output
    signal reduced : poly_word;

begin

    -- Combinational reducer
    reducer: entity work.gf_reduce_130
        port map (
            val_in  => full_product,
            val_out => reduced
        );

    process(clk)
        -- Column accumulators: 10 columns (indices 0..9), each limb position
        -- Column k accumulates partial products where i+j = k
        -- Result limbs are 26 bits, but accumulators need more headroom
        type col_array is array(0 to 9) of unsigned(63 downto 0);
        variable cols : col_array;
        variable carry : unsigned(63 downto 0);
        variable full  : unsigned(259 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state <= IDLE;
                done  <= '0';
            else
                done <= '0';

                case state is
                    when IDLE =>
                        if start = '1' then
                            -- Decompose into 5 x 26-bit limbs
                            for i in 0 to 3 loop
                                a_limbs(i) <= a(i*26 + 25 downto i*26);
                                b_limbs(i) <= b(i*26 + 25 downto i*26);
                            end loop;
                            -- Limb 4: bits 129..104 (26 bits)
                            a_limbs(4) <= a(129 downto 104);
                            b_limbs(4) <= b(129 downto 104);
                            state <= PARTIAL_PRODUCTS;
                        end if;

                    when PARTIAL_PRODUCTS =>
                        -- Compute 25 partial products
                        for i in 0 to 4 loop
                            for j in 0 to 4 loop
                                pp(i*5 + j) <= a_limbs(i) * b_limbs(j);
                            end loop;
                        end loop;
                        state <= ACCUM_1;

                    when ACCUM_1 =>
                        -- Accumulate partial products into columns 0..4
                        -- Column k = sum of pp(i*5+j) where i+j = k, for k in 0..4
                        for k in 0 to 4 loop
                            cols(k) := (others => '0');
                        end loop;
                        for i in 0 to 4 loop
                            for j in 0 to 4 loop
                                if (i + j) <= 4 then
                                    cols(i+j) := cols(i+j) + resize(pp(i*5 + j), 64);
                                end if;
                            end loop;
                        end loop;
                        -- Register columns 0..4 for ACCUM_2
                        for k in 0 to 4 loop
                            cols_lo(k) <= cols(k);
                        end loop;
                        state <= ACCUM_2A;

                    when ACCUM_2A =>
                        -- Stage 1: accumulate pp into high columns only.
                        -- Breaks DSP->LUT->CARRY8 chain by registering cols_hi FFs.
                        for k in 5 to 9 loop
                            cols(k) := (others => '0');
                        end loop;
                        for i in 0 to 4 loop
                            for j in 0 to 4 loop
                                if (i + j) >= 5 then
                                    cols(i+j) := cols(i+j) + resize(pp(i*5 + j), 64);
                                end if;
                            end loop;
                        end loop;
                        for k in 5 to 9 loop
                            cols_hi(k) <= cols(k);
                        end loop;
                        state <= ACCUM_2B;

                    when ACCUM_2B =>
                        -- Stage 2: all inputs are registered FFs (cols_lo, cols_hi).
                        -- Carry-propagate through all 10 columns and assemble full_product.
                        for k in 0 to 4 loop
                            cols(k) := cols_lo(k);
                        end loop;
                        for k in 5 to 9 loop
                            cols(k) := cols_hi(k);
                        end loop;
                        full  := (others => '0');
                        carry := (others => '0');
                        for k in 0 to 9 loop
                            cols(k) := cols(k) + carry;
                            if k < 9 then
                                -- Each column position is 26 bits wide
                                full(k*26 + 25 downto k*26) := cols(k)(25 downto 0);
                                carry := shift_right(cols(k), 26);
                            else
                                -- Last column: take all remaining bits (up to bit 259)
                                -- k=9 starts at bit 234, need bits up to 259 = 26 bits
                                full(259 downto 234) := cols(k)(25 downto 0);
                            end if;
                        end loop;
                        full_product <= full;
                        state <= REDUCE_STAGE;

                    when REDUCE_STAGE =>
                        -- full_product drives gf_reduce_130 combinationally.
                        -- Wait one extra cycle (REDUCE_WAIT) so the combinational
                        -- path from full_product FF through gf_reduce_130 to product FF
                        -- spans two clock cycles, meeting timing at 200 MHz.
                        state <= REDUCE_WAIT;

                    when REDUCE_WAIT =>
                        -- Capture the settled combinational reduction result.
                        product <= reduced;
                        state   <= DONE_STATE;

                    when DONE_STATE =>
                        done  <= '1';
                        state <= IDLE;
                end case;
            end if;
        end if;
    end process;

end architecture rtl;
