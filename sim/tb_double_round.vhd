-- Testbench: ChaCha20 Double Round
-- Uses RFC 7539 Appendix A.1 initial state, verifies after 1 double round

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.chacha20_pkg.all;

entity tb_double_round is
end entity tb_double_round;

architecture sim of tb_double_round is
    signal state_in  : state_array;
    signal state_out : state_array;
    signal test_pass : boolean := true;

    -- Expected state after 1 double round of the RFC A.1 initial state
    -- Computed from Python reference implementation
    type expected_array is array(0 to 15) of std_logic_vector(31 downto 0);
    constant expected : expected_array := (
        x"cd52e917", x"85ab03b4", x"b3457395", x"f96de7dd",
        x"c4b7cd22", x"5c2e187a", x"c95eb461", x"316c801a",
        x"7bf7d740", x"7eddd644", x"f1a1bdf5", x"761246ca",
        x"6b0d58a3", x"6798471a", x"d737f167", x"f173888d"
    );

begin

    uut: entity work.double_round
        port map (
            state_in  => state_in,
            state_out => state_out
        );

    process
    begin
        report "=== Double Round Testbench ===" severity note;

        -- RFC 7539 A.1 initial state:
        -- Key: 00:01:02:...:1f, Nonce: 000000090000004a00000000, Counter: 1
        state_in(0)  <= x"61707865";  -- C0
        state_in(1)  <= x"3320646e";  -- C1
        state_in(2)  <= x"79622d32";  -- C2
        state_in(3)  <= x"6b206574";  -- C3
        state_in(4)  <= x"03020100";  -- key word 0
        state_in(5)  <= x"07060504";  -- key word 1
        state_in(6)  <= x"0b0a0908";  -- key word 2
        state_in(7)  <= x"0f0e0d0c";  -- key word 3
        state_in(8)  <= x"13121110";  -- key word 4
        state_in(9)  <= x"17161514";  -- key word 5
        state_in(10) <= x"1b1a1918";  -- key word 6
        state_in(11) <= x"1f1e1d1c";  -- key word 7
        state_in(12) <= x"00000001";  -- counter = 1
        state_in(13) <= x"09000000";  -- nonce word 0
        state_in(14) <= x"4a000000";  -- nonce word 1
        state_in(15) <= x"00000000";  -- nonce word 2

        wait for 10 ns;

        for i in 0 to 15 loop
            if std_logic_vector(state_out(i)) /= expected(i) then
                report "FAIL: word " & integer'image(i) &
                       " = " & to_hstring(state_out(i)) &
                       " expected " & to_hstring(unsigned(expected(i)))
                    severity error;
                test_pass <= false;
            end if;
        end loop;

        wait for 10 ns;

        if test_pass then
            report "=== ALL DOUBLE ROUND TESTS PASSED ===" severity note;
        else
            report "=== DOUBLE ROUND TESTS FAILED ===" severity error;
        end if;

        wait;
    end process;

end architecture sim;
