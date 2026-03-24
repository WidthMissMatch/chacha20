--------------------------------------------------------------------------------
-- tb_ecdh_key_exchange.vhd
-- Testbench for X25519 ECDH key exchange (RFC 7748 Section 6.1 test vectors)
--
-- Test 1: Alice's private key x Bob's public key  -> shared secret
-- Test 2: Bob's private key x Alice's public key   -> same shared secret
--
-- All hex constants are byte-reversed from RFC 7748 little-endian encoding
-- to match VHDL big-endian unsigned representation.
--
-- VHDL-2008
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library work;
use work.chacha20_pkg.all;

entity tb_ecdh_key_exchange is
end entity tb_ecdh_key_exchange;

architecture sim of tb_ecdh_key_exchange is

    constant CLK_PERIOD : time := 10 ns;

    signal clk             : std_logic := '0';
    signal rst             : std_logic := '1';
    signal private_key     : unsigned(254 downto 0) := (others => '0');
    signal peer_public_key : unsigned(254 downto 0) := (others => '0');
    signal start           : std_logic := '0';
    signal shared_secret   : unsigned(254 downto 0);
    signal public_key_out  : unsigned(254 downto 0);
    signal done            : std_logic;

    ---------------------------------------------------------------------------
    -- RFC 7748 Section 6.1 test vectors (byte-reversed to big-endian)
    ---------------------------------------------------------------------------

    -- Alice's private key (LE): 77076d0a7318a57d3c16c17251b26645
    --                           df4c2f87ebc0992ab177fba51db92c2a
    -- Byte-reversed (BE 256-bit):
    constant ALICE_PRIV_256 : unsigned(255 downto 0) :=
        x"2a2cb91da5fb77b12a99c0eb872f4cdf4566b25172c1163c7da518730a6d0777";

    -- Bob's private key (LE): 5dab087e624a8a4b79e17f8b83800ee6
    --                         6f3bb1292618b6fd1c2f8b27ff88e0eb
    -- Byte-reversed (BE 256-bit):
    constant BOB_PRIV_256 : unsigned(255 downto 0) :=
        x"ebe088ff278b2f1cfdb6182629b13b6fe60e80838b7fe1794b8a4a627e08ab5d";

    -- Alice's public key (LE): 8520f0098930a754748b7ddcb43ef75a
    --                          0dbf3a0d26381af4eba4a98eaa9b4e6a
    -- Byte-reversed (BE 256-bit):
    constant ALICE_PUB_256 : unsigned(255 downto 0) :=
        x"6a4e9baa8ea9a4ebf41a38260d3abf0d5af73eb4dc7d8b7454a7308909f02085";

    -- Bob's public key (LE): de9edb7d7b7dc1b4d35b61c2ece43537
    --                        3f8343c85b78674dadfc7e146f882b4f
    -- Byte-reversed (BE 256-bit):
    constant BOB_PUB_256 : unsigned(255 downto 0) :=
        x"4f2b886f147efcad4d67785bc843833f3735e4ecc2615bd3b4c17d7b7ddb9ede";

    -- Shared secret (LE): 4a5d9d5ba4ce2de1728e3bf480350f25
    --                     e07e21c947d19e3376f09b3c1e161742
    -- Byte-reversed (BE 256-bit):
    constant SHARED_SECRET_256 : unsigned(255 downto 0) :=
        x"4217161e3c9bf076339ed147c9217ee0250f3580f43b8e72e12dcea45b9d5d4a";

    -- Extract lower 255 bits for our 255-bit entity ports
    constant ALICE_PRIV    : unsigned(254 downto 0) := ALICE_PRIV_256(254 downto 0);
    constant BOB_PRIV      : unsigned(254 downto 0) := BOB_PRIV_256(254 downto 0);
    constant ALICE_PUB     : unsigned(254 downto 0) := ALICE_PUB_256(254 downto 0);
    constant BOB_PUB       : unsigned(254 downto 0) := BOB_PUB_256(254 downto 0);
    constant EXPECTED_SS   : unsigned(254 downto 0) := SHARED_SECRET_256(254 downto 0);

    -- Test tracking
    signal test_num    : integer := 0;
    signal pass_count  : integer := 0;
    signal fail_count  : integer := 0;

    -- Helper: convert unsigned to hex string for reporting
    function to_hex_string(val : unsigned) return string is
        variable result : string(1 to (val'length + 3) / 4);
        variable nibble : unsigned(3 downto 0);
        variable padded : unsigned(result'length * 4 - 1 downto 0);
        constant hex_chars : string(1 to 16) := "0123456789abcdef";
    begin
        padded := resize(val, padded'length);
        for i in result'range loop
            nibble := padded(padded'high - (i-1)*4 downto padded'high - (i-1)*4 - 3);
            result(i) := hex_chars(to_integer(nibble) + 1);
        end loop;
        return result;
    end function;

begin

    ---------------------------------------------------------------------------
    -- Clock generation
    ---------------------------------------------------------------------------
    clk <= not clk after CLK_PERIOD / 2;

    ---------------------------------------------------------------------------
    -- DUT
    ---------------------------------------------------------------------------
    dut : entity work.ecdh_key_exchange
        port map (
            clk             => clk,
            rst             => rst,
            private_key     => private_key,
            peer_public_key => peer_public_key,
            start           => start,
            shared_secret   => shared_secret,
            public_key_out  => public_key_out,
            done            => done
        );

    ---------------------------------------------------------------------------
    -- Stimulus process
    ---------------------------------------------------------------------------
    stim_proc : process
        procedure run_test(
            test_id   : integer;
            priv_key  : unsigned(254 downto 0);
            pub_key   : unsigned(254 downto 0);
            exp_ss    : unsigned(254 downto 0);
            test_desc : string
        ) is
        begin
            test_num    <= test_id;
            private_key     <= priv_key;
            peer_public_key <= pub_key;

            -- Pulse start
            wait until rising_edge(clk);
            start <= '1';
            wait until rising_edge(clk);
            start <= '0';

            -- Wait for done
            wait until done = '1' for 500 ms;

            if done /= '1' then
                report "Test " & integer'image(test_id) & " (" & test_desc &
                       "): TIMEOUT - did not complete" severity error;
                fail_count <= fail_count + 1;
            elsif shared_secret = exp_ss then
                report "Test " & integer'image(test_id) & " (" & test_desc &
                       "): PASSED" severity note;
                pass_count <= pass_count + 1;
            else
                report "Test " & integer'image(test_id) & " (" & test_desc &
                       "): FAILED" severity error;
                report "  Expected SS: " & to_hex_string(exp_ss) severity note;
                report "  Got SS:      " & to_hex_string(shared_secret) severity note;
                fail_count <= fail_count + 1;
            end if;

            -- Wait for done to deassert before next test
            wait until rising_edge(clk);
            wait until rising_edge(clk);
        end procedure;

    begin
        -- Reset
        rst   <= '1';
        start <= '0';
        wait for CLK_PERIOD * 10;
        rst <= '0';
        wait for CLK_PERIOD * 5;

        report "========================================" severity note;
        report "  ECDH Key Exchange Testbench Start" severity note;
        report "  RFC 7748 Section 6.1 Test Vectors" severity note;
        report "========================================" severity note;

        -----------------------------------------------------------------------
        -- Test 1: Alice private x Bob public -> shared secret
        -----------------------------------------------------------------------
        run_test(
            test_id   => 1,
            priv_key  => ALICE_PRIV,
            pub_key   => BOB_PUB,
            exp_ss    => EXPECTED_SS,
            test_desc => "Alice priv x Bob pub"
        );

        -----------------------------------------------------------------------
        -- Test 2: Bob private x Alice public -> shared secret (must match)
        -----------------------------------------------------------------------
        run_test(
            test_id   => 2,
            priv_key  => BOB_PRIV,
            pub_key   => ALICE_PUB,
            exp_ss    => EXPECTED_SS,
            test_desc => "Bob priv x Alice pub"
        );

        -----------------------------------------------------------------------
        -- Summary
        -----------------------------------------------------------------------
        wait for CLK_PERIOD * 5;

        report "========================================" severity note;
        report "  ECDH Key Exchange Test Summary" severity note;
        report "  Passed: " & integer'image(pass_count) severity note;
        report "  Failed: " & integer'image(fail_count) severity note;
        report "========================================" severity note;

        if fail_count = 0 then
            report "=== ALL ECDH_KEY_EXCHANGE TESTS PASSED ===" severity note;
        else
            report "=== SOME ECDH_KEY_EXCHANGE TESTS FAILED ===" severity error;
        end if;

        std.env.stop;
        wait;
    end process stim_proc;

end architecture sim;
