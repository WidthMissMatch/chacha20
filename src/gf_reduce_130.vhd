-- GF(2^130-5) Modular Reduction
-- Reduces a 260-bit value to 130 bits mod (2^130 - 5)
-- Combinational: split at bit 130, upper * 5 + lower, conditional subtract
-- Since upper is at most 130 bits and *5 gives at most 133 bits,
-- we need at most 2 conditional subtracts.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.poly1305_pkg.all;

entity gf_reduce_130 is
    port (
        val_in  : in  unsigned(259 downto 0);
        val_out : out poly_word
    );
end entity gf_reduce_130;

architecture rtl of gf_reduce_130 is
begin
    process(val_in)
        variable lower   : unsigned(129 downto 0);  -- bits [129:0]
        variable upper   : unsigned(129 downto 0);  -- bits [259:130]
        variable upper5  : unsigned(132 downto 0);  -- upper * 5 (133 bits max)
        variable sum1    : unsigned(133 downto 0);  -- lower + upper*5 (134 bits)
        -- After first reduction, if sum1 >= 2^130, need to reduce again
        variable lower2  : unsigned(129 downto 0);
        variable upper2  : unsigned(3 downto 0);    -- at most 4 bits above bit 130
        variable upper2x5: unsigned(6 downto 0);    -- upper2 * 5 (7 bits max)
        variable sum2    : unsigned(130 downto 0);  -- lower2 + upper2*5 (131 bits)
        variable result  : unsigned(130 downto 0);
    begin
        lower := val_in(129 downto 0);
        upper := val_in(259 downto 130);

        -- First reduction: product = lower + upper * 5
        upper5 := upper * to_unsigned(5, 3);
        sum1   := resize(lower, 134) + resize(upper5, 134);

        -- Second reduction: sum1 could be up to ~133 bits
        lower2  := sum1(129 downto 0);
        upper2  := sum1(133 downto 130);
        upper2x5 := upper2 * to_unsigned(5, 3);
        sum2    := resize(lower2, 131) + resize(upper2x5, 131);

        -- Final conditional subtract: if sum2 >= P, subtract P
        result := sum2;
        if result >= POLY_P then
            result := result - POLY_P;
        end if;

        val_out <= result(129 downto 0);
    end process;

end architecture rtl;
