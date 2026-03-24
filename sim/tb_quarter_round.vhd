-- Testbench: ChaCha20 Quarter Round
-- RFC 7539 Section 2.1.1 test vector

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.chacha20_pkg.all;

entity tb_quarter_round is
end entity tb_quarter_round;

architecture sim of tb_quarter_round is
    signal a_in, b_in, c_in, d_in   : word32;
    signal a_out, b_out, c_out, d_out : word32;
    signal test_pass : boolean := true;
begin

    uut: entity work.quarter_round
        port map (
            a_in => a_in, b_in => b_in, c_in => c_in, d_in => d_in,
            a_out => a_out, b_out => b_out, c_out => c_out, d_out => d_out
        );

    process
    begin
        report "=== Quarter Round Testbench ===" severity note;

        -- RFC 7539 Section 2.1.1 test vector
        a_in <= x"11111111";
        b_in <= x"01020304";
        c_in <= x"9b8d6f43";
        d_in <= x"01234567";
        wait for 10 ns;

        if a_out /= x"ea2a92f4" then
            report "FAIL: a_out = " & to_hstring(a_out) & " expected ea2a92f4" severity error;
            test_pass <= false;
        end if;
        if b_out /= x"cb1cf8ce" then
            report "FAIL: b_out = " & to_hstring(b_out) & " expected cb1cf8ce" severity error;
            test_pass <= false;
        end if;
        if c_out /= x"4581472e" then
            report "FAIL: c_out = " & to_hstring(c_out) & " expected 4581472e" severity error;
            test_pass <= false;
        end if;
        if d_out /= x"5881c4bb" then
            report "FAIL: d_out = " & to_hstring(d_out) & " expected 5881c4bb" severity error;
            test_pass <= false;
        end if;

        -- Additional test: RFC 7539 Section 2.2.1 (from full state QR on indices 2,7,8,13)
        -- Input state words at those indices: 0x7b, 0, 0, 0 ... let's use a simpler second test
        -- Test with all zeros
        a_in <= x"00000000";
        b_in <= x"00000000";
        c_in <= x"00000000";
        d_in <= x"00000000";
        wait for 10 ns;

        if a_out /= x"00000000" then
            report "FAIL: zero test a_out = " & to_hstring(a_out) & " expected 00000000" severity error;
            test_pass <= false;
        end if;

        wait for 10 ns;

        if test_pass then
            report "=== ALL QUARTER ROUND TESTS PASSED ===" severity note;
        else
            report "=== QUARTER ROUND TESTS FAILED ===" severity error;
        end if;

        wait;
    end process;

end architecture sim;
