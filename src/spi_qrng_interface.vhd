-- SPI QRNG Interface
-- Reads 44 bytes via SPI Mode 0 (CPOL=0, CPHA=0): 32B key + 12B nonce
-- Pin-compatible outputs with matlab_uart_interface
-- VHDL-2008

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spi_qrng_interface is
    generic (
        CLK_FREQ    : positive := 200_000_000;
        SPI_CLK_DIV : positive := 4  -- CLK_FREQ / (2 * SPI_CLK_DIV) = SPI clock
    );
    port (
        clk        : in  std_logic;
        rst        : in  std_logic;
        -- SPI pins
        spi_sclk   : out std_logic;
        spi_mosi   : out std_logic;
        spi_miso   : in  std_logic;
        spi_cs_n   : out std_logic;
        -- Trigger
        start      : in  std_logic;
        -- Outputs (same as matlab_uart_interface)
        key_out    : out std_logic_vector(255 downto 0);
        nonce_out  : out std_logic_vector(95 downto 0);
        data_ready : out std_logic;
        busy       : out std_logic
    );
end entity spi_qrng_interface;

architecture rtl of spi_qrng_interface is

    type fsm_state is (IDLE, ASSERT_CS, SHIFT_BIT, NEXT_BYTE, DEASSERT_CS, DONE_STATE);
    signal state : fsm_state := IDLE;

    -- Clock divider for SCLK generation
    signal clk_div_cnt : unsigned(15 downto 0) := (others => '0');
    signal sclk_i      : std_logic := '0';
    signal sclk_rise   : std_logic := '0';
    signal sclk_fall   : std_logic := '0';

    -- Byte/bit counters
    signal byte_cnt : unsigned(5 downto 0) := (others => '0');  -- 0 to 43
    signal bit_cnt  : unsigned(2 downto 0) := (others => '0');  -- 0 to 7

    -- Shift register for incoming byte (MSB first, SPI convention)
    signal shift_in : std_logic_vector(7 downto 0) := (others => '0');

    -- Storage registers
    signal key_reg   : std_logic_vector(255 downto 0) := (others => '0');
    signal nonce_reg : std_logic_vector(95 downto 0)  := (others => '0');

    constant TOTAL_BYTES : unsigned(5 downto 0) := to_unsigned(44, 6);

begin

    -- MOSI always drives 0x00 (dummy bytes to clock data in from QRNG)
    spi_mosi <= '0';

    -- SCLK clock divider and edge detection
    process(clk)
    begin
        if rising_edge(clk) then
            sclk_rise <= '0';
            sclk_fall <= '0';

            if rst = '1' then
                clk_div_cnt <= (others => '0');
                sclk_i      <= '0';
            elsif state = SHIFT_BIT then
                if clk_div_cnt = to_unsigned(SPI_CLK_DIV - 1, 16) then
                    clk_div_cnt <= (others => '0');
                    sclk_i      <= not sclk_i;
                    if sclk_i = '0' then
                        sclk_rise <= '1';
                    else
                        sclk_fall <= '1';
                    end if;
                else
                    clk_div_cnt <= clk_div_cnt + 1;
                end if;
            else
                clk_div_cnt <= (others => '0');
                sclk_i      <= '0';
            end if;
        end if;
    end process;

    spi_sclk <= sclk_i;

    -- Main FSM
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state      <= IDLE;
                spi_cs_n   <= '1';
                data_ready <= '0';
                busy       <= '0';
                byte_cnt   <= (others => '0');
                bit_cnt    <= (others => '0');
                shift_in   <= (others => '0');
                key_reg    <= (others => '0');
                nonce_reg  <= (others => '0');
            else
                data_ready <= '0';

                case state is
                    when IDLE =>
                        spi_cs_n <= '1';
                        busy     <= '0';
                        if start = '1' then
                            busy     <= '1';
                            byte_cnt <= (others => '0');
                            bit_cnt  <= (others => '0');
                            shift_in <= (others => '0');
                            state    <= ASSERT_CS;
                        end if;

                    when ASSERT_CS =>
                        spi_cs_n <= '0';
                        -- Wait one SPI clock period for CS setup time
                        state <= SHIFT_BIT;

                    when SHIFT_BIT =>
                        -- SPI Mode 0: sample MISO on rising SCLK edge
                        if sclk_rise = '1' then
                            -- Shift in MISO bit (MSB first)
                            shift_in <= shift_in(6 downto 0) & spi_miso;

                            if bit_cnt = to_unsigned(7, 3) then
                                -- Full byte received
                                bit_cnt <= (others => '0');
                                state   <= NEXT_BYTE;
                            else
                                bit_cnt <= bit_cnt + 1;
                            end if;
                        end if;

                    when NEXT_BYTE =>
                        -- Store completed byte into appropriate register (little-endian)
                        if byte_cnt < to_unsigned(32, 6) then
                            -- Bytes 0-31 go to key_out
                            key_reg(to_integer(byte_cnt)*8 + 7 downto to_integer(byte_cnt)*8) <= shift_in;
                        else
                            -- Bytes 32-43 go to nonce_out
                            nonce_reg(to_integer(byte_cnt - 32)*8 + 7 downto to_integer(byte_cnt - 32)*8) <= shift_in;
                        end if;

                        if byte_cnt = TOTAL_BYTES - 1 then
                            state <= DEASSERT_CS;
                        else
                            byte_cnt <= byte_cnt + 1;
                            shift_in <= (others => '0');
                            state    <= SHIFT_BIT;
                        end if;

                    when DEASSERT_CS =>
                        spi_cs_n  <= '1';
                        key_out   <= key_reg;
                        nonce_out <= nonce_reg;
                        state     <= DONE_STATE;

                    when DONE_STATE =>
                        data_ready <= '1';
                        busy       <= '0';
                        state      <= IDLE;
                end case;
            end if;
        end if;
    end process;

end architecture rtl;
