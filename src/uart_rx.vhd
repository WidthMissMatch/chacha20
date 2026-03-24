-- UART Receiver
-- 8N1 format: 1 start bit, 8 data bits (LSB first), 1 stop bit
-- 16x oversampling with metastability synchronizer on rx_in

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_rx is
    generic (
        CLK_FREQ  : positive := 200_000_000;
        BAUD_RATE : positive := 115200
    );
    port (
        clk      : in  std_logic;
        rst      : in  std_logic;
        rx_in    : in  std_logic;
        data_out : out std_logic_vector(7 downto 0);
        rx_valid : out std_logic;
        rx_error : out std_logic
    );
end entity uart_rx;

architecture rtl of uart_rx is

    constant OVERSAMPLE_DIV : positive := CLK_FREQ / (BAUD_RATE * 16);

    type fsm_state is (IDLE, WAIT_IDLE, START_DETECT, SAMPLE_BITS, STOP_CHECK);
    signal state : fsm_state := IDLE;

    -- Metastability synchronizer
    signal rx_sync1  : std_logic := '1';
    signal rx_sync2  : std_logic := '1';

    signal os_cnt    : unsigned(15 downto 0) := (others => '0');  -- Oversample tick counter
    signal os_tick   : std_logic;                                  -- Pulse every oversample period
    signal sample_cnt : unsigned(3 downto 0) := (others => '0'); -- 0-15 within bit
    signal bit_idx   : unsigned(2 downto 0)  := (others => '0');
    signal shift_reg : std_logic_vector(7 downto 0) := (others => '0');

begin

    -- 2-FF synchronizer
    process(clk)
    begin
        if rising_edge(clk) then
            rx_sync1 <= rx_in;
            rx_sync2 <= rx_sync1;
        end if;
    end process;

    -- Oversample tick generator
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' or state = IDLE or state = WAIT_IDLE then
                os_cnt  <= (others => '0');
                os_tick <= '0';
            elsif os_cnt = to_unsigned(OVERSAMPLE_DIV - 1, 16) then
                os_cnt  <= (others => '0');
                os_tick <= '1';
            else
                os_cnt  <= os_cnt + 1;
                os_tick <= '0';
            end if;
        end if;
    end process;

    -- Main FSM
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state      <= IDLE;
                rx_valid   <= '0';
                rx_error   <= '0';
                data_out   <= (others => '0');
                sample_cnt <= (others => '0');
                bit_idx    <= (others => '0');
                shift_reg  <= (others => '0');
            else
                rx_valid <= '0';
                rx_error <= '0';

                case state is
                    when IDLE =>
                        if rx_sync2 = '0' then
                            -- Falling edge detected (start bit)
                            sample_cnt <= (others => '0');
                            state      <= START_DETECT;
                        end if;

                    when WAIT_IDLE =>
                        -- Wait for line to return to idle (high) after error
                        if rx_sync2 = '1' then
                            state <= IDLE;
                        end if;

                    when START_DETECT =>
                        -- Wait until mid-start-bit (8 oversample ticks)
                        if os_tick = '1' then
                            if sample_cnt = to_unsigned(7, 4) then
                                if rx_sync2 = '0' then
                                    -- Valid start bit at center
                                    sample_cnt <= (others => '0');
                                    bit_idx    <= (others => '0');
                                    state      <= SAMPLE_BITS;
                                else
                                    -- Glitch, not a real start bit
                                    state <= IDLE;
                                end if;
                            else
                                sample_cnt <= sample_cnt + 1;
                            end if;
                        end if;

                    when SAMPLE_BITS =>
                        -- Wait 16 oversample ticks (one bit period) then sample
                        if os_tick = '1' then
                            if sample_cnt = to_unsigned(15, 4) then
                                sample_cnt <= (others => '0');
                                -- Sample at bit center: shift in LSB first
                                shift_reg <= rx_sync2 & shift_reg(7 downto 1);
                                if bit_idx = to_unsigned(7, 3) then
                                    state <= STOP_CHECK;
                                else
                                    bit_idx <= bit_idx + 1;
                                end if;
                            else
                                sample_cnt <= sample_cnt + 1;
                            end if;
                        end if;

                    when STOP_CHECK =>
                        -- Wait 16 oversample ticks for stop bit
                        if os_tick = '1' then
                            if sample_cnt = to_unsigned(15, 4) then
                                sample_cnt <= (others => '0');
                                data_out   <= shift_reg;
                                if rx_sync2 = '1' then
                                    rx_valid <= '1';  -- Good stop bit
                                    state <= IDLE;
                                else
                                    rx_error <= '1';  -- Bad stop bit (framing error)
                                    state <= WAIT_IDLE;  -- Wait for line idle
                                end if;
                            else
                                sample_cnt <= sample_cnt + 1;
                            end if;
                        end if;
                end case;
            end if;
        end if;
    end process;

end architecture rtl;
