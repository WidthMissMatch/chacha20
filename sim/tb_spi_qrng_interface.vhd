--------------------------------------------------------------------------------
-- tb_spi_qrng_interface.vhd
-- Testbench for SPI QRNG interface
--
-- Test: Drive MISO with bytes 0x00, 0x01, ..., 0x2B (44 bytes, MSB first per byte)
-- Expected outputs:
--   key_out   = 0x1F1E1D1C1B1A191817161514131211100F0E0D0C0B0A09080706050403020100
--   nonce_out = 0x2B2A29282726252423222120
--
-- VHDL-2008
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_spi_qrng_interface is
end entity tb_spi_qrng_interface;

architecture sim of tb_spi_qrng_interface is

    constant CLK_PERIOD : time := 10 ns;   -- 100 MHz simulation clock

    signal clk        : std_logic := '0';
    signal rst        : std_logic := '1';
    signal spi_sclk   : std_logic;
    signal spi_mosi   : std_logic;
    signal spi_miso   : std_logic := '0';
    signal spi_cs_n   : std_logic;
    signal start      : std_logic := '0';
    signal key_out    : std_logic_vector(255 downto 0);
    signal nonce_out  : std_logic_vector(95 downto 0);
    signal data_ready : std_logic;
    signal busy       : std_logic;

    -- Expected values: byte k = k (0x00..0x2B), stored little-endian
    constant EXP_KEY : std_logic_vector(255 downto 0) :=
        x"1F1E1D1C1B1A191817161514131211100F0E0D0C0B0A09080706050403020100";
    constant EXP_NONCE : std_logic_vector(95 downto 0) :=
        x"2B2A29282726252423222120";

    -- MISO driver state
    signal miso_bit_cnt : integer := 0;
    signal sclk_d       : std_logic := '0';

begin

    clk <= not clk after CLK_PERIOD / 2;

    -- DUT
    dut: entity work.spi_qrng_interface
        generic map (
            CLK_FREQ    => 100_000_000,
            SPI_CLK_DIV => 4
        )
        port map (
            clk        => clk,
            rst        => rst,
            spi_sclk   => spi_sclk,
            spi_mosi   => spi_mosi,
            spi_miso   => spi_miso,
            spi_cs_n   => spi_cs_n,
            start      => start,
            key_out    => key_out,
            nonce_out  => nonce_out,
            data_ready => data_ready,
            busy       => busy
        );

    -- -------------------------------------------------------------------------
    -- MISO driver: advance bit counter on SCLK falling edges.
    -- Reset counter when CS deasserts (idle / end of transfer).
    -- -------------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            sclk_d <= spi_sclk;
            if spi_cs_n = '1' then
                -- CS deasserted: reset for next transfer
                miso_bit_cnt <= 0;
            elsif sclk_d = '1' and spi_sclk = '0' then
                -- SCLK falling edge: master has sampled, advance to next bit
                if miso_bit_cnt < 351 then
                    miso_bit_cnt <= miso_bit_cnt + 1;
                end if;
            end if;
        end if;
    end process;

    -- Combinatorial: drive MISO based on current bit index.
    -- Byte k = k (value 0..43), transmitted MSB first.
    process(miso_bit_cnt, spi_cs_n)
        variable byte_idx : integer;
        variable bit_pos  : integer;
        variable bval     : std_logic_vector(7 downto 0);
    begin
        spi_miso <= '0';
        if spi_cs_n = '0' then
            byte_idx := miso_bit_cnt / 8;
            bit_pos  := 7 - (miso_bit_cnt mod 8);  -- MSB first
            if byte_idx <= 43 then
                bval     := std_logic_vector(to_unsigned(byte_idx, 8));
                spi_miso <= bval(bit_pos);
            end if;
        end if;
    end process;

    -- -------------------------------------------------------------------------
    -- Main stimulus and checker
    -- -------------------------------------------------------------------------
    process
    begin
        -- Reset
        rst   <= '1';
        start <= '0';
        wait for 100 ns;
        rst <= '0';
        wait for 20 ns;

        -- Trigger SPI transfer
        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';

        -- Wait for data_ready pulse
        wait until data_ready = '1';
        wait for CLK_PERIOD;

        -- Check key_out
        assert key_out = EXP_KEY
            report "FAILED: key_out = " & to_hstring(key_out) &
                   " expected " & to_hstring(EXP_KEY)
            severity failure;

        -- Check nonce_out
        assert nonce_out = EXP_NONCE
            report "FAILED: nonce_out = " & to_hstring(nonce_out) &
                   " expected " & to_hstring(EXP_NONCE)
            severity failure;

        report "tb_spi_qrng_interface: PASSED" severity note;
        wait;
    end process;

end architecture sim;
