-- ChaCha20 Round Controller
-- FSM: IDLE -> ROUND_COL -> ROUND_DIAG (10 double rounds) -> FINAL_ADD -> DONE_STATE
-- P6 change: split double round into column half + diagonal half for 200 MHz pipelining
-- Latency: 22 clocks per block (1 load + 10 col + 10 diag + 1 final add)
-- Each ROUND_COL applies 4 column QRs; each ROUND_DIAG applies 4 diagonal QRs.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.chacha20_pkg.all;

entity round_controller is
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        start     : in  std_logic;
        state_in  : in  state_array;
        state_out : out state_array;
        done      : out std_logic
    );
end entity round_controller;

architecture rtl of round_controller is

    type fsm_state is (IDLE, ROUND_COL, ROUND_DIAG, FINAL_ADD, DONE_STATE);
    signal current_state : fsm_state := IDLE;

    signal working     : state_array;
    signal initial     : state_array;
    signal col_out     : state_array;   -- registered after column round
    signal col_result  : state_array;   -- combinational output of column_round
    signal diag_result : state_array;   -- combinational output of diagonal_round
    signal round_cnt   : unsigned(3 downto 0) := (others => '0');

begin

    -- Combinational column round (4 column QRs)
    col_inst: entity work.column_round
        port map (
            state_in  => working,
            state_out => col_result
        );

    -- Combinational diagonal round (4 diagonal QRs)
    diag_inst: entity work.diagonal_round
        port map (
            state_in  => col_out,
            state_out => diag_result
        );

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                current_state <= IDLE;
                done      <= '0';
                round_cnt <= (others => '0');
            else
                done <= '0';  -- default: 1-clock pulse

                case current_state is
                    when IDLE =>
                        if start = '1' then
                            working   <= state_in;
                            initial   <= state_in;
                            round_cnt <= (others => '0');
                            current_state <= ROUND_COL;
                        end if;

                    when ROUND_COL =>
                        -- Apply column quarter rounds (combinational from working)
                        -- Register the result into col_out
                        col_out       <= col_result;
                        current_state <= ROUND_DIAG;

                    when ROUND_DIAG =>
                        -- Apply diagonal quarter rounds (combinational from col_out)
                        -- Register result back into working
                        working   <= diag_result;
                        round_cnt <= round_cnt + 1;
                        if round_cnt = to_unsigned(9, 4) then
                            current_state <= FINAL_ADD;
                        else
                            current_state <= ROUND_COL;
                        end if;

                    when FINAL_ADD =>
                        -- Add initial state to working state (mod 2^32)
                        -- Use 'working' (after exactly 10 double rounds)
                        for i in 0 to 15 loop
                            state_out(i) <= working(i) + initial(i);
                        end loop;
                        current_state <= DONE_STATE;

                    when DONE_STATE =>
                        done <= '1';
                        current_state <= IDLE;
                end case;
            end if;
        end if;
    end process;

end architecture rtl;
