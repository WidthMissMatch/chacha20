-- AXI4-Lite Slave Wrapper for ChaCha20-Poly1305
-- Provides PS-PL register interface bypassing UART path.
-- Instantiates chacha20_core, poly1305_mac, and ecdh_key_exchange directly.
--
-- Register Map (byte addresses, 32-bit aligned):
--   0x000 CTRL       [W] bit0=start_encrypt, bit1=start_ecdh, bit7=sw_rst
--   0x004 STATUS     [R] bit0=busy, bit1=done, bit2=tag_valid
--   0x008-0x027      KEY[0..7]        (256-bit ChaCha20 key)
--   0x028-0x033      NONCE[0..2]      (96-bit nonce)
--   0x034-0x073      PLAINTEXT[0..15] (512-bit plaintext)
--   0x074-0x0B3      CIPHERTEXT[0..15](512-bit ciphertext, read-only)
--   0x0B4-0x0C3      TAG[0..3]        (128-bit Poly1305 tag, read-only)
--   0x0C4-0x0E3      PRIV_KEY[0..7]   (256-bit ECDH private key)
--   0x0E4-0x103      PEER_PUB[0..7]   (256-bit ECDH peer public key)
--   0x104-0x143      ECDH_RESULT[0..15](512-bit ECDH output, read-only)
--
-- Encryption flow (CTRL.bit0 = 1):
--   1. ChaCha20 core, counter=0 -> 512-bit keystream; take low 256 bits as Poly1305 key
--   2. ChaCha20 core, counter=1 -> encrypt 512-bit plaintext -> ciphertext
--   3. Poly1305 MAC over 4x128-bit ciphertext blocks -> 128-bit tag
-- ECDH flow (CTRL.bit1 = 1):
--   1. ecdh_key_exchange: shared_secret || public_key_out -> ECDH_RESULT

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.chacha20_pkg.all;
use work.poly1305_pkg.all;

entity axi_lite_wrapper is
    port (
        -- AXI4-Lite clock and reset
        s_axi_aclk    : in  std_logic;
        s_axi_aresetn : in  std_logic;  -- active-low

        -- Write address channel
        s_axi_awaddr  : in  std_logic_vector(8 downto 0);
        s_axi_awvalid : in  std_logic;
        s_axi_awready : out std_logic;

        -- Write data channel
        s_axi_wdata   : in  std_logic_vector(31 downto 0);
        s_axi_wstrb   : in  std_logic_vector(3 downto 0);
        s_axi_wvalid  : in  std_logic;
        s_axi_wready  : out std_logic;

        -- Write response channel
        s_axi_bresp   : out std_logic_vector(1 downto 0);
        s_axi_bvalid  : out std_logic;
        s_axi_bready  : in  std_logic;

        -- Read address channel
        s_axi_araddr  : in  std_logic_vector(8 downto 0);
        s_axi_arvalid : in  std_logic;
        s_axi_arready : out std_logic;

        -- Read data channel
        s_axi_rdata   : out std_logic_vector(31 downto 0);
        s_axi_rresp   : out std_logic_vector(1 downto 0);
        s_axi_rvalid  : out std_logic;
        s_axi_rready  : in  std_logic
    );
end entity axi_lite_wrapper;

