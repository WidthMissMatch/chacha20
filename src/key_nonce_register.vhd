-- Key/Nonce Register
-- Sequences Poly1305 key generation (counter=0) then encryption (counter=1)
-- Per RFC 8439: first ChaCha20 block with counter=0 generates Poly1305 key

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity key_nonce_register is
    port (
        clk            : in  std_logic;
        rst            : in  std_logic;
        -- From MATLAB interface
        key_in         : in  std_logic_vector(255 downto 0);
        nonce_in       : in  std_logic_vector(95 downto 0);
        plaintext_in   : in  std_logic_vector(511 downto 0);
        data_valid     : in  std_logic;
        -- To/from chacha20_core
        key_out        : out std_logic_vector(255 downto 0);
        nonce_out      : out std_logic_vector(95 downto 0);
        counter_out    : out std_logic_vector(31 downto 0);
        plaintext_out  : out std_logic_vector(511 downto 0);
        start_core     : out std_logic;
        core_done      : in  std_logic;
        keystream_in   : in  std_logic_vector(511 downto 0);
        -- To poly1305_mac
        poly_key_out   : out std_logic_vector(255 downto 0);
        poly_key_valid : out std_logic;
        -- Ciphertext output
        cipher_data    : out std_logic_vector(511 downto 0);
        cipher_valid   : out std_logic;
        -- Status
        busy           : out std_logic
    );
end entity key_nonce_register;

architecture rtl of key_nonce_register is

    type fsm_state is (IDLE, GEN_POLY_KEY, WAIT_POLY_DONE,
                        ENCRYPT_BLOCK, WAIT_ENCRYPT_DONE,
                        OUTPUT_CIPHER, DONE_STATE);
    signal state : fsm_state := IDLE;

    signal key_reg   : std_logic_vector(255 downto 0) := (others => '0');
    signal nonce_reg : std_logic_vector(95 downto 0)  := (others => '0');
    signal pt_reg    : std_logic_vector(511 downto 0) := (others => '0');

begin

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state          <= IDLE;
                start_core     <= '0';
                poly_key_valid <= '0';
                cipher_valid   <= '0';
                busy           <= '0';
                key_out        <= (others => '0');
                nonce_out      <= (others => '0');
                counter_out    <= (others => '0');
                plaintext_out  <= (others => '0');
                poly_key_out   <= (others => '0');
                cipher_data    <= (others => '0');
                key_reg        <= (others => '0');
                nonce_reg      <= (others => '0');
                pt_reg         <= (others => '0');
            else
                start_core     <= '0';
                poly_key_valid <= '0';
                cipher_valid   <= '0';

                case state is
                    when IDLE =>
                        busy <= '0';
                        if data_valid = '1' then
                            -- Latch inputs
                            key_reg   <= key_in;
                            nonce_reg <= nonce_in;
                            pt_reg    <= plaintext_in;
                            busy      <= '1';
                            state     <= GEN_POLY_KEY;
                        end if;

                    when GEN_POLY_KEY =>
                        -- Counter=0, plaintext=0 for Poly1305 key generation
                        key_out       <= key_reg;
                        nonce_out     <= nonce_reg;
                        counter_out   <= x"00000000";
                        plaintext_out <= (others => '0');
                        start_core    <= '1';
                        state         <= WAIT_POLY_DONE;

                    when WAIT_POLY_DONE =>
                        if core_done = '1' then
                            -- First 256 bits of keystream = Poly1305 key
                            poly_key_out   <= keystream_in(255 downto 0);
                            poly_key_valid <= '1';
                            state          <= ENCRYPT_BLOCK;
                        end if;

                    when ENCRYPT_BLOCK =>
                        -- Counter=1, actual plaintext
                        counter_out   <= x"00000001";
                        plaintext_out <= pt_reg;
                        start_core    <= '1';
                        state         <= WAIT_ENCRYPT_DONE;

                    when WAIT_ENCRYPT_DONE =>
                        if core_done = '1' then
                            state <= OUTPUT_CIPHER;
                        end if;

                    when OUTPUT_CIPHER =>
                        cipher_valid <= '1';
                        state        <= DONE_STATE;

                    when DONE_STATE =>
                        busy  <= '0';
                        state <= IDLE;
                end case;
            end if;
        end if;
    end process;

end architecture rtl;
