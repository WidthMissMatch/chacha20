-- MATLAB UART Interface
-- Receives: [0xAA header] [32B key] [12B nonce] [64B plaintext] [1B checksum] = 110 bytes
-- Outputs key, nonce, plaintext with data_ready pulse on valid checksum
-- Also receives: [0xAB header] [32B priv_key] [32B peer_pub] [1B checksum] = 66 bytes
-- Outputs priv_key_out, peer_pub_out with ecdh_ready pulse on valid checksum

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity matlab_uart_interface is
    generic (
        CLK_FREQ  : positive := 200_000_000;
        BAUD_RATE : positive := 115200
    );
    port (
        clk           : in  std_logic;
        rst           : in  std_logic;
        -- UART pin
        uart_rx_pin   : in  std_logic;
        -- Encrypt path outputs (0xAA packet)
        key_out       : out std_logic_vector(255 downto 0);
        nonce_out     : out std_logic_vector(95 downto 0);
        plaintext_out : out std_logic_vector(511 downto 0);
        data_ready    : out std_logic;
        checksum_err  : out std_logic;
        -- ECDH path outputs (0xAB packet)
        ecdh_ready    : out std_logic;
        priv_key_out  : out std_logic_vector(255 downto 0);
        peer_pub_out  : out std_logic_vector(255 downto 0);
        -- NACK output (active UART TX for 0xFF on checksum error)
        uart_tx_pin   : out std_logic
    );
end entity matlab_uart_interface;

architecture rtl of matlab_uart_interface is

    type fsm_state is (IDLE, WAIT_HEADER, RX_KEY, RX_NONCE, RX_DATA,
                        RX_PRIV_KEY, RX_PEER_PUB,
                        VERIFY_CHECKSUM, READY, ECDH_READY_STATE,
                        ERROR_STATE, SEND_NACK);
    signal state : fsm_state := IDLE;

    -- UART RX interface
    signal uart_byte  : std_logic_vector(7 downto 0);
    signal uart_valid : std_logic;
    signal uart_error : std_logic;

    -- Internal registers
    signal key_reg      : std_logic_vector(255 downto 0) := (others => '0');
    signal nonce_reg    : std_logic_vector(95 downto 0)  := (others => '0');
    signal pt_reg       : std_logic_vector(511 downto 0) := (others => '0');
    signal priv_key_reg : std_logic_vector(255 downto 0) := (others => '0');
    signal peer_pub_reg : std_logic_vector(255 downto 0) := (others => '0');

    signal byte_cnt  : unsigned(6 downto 0) := (others => '0');  -- 0-63
    signal checksum  : std_logic_vector(7 downto 0) := (others => '0');

    -- Mode: '0' = encrypt (0xAA), '1' = ecdh (0xAB)
    signal mode : std_logic := '0';

    -- NACK TX signals
    signal nack_tx_data  : std_logic_vector(7 downto 0);
    signal nack_tx_start : std_logic := '0';
    signal nack_tx_busy  : std_logic;

