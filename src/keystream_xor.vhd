-- ChaCha20 Keystream XOR
-- Combinational: ciphertext = keystream XOR plaintext
-- Operates on 512-bit blocks

library ieee;
use ieee.std_logic_1164.all;

entity keystream_xor is
    port (
        keystream  : in  std_logic_vector(511 downto 0);
        plaintext  : in  std_logic_vector(511 downto 0);
        ciphertext : out std_logic_vector(511 downto 0)
    );
end entity keystream_xor;

architecture rtl of keystream_xor is
begin
    ciphertext <= keystream xor plaintext;
end architecture rtl;
