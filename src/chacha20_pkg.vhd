-- ChaCha20 Package
-- Types, constants, and utility functions for ChaCha20 cipher
-- IEEE 2008 compliant, pure integer arithmetic (no fixed-point)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package chacha20_pkg is

    -- Core state word type
    subtype word32 is unsigned(31 downto 0);

    -- ChaCha20 state: 4x4 matrix of 32-bit words (16 words)
    type state_array is array(0 to 15) of word32;

    -- ChaCha20 constants: "expand 32-byte k" in little-endian
    constant C0 : word32 := x"61707865";  -- "expa"
    constant C1 : word32 := x"3320646e";  -- "nd 3"
    constant C2 : word32 := x"79622d32";  -- "2-by"
    constant C3 : word32 := x"6b206574";  -- "te k"

    -- Rotate left function for 32-bit unsigned
    function rotl(val : word32; n : natural) return word32;

    -- Convert state array to 512-bit std_logic_vector (little-endian word order)
    function state_to_slv(s : state_array) return std_logic_vector;

    -- Convert 512-bit std_logic_vector to state array (little-endian word order)
    function slv_to_state(v : std_logic_vector(511 downto 0)) return state_array;

    -- Curve25519 constants for ECDH
    constant CURVE25519_P : unsigned(255 downto 0) := x"7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFED";
    constant A24_CURVE25519 : unsigned(254 downto 0) := to_unsigned(121666, 255);
    constant CURVE25519_BASE_U : unsigned(254 downto 0) := to_unsigned(9, 255);
    constant NR_ITERATIONS : positive := 8;

    -- GF(2^255-19) addition: (a + b) mod p
    function gf25519_add(a, b : unsigned(254 downto 0)) return unsigned;

    -- GF(2^255-19) subtraction: (a - b) mod p (add p if underflow)
    function gf25519_sub(a, b : unsigned(254 downto 0)) return unsigned;

end package chacha20_pkg;

package body chacha20_pkg is

    function rotl(val : word32; n : natural) return word32 is
    begin
        return val(31 - n downto 0) & val(31 downto 32 - n);
    end function;

    function state_to_slv(s : state_array) return std_logic_vector is
        variable result : std_logic_vector(511 downto 0);
    begin
        for i in 0 to 15 loop
            result(i*32 + 31 downto i*32) := std_logic_vector(s(i));
        end loop;
        return result;
    end function;

    function slv_to_state(v : std_logic_vector(511 downto 0)) return state_array is
        variable result : state_array;
    begin
        for i in 0 to 15 loop
            result(i) := unsigned(v(i*32 + 31 downto i*32));
        end loop;
        return result;
    end function;

    function gf25519_add(a, b : unsigned(254 downto 0)) return unsigned is
        variable sum : unsigned(255 downto 0);
        constant P : unsigned(255 downto 0) := x"7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFED";
    begin
        sum := resize(a, 256) + resize(b, 256);
        if sum >= P then
            sum := sum - P;
        end if;
        return sum(254 downto 0);
    end function;

    function gf25519_sub(a, b : unsigned(254 downto 0)) return unsigned is
        variable diff : unsigned(255 downto 0);
        constant P : unsigned(255 downto 0) := x"7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFED";
    begin
        if a >= b then
            diff := resize(a, 256) - resize(b, 256);
        else
            diff := resize(a, 256) + P - resize(b, 256);
        end if;
        -- Final reduction in case diff >= P
        if diff >= P then
            diff := diff - P;
        end if;
        return diff(254 downto 0);
    end function;

end package body chacha20_pkg;
