-- Testbench: ChaCha20 Round Controller
-- RFC 7539 Appendix A.1 full 20-round test vector

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.chacha20_pkg.all;

entity tb_round_controller is
end entity tb_round_controller;

architecture sim of tb_round_controller is
    constant CLK_PERIOD : time := 10 ns;

    signal clk       : std_logic := '0';
    signal rst       : std_logic := '1';
    signal start     : std_logic := '0';
    signal state_in  : state_array;
    signal state_out : state_array;
    signal done      : std_logic;
    signal test_pass : boolean := true;

    -- RFC 7539 A.1 expected output (after 20 rounds + final add)
    type expected_array is array(0 to 15) of std_logic_vector(31 downto 0);
    constant expected : expected_array := (
        x"e4e7f110", x"15593bd1", x"1fdd0f50", x"c47120a3",
        x"c7f4d1c7", x"0368c033", x"9aaa2204", x"4e6cd4c3",
        x"466482d2", x"09aa9f07", x"05d7c214", x"a2028bd9",
        x"d19c12b5", x"b94e16de", x"e883d0cb", x"4e3c50a2"
    );

begin

    clk <= not clk after CLK_PERIOD / 2;

    uut: entity work.round_controller
        port map (
            clk       => clk,
            rst       => rst,
            start     => start,
            state_in  => state_in,
            state_out => state_out,
            done      => done
        );

    process
    begin
        report "=== Round Controller Testbench ===" severity note;

        -- Setup initial state (RFC 7539 A.1)
        state_in(0)  <= x"61707865";
        state_in(1)  <= x"3320646e";
        state_in(2)  <= x"79622d32";
        state_in(3)  <= x"6b206574";
        state_in(4)  <= x"03020100";
        state_in(5)  <= x"07060504";
        state_in(6)  <= x"0b0a0908";
        state_in(7)  <= x"0f0e0d0c";
        state_in(8)  <= x"13121110";
        state_in(9)  <= x"17161514";
        state_in(10) <= x"1b1a1918";
        state_in(11) <= x"1f1e1d1c";
        state_in(12) <= x"00000001";
        state_in(13) <= x"09000000";
        state_in(14) <= x"4a000000";
        state_in(15) <= x"00000000";

        -- Reset
        rst <= '1';
        wait for CLK_PERIOD * 2;
        rst <= '0';
        wait for CLK_PERIOD;

        -- Start
        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';

        -- Wait for done
        wait until done = '1';
        wait for 1 ns;  -- Let signals settle

        -- Verify output
        for i in 0 to 15 loop
            if std_logic_vector(state_out(i)) /= expected(i) then
                report "FAIL: word " & integer'image(i) &
                       " = " & to_hstring(state_out(i)) &
                       " expected " & to_hstring(unsigned(expected(i)))
                    severity error;
                test_pass <= false;
            end if;
        end loop;

        wait for CLK_PERIOD;

        if test_pass then
            report "=== ALL ROUND CONTROLLER TESTS PASSED ===" severity note;
        else
            report "=== ROUND CONTROLLER TESTS FAILED ===" severity error;
        end if;

        wait;
    end process;

end architecture sim;
