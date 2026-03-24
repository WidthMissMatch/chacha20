-- ChaCha20 State Initialization
-- Combinational: assembles 4x4 state from constants + key + counter + nonce
-- Layout (RFC 7539 Section 2.3):
--   cccccccc  cccccccc  cccccccc  cccccccc
--   kkkkkkkk  kkkkkkkk  kkkkkkkk  kkkkkkkk
--   kkkkkkkk  kkkkkkkk  kkkkkkkk  kkkkkkkk
--   bbbbbbbb  nnnnnnnn  nnnnnnnn  nnnnnnnn
-- All words are little-endian

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.chacha20_pkg.all;

entity chacha20_state_init is
    port (
        key     : in  std_logic_vector(255 downto 0);
        counter : in  std_logic_vector(31 downto 0);
        nonce   : in  std_logic_vector(95 downto 0);
        state   : out state_array
    );
end entity chacha20_state_init;

architecture rtl of chacha20_state_init is
begin

    -- Row 0: Constants
    state(0)  <= C0;
    state(1)  <= C1;
    state(2)  <= C2;
    state(3)  <= C3;

    -- Row 1-2: Key (8 words, little-endian byte order within each word)
    -- key(31 downto 0) is the first 4 bytes -> word 4
    gen_key: for i in 0 to 7 generate
        state(4 + i) <= unsigned(key(i*32 + 31 downto i*32));
    end generate;

    -- Row 3, word 12: Block counter
    state(12) <= unsigned(counter);

    -- Row 3, words 13-15: Nonce (3 words, little-endian)
    gen_nonce: for i in 0 to 2 generate
        state(13 + i) <= unsigned(nonce(i*32 + 31 downto i*32));
    end generate;

end architecture rtl;
