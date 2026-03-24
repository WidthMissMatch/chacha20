-- ChaCha20 Core
-- Structural top-level: state_init -> round_controller -> keystream_xor
-- Supports multi-block encryption with auto-incrementing counter

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.chacha20_pkg.all;

entity chacha20_core is
    port (
        clk        : in  std_logic;
        rst        : in  std_logic;
        -- Control
        start      : in  std_logic;
        done       : out std_logic;
        -- Key material
        key        : in  std_logic_vector(255 downto 0);
        nonce      : in  std_logic_vector(95 downto 0);
        counter_in : in  std_logic_vector(31 downto 0);
        -- Data
        plaintext  : in  std_logic_vector(511 downto 0);
        ciphertext : out std_logic_vector(511 downto 0);
        -- Keystream output (for Poly1305 key generation)
        keystream_out : out std_logic_vector(511 downto 0)
    );
end entity chacha20_core;

architecture rtl of chacha20_core is

    signal init_state   : state_array;
    signal round_result : state_array;
    signal round_done   : std_logic;
    signal round_start  : std_logic;
    signal keystream_slv : std_logic_vector(511 downto 0);

begin

    -- State initialization
    state_init_inst: entity work.chacha20_state_init
        port map (
            key     => key,
            counter => counter_in,
            nonce   => nonce,
            state   => init_state
        );

    -- Round controller (20 rounds = 10 double rounds)
    round_ctrl_inst: entity work.round_controller
        port map (
            clk       => clk,
            rst       => rst,
            start     => start,
            state_in  => init_state,
            state_out => round_result,
            done      => round_done
        );

    -- Convert round result to SLV for XOR
    keystream_slv <= state_to_slv(round_result);
    keystream_out <= keystream_slv;

    -- Keystream XOR
    xor_inst: entity work.keystream_xor
        port map (
            keystream  => keystream_slv,
            plaintext  => plaintext,
            ciphertext => ciphertext
        );

    done <= round_done;

end architecture rtl;
