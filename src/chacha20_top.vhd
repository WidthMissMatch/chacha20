-- ChaCha20-Poly1305 System Top-Level
-- MATLAB UART → Key/Nonce Register → ChaCha20 Core → Poly1305 MAC → Output Buffer → UART TX
-- Active-low reset (rst_n), all submodules use active-high rst
-- Also integrates: ECDH key exchange (X25519) and SPI QRNG interface

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity chacha20_top is
    generic (
        CLK_FREQ    : positive := 200_000_000;
        BAUD_RATE   : positive := 115200;
        SPI_CLK_DIV : positive := 4
    );
    port (
        clk        : in  std_logic;
        rst_n      : in  std_logic;
        -- UART
        uart_rx    : in  std_logic;
        uart_tx    : out std_logic;
        -- NACK TX from matlab_uart_interface (checksum error → 0xFF)
        uart_tx_nack : out std_logic;
        -- SPI QRNG interface (PMOD J87)
        spi_sclk   : out std_logic;
        spi_mosi   : out std_logic;
        spi_miso   : in  std_logic;
        spi_cs_n   : out std_logic;
        -- Status LEDs
        led_status : out std_logic_vector(3 downto 0)
    );
end entity chacha20_top;

architecture rtl of chacha20_top is

    -- Internal active-high reset
    signal rst : std_logic;

    -- MATLAB interface signals
    signal mi_key       : std_logic_vector(255 downto 0);
    signal mi_nonce     : std_logic_vector(95 downto 0);
    signal mi_plaintext : std_logic_vector(511 downto 0);
    signal mi_ready     : std_logic;
    signal mi_chk_err   : std_logic;
    signal mi_ecdh_ready : std_logic;
    signal mi_priv_key   : std_logic_vector(255 downto 0);
    signal mi_peer_pub   : std_logic_vector(255 downto 0);

    -- Key/nonce register signals
    signal knr_key        : std_logic_vector(255 downto 0);
    signal knr_nonce      : std_logic_vector(95 downto 0);
    signal knr_counter    : std_logic_vector(31 downto 0);
    signal knr_plaintext  : std_logic_vector(511 downto 0);
    signal knr_start      : std_logic;
    signal knr_poly_key   : std_logic_vector(255 downto 0);
    signal knr_poly_valid : std_logic;
    signal knr_cipher     : std_logic_vector(511 downto 0);
    signal knr_cipher_v   : std_logic;
    signal knr_busy       : std_logic;

    -- ChaCha20 core signals
    signal core_done      : std_logic;
    signal core_ciphertext : std_logic_vector(511 downto 0);
    signal core_keystream : std_logic_vector(511 downto 0);

    -- Poly1305 signals
    signal poly_msg_block : std_logic_vector(127 downto 0);
    signal poly_msg_valid : std_logic;
    signal poly_msg_last  : std_logic;
    signal poly_byte_cnt  : std_logic_vector(4 downto 0);
    signal poly_tag       : std_logic_vector(127 downto 0);
    signal poly_tag_valid : std_logic;
    signal poly_ready     : std_logic;

    -- Output buffer signals
    signal obuf_wr_data   : std_logic_vector(511 downto 0);
    signal obuf_wr_en     : std_logic;
    signal obuf_rd_data   : std_logic_vector(7 downto 0);
    signal obuf_rd_en     : std_logic;
    signal obuf_rd_valid  : std_logic;
    signal obuf_full      : std_logic;
    signal obuf_empty     : std_logic;

    -- UART TX signals
    signal tx_data   : std_logic_vector(7 downto 0);
    signal tx_start  : std_logic;
    signal tx_busy   : std_logic;

    -- ECDH signals
    signal ecdh_start  : std_logic;
    signal ecdh_done   : std_logic;
    signal ecdh_ss     : unsigned(254 downto 0);
    signal ecdh_pk     : unsigned(254 downto 0);

    -- ECDH result shift register (512 bits: 32B shared_secret || 32B public_key)
    signal ecdh_result_reg : std_logic_vector(511 downto 0) := (others => '0');
    signal ecdh_tx_cnt     : unsigned(6 downto 0) := (others => '0');

    -- SPI QRNG signals (connected but start hardwired to '0' for now)
    signal qrng_start : std_logic;

    -- Top-level FSM
    type top_state is (IDLE, FEED_POLY_BLOCK, WAIT_POLY_BUSY, WAIT_POLY_READY,
                        WAIT_TAG, WRITE_CIPHER_TO_BUF,
                        TX_CIPHER_REQ, TX_CIPHER_WAIT, TX_CIPHER_SEND,
                        TX_TAG_LOAD, TX_TAG_BYTES,
                        ECDH_TRIGGER, WAIT_ECDH, TX_ECDH_RESULT,
                        DONE_STATE);
    signal tstate : top_state := IDLE;

    -- Poly1305 block feeding
    signal poly_blk_idx : unsigned(1 downto 0) := (others => '0');  -- 0-3
    signal ciphertext_reg : std_logic_vector(511 downto 0) := (others => '0');

    -- Tag output shift register
    signal tag_reg     : std_logic_vector(127 downto 0) := (others => '0');
    signal tag_byte_cnt : unsigned(4 downto 0) := (others => '0');  -- 0-16

    -- UART TX output sequencing
    signal cipher_byte_cnt : unsigned(6 downto 0) := (others => '0');  -- 0-64

    -- Tag capture (tag_valid may pulse while we're still sending ciphertext)
    signal tag_captured : std_logic := '0';

    -- LED heartbeat
    signal heartbeat_cnt : unsigned(27 downto 0) := (others => '0');
    signal led_rx_act    : std_logic := '0';
    signal led_encrypt   : std_logic := '0';
    signal led_poly      : std_logic := '0';

begin

    rst <= not rst_n;

    -- SPI QRNG start not driven in this implementation (QRNG inactive)
    qrng_start <= '0';

    -- ========================================================================
    -- Submodule instantiations
    -- ========================================================================

    -- MATLAB UART interface (receives 110-byte encrypt packets and 66-byte ECDH packets)
    matlab_if_inst: entity work.matlab_uart_interface
        generic map (
            CLK_FREQ  => CLK_FREQ,
            BAUD_RATE => BAUD_RATE
        )
        port map (
            clk           => clk,
            rst           => rst,
            uart_rx_pin   => uart_rx,
            key_out       => mi_key,
            nonce_out     => mi_nonce,
            plaintext_out => mi_plaintext,
            data_ready    => mi_ready,
            checksum_err  => mi_chk_err,
            ecdh_ready    => mi_ecdh_ready,
            priv_key_out  => mi_priv_key,
            peer_pub_out  => mi_peer_pub,
            uart_tx_pin   => uart_tx_nack
        );

    -- Key/nonce register (sequences poly key gen + encryption)
    knr_inst: entity work.key_nonce_register
        port map (
            clk            => clk,
            rst            => rst,
            key_in         => mi_key,
            nonce_in       => mi_nonce,
            plaintext_in   => mi_plaintext,
            data_valid     => mi_ready,
            key_out        => knr_key,
            nonce_out      => knr_nonce,
            counter_out    => knr_counter,
            plaintext_out  => knr_plaintext,
            start_core     => knr_start,
            core_done      => core_done,
            keystream_in   => core_keystream,
            poly_key_out   => knr_poly_key,
            poly_key_valid => knr_poly_valid,
            cipher_data    => knr_cipher,
            cipher_valid   => knr_cipher_v,
            busy           => knr_busy
        );

    -- ChaCha20 encryption core
    core_inst: entity work.chacha20_core
        port map (
            clk           => clk,
            rst           => rst,
            start         => knr_start,
            done          => core_done,
            key           => knr_key,
            nonce         => knr_nonce,
            counter_in    => knr_counter,
            plaintext     => knr_plaintext,
            ciphertext    => core_ciphertext,
            keystream_out => core_keystream
        );

    -- Poly1305 MAC
    poly_inst: entity work.poly1305_mac
        port map (
            clk        => clk,
            rst        => rst,
            poly_key   => knr_poly_key,
            msg_block  => poly_msg_block,
            msg_valid  => poly_msg_valid,
            msg_last   => poly_msg_last,
            byte_count => poly_byte_cnt,
            tag_out    => poly_tag,
            tag_valid  => poly_tag_valid,
            ready      => poly_ready
        );

    -- Output buffer (512→8 bit width conversion)
    obuf_inst: entity work.output_buffer
        port map (
            clk         => clk,
            rst         => rst,
            wr_data     => obuf_wr_data,
            wr_en       => obuf_wr_en,
            rd_data     => obuf_rd_data,
            rd_en       => obuf_rd_en,
            rd_valid    => obuf_rd_valid,
            full        => obuf_full,
            empty       => obuf_empty,
            almost_full => open
        );

    -- UART transmitter
    uart_tx_inst: entity work.uart_tx
        generic map (
            CLK_FREQ  => CLK_FREQ,
            BAUD_RATE => BAUD_RATE
        )
        port map (
            clk      => clk,
            rst      => rst,
            data_in  => tx_data,
            tx_start => tx_start,
            tx_busy  => tx_busy,
            tx_out   => uart_tx
        );

    -- ECDH key exchange (X25519 Montgomery ladder, RFC 7748)
    ecdh_inst: entity work.ecdh_key_exchange
        port map (
            clk             => clk,
            rst             => rst,
            private_key     => unsigned(mi_priv_key(254 downto 0)),
            peer_public_key => unsigned(mi_peer_pub(254 downto 0)),
            start           => ecdh_start,
            shared_secret   => ecdh_ss,
            public_key_out  => ecdh_pk,
            done            => ecdh_done
        );

    -- SPI QRNG interface (instantiated for synthesis; start driven '0' until enabled)
    qrng_inst: entity work.spi_qrng_interface
        generic map (
            CLK_FREQ    => CLK_FREQ,
            SPI_CLK_DIV => SPI_CLK_DIV
        )
        port map (
            clk        => clk,
            rst        => rst,
            spi_sclk   => spi_sclk,
            spi_mosi   => spi_mosi,
            spi_miso   => spi_miso,
            spi_cs_n   => spi_cs_n,
            start      => qrng_start,
            key_out    => open,
            nonce_out  => open,
            data_ready => open,
            busy       => open
        );

    -- ========================================================================
    -- Top-level FSM: Poly1305 feeding + output sequencing + ECDH
    -- ========================================================================
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                tstate         <= IDLE;
                poly_msg_valid <= '0';
                poly_msg_last  <= '0';
                poly_msg_block <= (others => '0');
                poly_byte_cnt  <= (others => '0');
                poly_blk_idx   <= (others => '0');
                obuf_wr_en     <= '0';
                obuf_wr_data   <= (others => '0');
                obuf_rd_en     <= '0';
                tx_start       <= '0';
                tx_data        <= (others => '0');
                ciphertext_reg <= (others => '0');
                tag_reg        <= (others => '0');
                tag_byte_cnt   <= (others => '0');
                cipher_byte_cnt <= (others => '0');
                tag_captured   <= '0';
                ecdh_start     <= '0';
                ecdh_result_reg <= (others => '0');
                ecdh_tx_cnt    <= (others => '0');
                led_encrypt    <= '0';
                led_poly       <= '0';
            else
                -- Capture Poly1305 tag whenever it fires (may happen during cipher output)
                if poly_tag_valid = '1' then
                    tag_reg      <= poly_tag;
                    tag_captured <= '1';
                end if;

                -- Default: deassert one-cycle pulses
                poly_msg_valid <= '0';
                poly_msg_last  <= '0';
                obuf_wr_en     <= '0';
                obuf_rd_en     <= '0';
                tx_start       <= '0';
                ecdh_start     <= '0';

                case tstate is
                    when IDLE =>
                        led_encrypt <= '0';
                        led_poly    <= '0';
                        if knr_cipher_v = '1' then
                            -- Encrypt path: ciphertext ready
                            ciphertext_reg <= core_ciphertext;
                            led_encrypt    <= '1';
                            poly_blk_idx   <= (others => '0');
                            tag_captured   <= '0';
                            tstate         <= FEED_POLY_BLOCK;
                        elsif mi_ecdh_ready = '1' then
                            -- ECDH path: private key + peer public key received
                            tstate <= ECDH_TRIGGER;
                        end if;

                    -- --------------------------------------------------------
                    -- Encrypt path: Poly1305 feeding
                    -- --------------------------------------------------------
                    when FEED_POLY_BLOCK =>
                        led_poly <= '1';
                        case to_integer(poly_blk_idx) is
                            when 0 => poly_msg_block <= ciphertext_reg(127 downto 0);
                            when 1 => poly_msg_block <= ciphertext_reg(255 downto 128);
                            when 2 => poly_msg_block <= ciphertext_reg(383 downto 256);
                            when 3 => poly_msg_block <= ciphertext_reg(511 downto 384);
                            when others => null;
                        end case;
                        poly_byte_cnt  <= "10000";  -- 16 bytes
                        poly_msg_valid <= '1';
                        if poly_blk_idx = to_unsigned(3, 2) then
                            poly_msg_last <= '1';
                        else
                            poly_msg_last <= '0';
                        end if;
                        tstate <= WAIT_POLY_BUSY;

                    when WAIT_POLY_BUSY =>
                        if poly_ready = '0' then
                            if poly_blk_idx = to_unsigned(3, 2) then
                                tstate <= WRITE_CIPHER_TO_BUF;
                            else
                                tstate <= WAIT_POLY_READY;
                            end if;
                        end if;

                    when WAIT_POLY_READY =>
                        if poly_ready = '1' then
                            poly_blk_idx <= poly_blk_idx + 1;
                            tstate       <= FEED_POLY_BLOCK;
                        end if;

                    when WRITE_CIPHER_TO_BUF =>
                        obuf_wr_data <= ciphertext_reg;
                        obuf_wr_en   <= '1';
                        cipher_byte_cnt <= (others => '0');
                        tstate       <= TX_CIPHER_REQ;

                    when TX_CIPHER_REQ =>
                        if cipher_byte_cnt < to_unsigned(64, 7) then
                            obuf_rd_en <= '1';
                            tstate     <= TX_CIPHER_WAIT;
                        else
                            tstate <= WAIT_TAG;
                        end if;

                    when TX_CIPHER_WAIT =>
                        if obuf_rd_valid = '1' then
                            tx_data  <= obuf_rd_data;
                            tx_start <= '1';
                            cipher_byte_cnt <= cipher_byte_cnt + 1;
                            tstate   <= TX_CIPHER_SEND;
                        end if;

                    when TX_CIPHER_SEND =>
                        if tx_busy = '0' and tx_start = '0' then
                            tstate <= TX_CIPHER_REQ;
                        end if;

                    when WAIT_TAG =>
                        if tag_captured = '1' then
                            tag_byte_cnt <= (others => '0');
                            tstate       <= TX_TAG_LOAD;
                        end if;

                    when TX_TAG_LOAD =>
                        led_poly <= '0';
                        tstate   <= TX_TAG_BYTES;

                    when TX_TAG_BYTES =>
                        if tx_busy = '0' and tx_start = '0' then
                            if tag_byte_cnt < to_unsigned(16, 5) then
                                tx_data      <= tag_reg(7 downto 0);
                                tx_start     <= '1';
                                tag_reg      <= x"00" & tag_reg(127 downto 8);
                                tag_byte_cnt <= tag_byte_cnt + 1;
                            else
                                tstate <= DONE_STATE;
                            end if;
                        end if;

                    -- --------------------------------------------------------
                    -- ECDH path: X25519 scalar multiplication
                    -- --------------------------------------------------------
                    when ECDH_TRIGGER =>
                        -- Pulse start for one cycle; ecdh_key_exchange latches in IDLE
                        ecdh_start <= '1';
                        tstate     <= WAIT_ECDH;

                    when WAIT_ECDH =>
                        -- Wait for both phases of X25519 to complete
                        if ecdh_done = '1' then
                            -- Pack result: [public_key_out (256b)] & [shared_secret (256b)]
                            ecdh_result_reg <= std_logic_vector(resize(ecdh_pk, 256)) &
                                               std_logic_vector(resize(ecdh_ss, 256));
                            ecdh_tx_cnt <= (others => '0');
                            tstate      <= TX_ECDH_RESULT;
                        end if;

                    when TX_ECDH_RESULT =>
                        -- Send 64 bytes: 32B shared_secret (LSB first) then 32B public_key
                        if tx_busy = '0' and tx_start = '0' then
                            if ecdh_tx_cnt < to_unsigned(64, 7) then
                                tx_data         <= ecdh_result_reg(7 downto 0);
                                tx_start        <= '1';
                                ecdh_result_reg <= x"00" & ecdh_result_reg(511 downto 8);
                                ecdh_tx_cnt     <= ecdh_tx_cnt + 1;
                            else
                                tstate <= DONE_STATE;
                            end if;
                        end if;

                    -- --------------------------------------------------------
                    when DONE_STATE =>
                        led_encrypt <= '0';
                        led_poly    <= '0';
                        tstate      <= IDLE;
                end case;
            end if;
        end if;
    end process;

    -- ========================================================================
    -- LED indicators
    -- ========================================================================
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                heartbeat_cnt <= (others => '0');
                led_rx_act    <= '0';
            else
                heartbeat_cnt <= heartbeat_cnt + 1;
                if mi_ready = '1' or mi_chk_err = '1' or mi_ecdh_ready = '1' then
                    led_rx_act <= '1';
                elsif heartbeat_cnt(20 downto 0) = 0 then
                    led_rx_act <= '0';
                end if;
            end if;
        end if;
    end process;

    led_status(0) <= led_rx_act;
    led_status(1) <= led_encrypt;
    led_status(2) <= led_poly;
    led_status(3) <= heartbeat_cnt(27);  -- ~1.5 Hz at 200 MHz

end architecture rtl;