architecture rtl of axi_lite_wrapper is

    -- Internal clock/reset (AXI uses active-low reset; cores use active-high)
    signal clk : std_logic;
    signal rst : std_logic;

    -- -----------------------------------------------------------------------
    -- Register file
    -- -----------------------------------------------------------------------
    type reg8_t   is array(0 to 7)  of std_logic_vector(31 downto 0);
    type reg16_t  is array(0 to 15) of std_logic_vector(31 downto 0);
    type reg3_t   is array(0 to 2)  of std_logic_vector(31 downto 0);
    type reg4_t   is array(0 to 3)  of std_logic_vector(31 downto 0);

    signal reg_ctrl      : std_logic_vector(31 downto 0) := (others => '0');
    signal reg_status    : std_logic_vector(31 downto 0) := (others => '0');
    signal reg_key       : reg8_t  := (others => (others => '0'));
    signal reg_nonce     : reg3_t  := (others => (others => '0'));
    signal reg_plaintext : reg16_t := (others => (others => '0'));
    signal reg_ciphertext: reg16_t := (others => (others => '0'));
    signal reg_tag       : reg4_t  := (others => (others => '0'));
    signal reg_priv_key  : reg8_t  := (others => (others => '0'));
    signal reg_peer_pub  : reg8_t  := (others => (others => '0'));
    signal reg_ecdh_res  : reg16_t := (others => (others => '0'));

    -- -----------------------------------------------------------------------
    -- AXI handshake signals
    -- -----------------------------------------------------------------------
    signal aw_ready  : std_logic := '0';
    signal w_ready   : std_logic := '0';
    signal b_valid   : std_logic := '0';
    signal ar_ready  : std_logic := '0';
    signal r_valid   : std_logic := '0';
    signal r_data    : std_logic_vector(31 downto 0) := (others => '0');

    signal aw_addr_lat : std_logic_vector(8 downto 0) := (others => '0');
    signal ar_addr_lat : std_logic_vector(8 downto 0) := (others => '0');

    -- -----------------------------------------------------------------------
    -- chacha20_core interface
    -- -----------------------------------------------------------------------
    signal cc_start    : std_logic := '0';
    signal cc_done     : std_logic;
    signal cc_key      : std_logic_vector(255 downto 0);
    signal cc_nonce    : std_logic_vector(95 downto 0);
    signal cc_counter  : std_logic_vector(31 downto 0);
    signal cc_pt       : std_logic_vector(511 downto 0);
    signal cc_ct       : std_logic_vector(511 downto 0);
    signal cc_ks       : std_logic_vector(511 downto 0);

    -- -----------------------------------------------------------------------
    -- poly1305_mac interface
    -- -----------------------------------------------------------------------
    signal poly_start  : std_logic := '0';
    signal poly_valid  : std_logic := '0';
    signal poly_last   : std_logic := '0';
    signal poly_key    : std_logic_vector(255 downto 0) := (others => '0');
    signal poly_block  : std_logic_vector(127 downto 0) := (others => '0');
    signal poly_bytes  : std_logic_vector(4 downto 0)   := (others => '0');
    signal poly_tag    : std_logic_vector(127 downto 0);
    signal poly_tv     : std_logic;
    signal poly_ready  : std_logic;

    -- -----------------------------------------------------------------------
    -- ecdh_key_exchange interface
    -- -----------------------------------------------------------------------
    signal ecdh_start  : std_logic := '0';
    signal ecdh_done   : std_logic;
    signal ecdh_priv   : unsigned(254 downto 0) := (others => '0');
    signal ecdh_peer   : unsigned(254 downto 0) := (others => '0');
    signal ecdh_secret : unsigned(254 downto 0);
    signal ecdh_pubout : unsigned(254 downto 0);

    -- -----------------------------------------------------------------------
    -- Control FSM
    -- -----------------------------------------------------------------------
    type ctrl_fsm_t is (
        IDLE,
        -- Encryption pipeline
        GEN_POLY_KEY,   WAIT_POLY_KEY,
        ENCRYPT_BLOCK,  WAIT_ENCRYPT,
        POLY_BLOCK0, POLY_WAIT1, POLY_BLOCK1, POLY_WAIT2, POLY_BLOCK2, POLY_WAIT3, POLY_BLOCK3,
        WAIT_POLY,
        LATCH_RESULTS,
        -- ECDH pipeline
        ECDH_RUN,       WAIT_ECDH,
        LATCH_ECDH,
        DONE_ST
    );
    signal ctrl_state : ctrl_fsm_t := IDLE;

    signal block_idx  : unsigned(1 downto 0) := (others => '0');
    signal busy       : std_logic := '0';
    signal done_flag  : std_logic := '0';
    signal tag_valid  : std_logic := '0';

    -- Helper: assemble key/nonce/pt from register banks
    function regs_to_slv8(r : reg8_t) return std_logic_vector is
        variable v : std_logic_vector(255 downto 0);
    begin
        for i in 0 to 7 loop
            v(i*32+31 downto i*32) := r(i);
        end loop;
        return v;
    end function;

    function regs_to_slv3(r : reg3_t) return std_logic_vector is
        variable v : std_logic_vector(95 downto 0);
    begin
        for i in 0 to 2 loop
            v(i*32+31 downto i*32) := r(i);
        end loop;
        return v;
    end function;

    function regs_to_slv16(r : reg16_t) return std_logic_vector is
        variable v : std_logic_vector(511 downto 0);
    begin
        for i in 0 to 15 loop
            v(i*32+31 downto i*32) := r(i);
        end loop;
        return v;
    end function;

