-- UART Transmitter
-- 8N1 format: 1 start bit, 8 data bits (LSB first), 1 stop bit
-- tx_out idles high, tx_busy asserted outside IDLE
-- Uses 10-bit frame shift register: [stop][d7..d0][start]

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_tx is
    generic (
        CLK_FREQ  : positive := 200_000_000;
        BAUD_RATE : positive := 115200
    );
    port (
        clk      : in  std_logic;
        rst      : in  std_logic;
        data_in  : in  std_logic_vector(7 downto 0);
        tx_start : in  std_logic;
        tx_busy  : out std_logic;
        tx_out   : out std_logic
    );
end entity uart_tx;

architecture rtl of uart_tx is

    constant BAUD_DIV : positive := CLK_FREQ / BAUD_RATE;

    type fsm_state is (IDLE, TRANSMITTING);
    signal state : fsm_state := IDLE;

    signal baud_cnt  : unsigned(15 downto 0) := (others => '0');
    signal bit_cnt   : unsigned(3 downto 0)  := (others => '0');  -- 0-9
    signal frame_reg : std_logic_vector(9 downto 0) := (others => '1');

begin

    tx_out <= frame_reg(0);

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state     <= IDLE;
                tx_busy   <= '0';
                baud_cnt  <= (others => '0');
                bit_cnt   <= (others => '0');
                frame_reg <= (others => '1');
            else
                case state is
                    when IDLE =>
                        tx_busy <= '0';
                        if tx_start = '1' then
                            -- Build frame: [stop=1][d7..d0][start=0]
                            frame_reg <= '1' & data_in & '0';
                            tx_busy   <= '1';
                            baud_cnt  <= (others => '0');
                            bit_cnt   <= (others => '0');
                            state     <= TRANSMITTING;
                        end if;

                    when TRANSMITTING =>
                        tx_busy <= '1';
                        if baud_cnt = to_unsigned(BAUD_DIV - 1, 16) then
                            baud_cnt <= (others => '0');
                            if bit_cnt = to_unsigned(9, 4) then
                                state <= IDLE;
                            else
                                frame_reg <= '1' & frame_reg(9 downto 1);
                                bit_cnt   <= bit_cnt + 1;
                            end if;
                        else
                            baud_cnt <= baud_cnt + 1;
                        end if;
                end case;
            end if;
        end if;
    end process;

end architecture rtl;