begin

    -- UART receiver
    uart_rx_inst: entity work.uart_rx
        generic map (
            CLK_FREQ  => CLK_FREQ,
            BAUD_RATE => BAUD_RATE
        )
        port map (
            clk      => clk,
            rst      => rst,
            rx_in    => uart_rx_pin,
            data_out => uart_byte,
            rx_valid => uart_valid,
            rx_error => uart_error
        );

    -- UART TX for NACK byte
    uart_tx_nack: entity work.uart_tx
        generic map (CLK_FREQ => CLK_FREQ, BAUD_RATE => BAUD_RATE)
        port map (
            clk      => clk,
            rst      => rst,
            data_in  => nack_tx_data,
            tx_start => nack_tx_start,
            tx_busy  => nack_tx_busy,
            tx_out   => uart_tx_pin
        );

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state        <= IDLE;
                data_ready   <= '0';
                checksum_err <= '0';
                ecdh_ready   <= '0';
                byte_cnt     <= (others => '0');
                checksum     <= (others => '0');
                mode         <= '0';
                key_reg      <= (others => '0');
                nonce_reg    <= (others => '0');
                pt_reg       <= (others => '0');
                priv_key_reg <= (others => '0');
                peer_pub_reg <= (others => '0');
            else
                data_ready    <= '0';
                checksum_err  <= '0';
                ecdh_ready    <= '0';
                nack_tx_start <= '0';

                case state is
                    when IDLE =>
                        byte_cnt <= (others => '0');
                        checksum <= (others => '0');
                        mode     <= '0';
                        state    <= WAIT_HEADER;

                    when WAIT_HEADER =>
                        if uart_valid = '1' then
                            if uart_byte = x"AA" then
                                checksum <= uart_byte;
                                byte_cnt <= (others => '0');
                                mode     <= '0';
                                state    <= RX_KEY;
                            elsif uart_byte = x"AB" then
                                checksum <= uart_byte;
                                byte_cnt <= (others => '0');
                                mode     <= '1';
                                state    <= RX_PRIV_KEY;
                            end if;
                            -- Other bytes silently ignored
                        end if;

                    when RX_KEY =>
                        -- Receive 32 bytes of key (byte 0 → bits 7:0, byte 31 → bits 255:248)
                        if uart_valid = '1' then
                            key_reg(to_integer(byte_cnt)*8 + 7 downto to_integer(byte_cnt)*8) <= uart_byte;
                            checksum <= checksum xor uart_byte;
                            if byte_cnt = to_unsigned(31, 7) then
                                byte_cnt <= (others => '0');
                                state    <= RX_NONCE;
                            else
                                byte_cnt <= byte_cnt + 1;
                            end if;
                        end if;

                    when RX_NONCE =>
                        -- Receive 12 bytes of nonce
                        if uart_valid = '1' then
                            nonce_reg(to_integer(byte_cnt)*8 + 7 downto to_integer(byte_cnt)*8) <= uart_byte;
                            checksum <= checksum xor uart_byte;
                            if byte_cnt = to_unsigned(11, 7) then
                                byte_cnt <= (others => '0');
                                state    <= RX_DATA;
                            else
                                byte_cnt <= byte_cnt + 1;
                            end if;
                        end if;

                    when RX_DATA =>
                        -- Receive 64 bytes of plaintext
                        if uart_valid = '1' then
                            pt_reg(to_integer(byte_cnt)*8 + 7 downto to_integer(byte_cnt)*8) <= uart_byte;
                            checksum <= checksum xor uart_byte;
                            if byte_cnt = to_unsigned(63, 7) then
                                state <= VERIFY_CHECKSUM;
                            else
                                byte_cnt <= byte_cnt + 1;
                            end if;
                        end if;

                    when RX_PRIV_KEY =>
                        -- Receive 32 bytes of private key (0xAB path)
                        if uart_valid = '1' then
                            priv_key_reg(to_integer(byte_cnt)*8 + 7 downto to_integer(byte_cnt)*8) <= uart_byte;
                            checksum <= checksum xor uart_byte;
                            if byte_cnt = to_unsigned(31, 7) then
                                byte_cnt <= (others => '0');
                                state    <= RX_PEER_PUB;
                            else
                                byte_cnt <= byte_cnt + 1;
                            end if;
                        end if;

                    when RX_PEER_PUB =>
                        -- Receive 32 bytes of peer public key (0xAB path)
                        if uart_valid = '1' then
                            peer_pub_reg(to_integer(byte_cnt)*8 + 7 downto to_integer(byte_cnt)*8) <= uart_byte;
                            checksum <= checksum xor uart_byte;
                            if byte_cnt = to_unsigned(31, 7) then
                                state <= VERIFY_CHECKSUM;
                            else
                                byte_cnt <= byte_cnt + 1;
                            end if;
                        end if;

                    when VERIFY_CHECKSUM =>
                        -- Receive 1 checksum byte and compare
                        if uart_valid = '1' then
                            if uart_byte = checksum then
                                if mode = '0' then
                                    -- Encrypt path: output key/nonce/plaintext
                                    key_out       <= key_reg;
                                    nonce_out     <= nonce_reg;
                                    plaintext_out <= pt_reg;
                                    state         <= READY;
                                else
                                    -- ECDH path: output priv_key/peer_pub
                                    priv_key_out <= priv_key_reg;
                                    peer_pub_out <= peer_pub_reg;
                                    state        <= ECDH_READY_STATE;
                                end if;
                            else
                                state <= ERROR_STATE;
                            end if;
                        end if;

                    when READY =>
                        data_ready <= '1';
                        state      <= IDLE;

                    when ECDH_READY_STATE =>
                        ecdh_ready <= '1';
                        state      <= IDLE;

                    when ERROR_STATE =>
                        nack_tx_data  <= x"FF";
                        nack_tx_start <= '1';
                        state         <= SEND_NACK;

                    when SEND_NACK =>
                        nack_tx_start <= '0';
                        if nack_tx_busy = '0' then
                            checksum_err <= '1';
                            state        <= IDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;

end architecture rtl;