begin

    clk <= s_axi_aclk;
    rst <= not s_axi_aresetn;

    -- -----------------------------------------------------------------------
    -- chacha20_core instantiation
    -- -----------------------------------------------------------------------
    cc_inst: entity work.chacha20_core
        port map (
            clk          => clk,
            rst          => rst,
            start        => cc_start,
            done         => cc_done,
            key          => cc_key,
            nonce        => cc_nonce,
            counter_in   => cc_counter,
            plaintext    => cc_pt,
            ciphertext   => cc_ct,
            keystream_out => cc_ks
        );

    -- -----------------------------------------------------------------------
    -- poly1305_mac instantiation
    -- -----------------------------------------------------------------------
    poly_inst: entity work.poly1305_mac
        port map (
            clk        => clk,
            rst        => rst,
            poly_key   => poly_key,
            msg_block  => poly_block,
            msg_valid  => poly_valid,
            msg_last   => poly_last,
            byte_count => poly_bytes,
            tag_out    => poly_tag,
            tag_valid  => poly_tv,
            ready      => poly_ready
        );

    -- -----------------------------------------------------------------------
    -- ecdh_key_exchange instantiation
    -- -----------------------------------------------------------------------
    ecdh_inst: entity work.ecdh_key_exchange
        port map (
            clk             => clk,
            rst             => rst,
            private_key     => ecdh_priv,
            peer_public_key => ecdh_peer,
            start           => ecdh_start,
            shared_secret   => ecdh_secret,
            public_key_out  => ecdh_pubout,
            done            => ecdh_done
        );

    -- -----------------------------------------------------------------------
    -- Wire register banks to core inputs
    -- -----------------------------------------------------------------------
    cc_key   <= regs_to_slv8(reg_key);
    cc_nonce <= regs_to_slv3(reg_nonce);
    ecdh_priv <= unsigned(regs_to_slv8(reg_priv_key)(254 downto 0));
    ecdh_peer <= unsigned(regs_to_slv8(reg_peer_pub)(254 downto 0));

    -- -----------------------------------------------------------------------
    -- AXI4-Lite write path
    -- -----------------------------------------------------------------------
    s_axi_awready <= aw_ready;
    s_axi_wready  <= w_ready;
    s_axi_bresp   <= "00";   -- OKAY
    s_axi_bvalid  <= b_valid;

    process(clk)
        variable addr_w : integer range 0 to 511;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                aw_ready    <= '0';
                w_ready     <= '0';
                b_valid     <= '0';
                aw_addr_lat <= (others => '0');
            else
                -- Address handshake
                if s_axi_awvalid = '1' and aw_ready = '0' then
                    aw_ready    <= '1';
                    aw_addr_lat <= s_axi_awaddr;
                else
                    aw_ready <= '0';
                end if;

                -- Data handshake
                if s_axi_wvalid = '1' and w_ready = '0' then
                    w_ready <= '1';
                else
                    w_ready <= '0';
                end if;

                -- Write register
                if aw_ready = '1' and s_axi_wvalid = '1' then
                    addr_w := to_integer(unsigned(aw_addr_lat(8 downto 2)));
                    case addr_w is
                        when 0 => reg_ctrl <= s_axi_wdata;
                        when 8  to 15  =>
                            reg_key(addr_w - 8) <= s_axi_wdata;
                        when 16 to 18  =>
                            reg_nonce(addr_w - 16) <= s_axi_wdata;
                        when 19 to 34  =>
                            reg_plaintext(addr_w - 19) <= s_axi_wdata;
                        when 49 to 56  =>
                            reg_priv_key(addr_w - 49) <= s_axi_wdata;
                        when 57 to 64  =>
                            reg_peer_pub(addr_w - 57) <= s_axi_wdata;
                        when others => null;
                    end case;
                    b_valid <= '1';
                elsif s_axi_bready = '1' then
                    b_valid <= '0';
                end if;
            end if;
        end if;
    end process;

    -- -----------------------------------------------------------------------
    -- AXI4-Lite read path
    -- -----------------------------------------------------------------------
    s_axi_arready <= ar_ready;
    s_axi_rdata   <= r_data;
    s_axi_rresp   <= "00";
    s_axi_rvalid  <= r_valid;

    process(clk)
        variable addr_r : integer range 0 to 511;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                ar_ready    <= '0';
                r_valid     <= '0';
                r_data      <= (others => '0');
                ar_addr_lat <= (others => '0');
            else
                if s_axi_arvalid = '1' and ar_ready = '0' then
                    ar_ready    <= '1';
                    ar_addr_lat <= s_axi_araddr;
                else
                    ar_ready <= '0';
                end if;

                if ar_ready = '1' and r_valid = '0' then
                    addr_r := to_integer(unsigned(ar_addr_lat(8 downto 2)));
                    r_valid <= '1';
                    case addr_r is
                        when 0      => r_data <= reg_ctrl;
                        when 1      => r_data <= reg_status;
                        when 29 to 44 =>
                            r_data <= reg_ciphertext(addr_r - 29);
                        when 45 to 48 =>
                            r_data <= reg_tag(addr_r - 45);
                        when 65 to 80 =>
                            r_data <= reg_ecdh_res(addr_r - 65);
                        when others => r_data <= (others => '0');
                    end case;
                elsif s_axi_rready = '1' then
                    r_valid <= '0';
                end if;
            end if;
        end if;
    end process;

    -- -----------------------------------------------------------------------
    -- Status register
    -- -----------------------------------------------------------------------
    reg_status(0) <= busy;
    reg_status(1) <= done_flag;
    reg_status(2) <= tag_valid;
    reg_status(31 downto 3) <= (others => '0');

    -- -----------------------------------------------------------------------
    -- Control FSM — orchestrates encryption and ECDH pipelines
    -- -----------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                ctrl_state <= IDLE;
                busy       <= '0';
                done_flag  <= '0';
                tag_valid  <= '0';
                cc_start   <= '0';
                cc_counter <= (others => '0');
                cc_pt      <= (others => '0');
                poly_valid <= '0';
                poly_last  <= '0';
                poly_bytes <= "10000";
                ecdh_start <= '0';
                block_idx  <= (others => '0');
            else
                -- Default pulse signals
                cc_start   <= '0';
                ecdh_start <= '0';
                poly_valid <= '0';
                poly_last  <= '0';

                -- Clear done on new CTRL write (triggers)
                if reg_ctrl(7) = '1' then   -- sw_rst
                    ctrl_state <= IDLE;
                    busy       <= '0';
                    done_flag  <= '0';
                    tag_valid  <= '0';
                end if;

                case ctrl_state is

                    when IDLE =>
                        if reg_ctrl(0) = '1' then
                            -- Start encryption
                            busy      <= '1';
                            done_flag <= '0';
                            tag_valid <= '0';
                            ctrl_state <= GEN_POLY_KEY;
                        elsif reg_ctrl(1) = '1' then
                            -- Start ECDH
                            busy      <= '1';
                            done_flag <= '0';
                            ctrl_state <= ECDH_RUN;
                        end if;

                    -- --------------------------------------------------------
                    -- Step 1: Generate Poly1305 key (ChaCha20 counter=0, pt=0)
                    -- --------------------------------------------------------
                    when GEN_POLY_KEY =>
                        cc_counter <= (others => '0');
                        cc_pt      <= (others => '0');
                        cc_start   <= '1';
                        ctrl_state <= WAIT_POLY_KEY;

                    when WAIT_POLY_KEY =>
                        if cc_done = '1' then
                            -- Low 256 bits of keystream = Poly1305 key
                            poly_key   <= cc_ks(255 downto 0);
                            ctrl_state <= ENCRYPT_BLOCK;
                        end if;

                    -- --------------------------------------------------------
                    -- Step 2: Encrypt plaintext (counter=1)
                    -- --------------------------------------------------------
                    when ENCRYPT_BLOCK =>
                        cc_counter <= std_logic_vector(to_unsigned(1, 32));
                        cc_pt      <= regs_to_slv16(reg_plaintext);
                        cc_start   <= '1';
                        ctrl_state <= WAIT_ENCRYPT;

                    when WAIT_ENCRYPT =>
                        if cc_done = '1' then
                            -- Store ciphertext into output registers
                            for i in 0 to 15 loop
                                reg_ciphertext(i) <= cc_ct(i*32+31 downto i*32);
                            end loop;
                            block_idx  <= (others => '0');
                            ctrl_state <= POLY_BLOCK0;
                        end if;

                    -- --------------------------------------------------------
                    -- Step 3: Feed 4x128-bit ciphertext blocks to Poly1305
                    -- --------------------------------------------------------
                    when POLY_BLOCK0 =>
                        -- Feed block 0 unconditionally (MAC starts from IDLE on msg_valid)
                        poly_block <= cc_ct(127 downto 0);
                        poly_bytes <= "10000";   -- 16 bytes
                        poly_last  <= '0';
                        poly_valid <= '1';
                        ctrl_state <= POLY_WAIT1;

                    when POLY_WAIT1 =>
                        -- One-cycle gap: let MAC de-assert ready before next check
                        ctrl_state <= POLY_BLOCK1;

                    when POLY_BLOCK1 =>
                        if poly_ready = '1' then
                            poly_block <= cc_ct(255 downto 128);
                            poly_bytes <= "10000";
                            poly_last  <= '0';
                            poly_valid <= '1';
                            ctrl_state <= POLY_WAIT2;
                        end if;

                    when POLY_WAIT2 =>
                        ctrl_state <= POLY_BLOCK2;

                    when POLY_BLOCK2 =>
                        if poly_ready = '1' then
                            poly_block <= cc_ct(383 downto 256);
                            poly_bytes <= "10000";
                            poly_last  <= '0';
                            poly_valid <= '1';
                            ctrl_state <= POLY_WAIT3;
                        end if;

                    when POLY_WAIT3 =>
                        ctrl_state <= POLY_BLOCK3;

                    when POLY_BLOCK3 =>
                        if poly_ready = '1' then
                            poly_block <= cc_ct(511 downto 384);
                            poly_bytes <= "10000";
                            poly_last  <= '1';
                            poly_valid <= '1';
                            ctrl_state <= WAIT_POLY;
                        end if;

                    when WAIT_POLY =>
                        if poly_tv = '1' then
                            ctrl_state <= LATCH_RESULTS;
                        end if;

                    when LATCH_RESULTS =>
                        for i in 0 to 3 loop
                            reg_tag(i) <= poly_tag(i*32+31 downto i*32);
                        end loop;
                        tag_valid  <= '1';
                        busy       <= '0';
                        done_flag  <= '1';
                        ctrl_state <= DONE_ST;

                    -- --------------------------------------------------------
                    -- ECDH pipeline
                    -- --------------------------------------------------------
                    when ECDH_RUN =>
                        ecdh_start <= '1';
                        ctrl_state <= WAIT_ECDH;

                    when WAIT_ECDH =>
                        if ecdh_done = '1' then
                            ctrl_state <= LATCH_ECDH;
                        end if;

                    when LATCH_ECDH =>
                        -- shared_secret in words 0..7, public_key_out in words 8..15
                        for i in 0 to 7 loop
                            reg_ecdh_res(i) <=
                                std_logic_vector(ecdh_secret(i*32+31 downto i*32));
                            reg_ecdh_res(i+8) <=
                                std_logic_vector(ecdh_pubout(i*32+31 downto i*32));
                        end loop;
                        busy       <= '0';
                        done_flag  <= '1';
                        ctrl_state <= DONE_ST;

                    when DONE_ST =>
                        -- Stay here until CTRL is cleared by software
                        if reg_ctrl(0) = '0' and reg_ctrl(1) = '0' then
                            ctrl_state <= IDLE;
                        end if;

                end case;
            end if;
        end if;
    end process;

end architecture rtl;
