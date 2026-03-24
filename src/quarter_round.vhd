-- ChaCha20 Quarter Round
-- Combinational: 4 modular adds + 4 XORs + 4 rotations (16,12,8,7)
-- RFC 7539 Section 2.1

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.chacha20_pkg.all;

entity quarter_round is
    port (
        a_in  : in  word32;
        b_in  : in  word32;
        c_in  : in  word32;
        d_in  : in  word32;
        a_out : out word32;
        b_out : out word32;
        c_out : out word32;
        d_out : out word32
    );
end entity quarter_round;

architecture rtl of quarter_round is
    signal a1, b1, c1, d1 : word32;
    signal a2, b2, c2, d2 : word32;
    signal a3, b3, c3, d3 : word32;
    signal a4, b4, c4, d4 : word32;
begin

    -- Step 1: a += b; d ^= a; d <<<= 16
    a1 <= a_in + b_in;
    d1 <= rotl(d_in xor a1, 16);
    b1 <= b_in;
    c1 <= c_in;

    -- Step 2: c += d; b ^= c; b <<<= 12
    c2 <= c1 + d1;
    b2 <= rotl(b1 xor c2, 12);
    a2 <= a1;
    d2 <= d1;

    -- Step 3: a += b; d ^= a; d <<<= 8
    a3 <= a2 + b2;
    d3 <= rotl(d2 xor a3, 8);
    b3 <= b2;
    c3 <= c2;

    -- Step 4: c += d; b ^= c; b <<<= 7
    c4 <= c3 + d3;
    b4 <= rotl(b3 xor c4, 7);

    a_out <= a3;
    b_out <= b4;
    c_out <= c4;
    d_out <= d3;

end architecture rtl;
