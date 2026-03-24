-- Poly1305 Package
-- Types, constants, and utility functions for Poly1305 MAC
-- IEEE 2008 compliant

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package poly1305_pkg is

    -- 130-bit word for GF(2^130-5) arithmetic
    subtype poly_word is unsigned(129 downto 0);

    -- Prime P = 2^130 - 5 (131 bits needed to represent)
    constant POLY_P : unsigned(130 downto 0) :=
        "100" & x"00000000000000000000000000000000" - 5;
    -- = 0x3fffffffffffffffffffffffffffffffb

    -- Clamping mask for r: per RFC 8439 Section 2.5.1
    -- Bits cleared: top 4 bits of each 32-bit word except first,
    -- bottom 2 bits of each 32-bit word except first
    -- Mask: 0x0ffffffc_0ffffffc_0ffffffc_0fffffff
    constant CLAMP_MASK : std_logic_vector(127 downto 0) :=
        x"0ffffffc0ffffffc0ffffffc0fffffff";

    -- Clamp r key material: AND with mask, return as 130-bit
    function poly_clamp_r(r : std_logic_vector(127 downto 0)) return poly_word;

    -- Pad a message block: set bit at position 8*byte_count
    -- For full 16-byte blocks, byte_count=16 sets bit 128
    -- For partial blocks, byte_count < 16
    function poly_pad_block(
        blk_data   : std_logic_vector(127 downto 0);
        blk_bytes  : natural range 0 to 16
    ) return poly_word;

end package poly1305_pkg;

package body poly1305_pkg is

    function poly_clamp_r(r : std_logic_vector(127 downto 0)) return poly_word is
        variable clamped : std_logic_vector(127 downto 0);
    begin
        clamped := r and CLAMP_MASK;
        return unsigned("00" & clamped);
    end function;

    function poly_pad_block(
        blk_data   : std_logic_vector(127 downto 0);
        blk_bytes  : natural range 0 to 16
    ) return poly_word is
        variable result : poly_word;
    begin
        -- Start with the block data (zero-padded beyond blk_bytes by caller)
        result := unsigned("00" & blk_data);
        -- Set the padding bit at position 8*blk_bytes
        -- This places the 0x01 byte just after the last valid byte
        result(8 * blk_bytes) := '1';
        return result;
    end function;

end package body poly1305_pkg;
