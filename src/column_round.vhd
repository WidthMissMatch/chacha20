-- ChaCha20 Column Round
-- Four parallel column quarter rounds (first half of a double round)
-- RFC 7539 Section 2.3: QR(0,4,8,12), QR(1,5,9,13), QR(2,6,10,14), QR(3,7,11,15)
-- Combinational: no clock port

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.chacha20_pkg.all;

entity column_round is
    port (
        state_in  : in  state_array;
        state_out : out state_array
    );
end entity column_round;

architecture rtl of column_round is
begin

    -- QR(0, 4, 8, 12)
    col0: entity work.quarter_round
        port map (
            a_in => state_in(0),  b_in => state_in(4),
            c_in => state_in(8),  d_in => state_in(12),
            a_out => state_out(0),  b_out => state_out(4),
            c_out => state_out(8),  d_out => state_out(12)
        );

    -- QR(1, 5, 9, 13)
    col1: entity work.quarter_round
        port map (
            a_in => state_in(1),  b_in => state_in(5),
            c_in => state_in(9),  d_in => state_in(13),
            a_out => state_out(1),  b_out => state_out(5),
            c_out => state_out(9),  d_out => state_out(13)
        );

    -- QR(2, 6, 10, 14)
    col2: entity work.quarter_round
        port map (
            a_in => state_in(2),  b_in => state_in(6),
            c_in => state_in(10), d_in => state_in(14),
            a_out => state_out(2),  b_out => state_out(6),
            c_out => state_out(10), d_out => state_out(14)
        );

    -- QR(3, 7, 11, 15)
    col3: entity work.quarter_round
        port map (
            a_in => state_in(3),  b_in => state_in(7),
            c_in => state_in(11), d_in => state_in(15),
            a_out => state_out(3),  b_out => state_out(7),
            c_out => state_out(11), d_out => state_out(15)
        );

end architecture rtl;
