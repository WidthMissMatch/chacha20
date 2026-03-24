-- Output Buffer
-- 512-bit to 8-bit width conversion with 8-entry FIFO
-- Accepts 512-bit words, outputs bytes sequentially (LSB first)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity output_buffer is
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;
        -- Write side (512-bit words)
        wr_data     : in  std_logic_vector(511 downto 0);
        wr_en       : in  std_logic;
        -- Read side (8-bit bytes)
        rd_data     : out std_logic_vector(7 downto 0);
        rd_en       : in  std_logic;
        rd_valid    : out std_logic;
        -- Status
        full        : out std_logic;
        empty       : out std_logic;
        almost_full : out std_logic
    );
end entity output_buffer;

architecture rtl of output_buffer is

    -- FIFO storage: 8 entries of 512 bits
    type fifo_array is array (0 to 7) of std_logic_vector(511 downto 0);
    signal fifo_mem : fifo_array;
    attribute ram_style : string;
    attribute ram_style of fifo_mem : signal is "block";

    signal wr_ptr   : unsigned(2 downto 0) := (others => '0');
    signal rd_ptr   : unsigned(2 downto 0) := (others => '0');
    signal count    : unsigned(3 downto 0) := (others => '0');  -- 0-8

    -- Width conversion
    signal shift_reg   : std_logic_vector(511 downto 0) := (others => '0');
    signal byte_cnt    : unsigned(5 downto 0) := (others => '0');  -- 0-63
    signal word_loaded : std_logic := '0';  -- A 512-bit word is loaded in shift_reg

    signal full_i  : std_logic;
    signal empty_i : std_logic;

begin

    full_i  <= '1' when count = 8 else '0';
    empty_i <= '1' when count = 0 and word_loaded = '0' else '0';

    full        <= full_i;
    empty       <= empty_i;
    almost_full <= '1' when count >= 6 else '0';

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                wr_ptr     <= (others => '0');
                rd_ptr     <= (others => '0');
                count      <= (others => '0');
                byte_cnt   <= (others => '0');
                word_loaded <= '0';
                rd_valid   <= '0';
                rd_data    <= (others => '0');
                shift_reg  <= (others => '0');
            else
                rd_valid <= '0';

                -- Write side: push 512-bit words into FIFO
                if wr_en = '1' and full_i = '0' then
                    fifo_mem(to_integer(wr_ptr)) <= wr_data;
                    wr_ptr <= wr_ptr + 1;
                    count  <= count + 1;
                end if;

                -- Read side: output bytes from shift register
                if rd_en = '1' then
                    if word_loaded = '1' then
                        -- Output current byte (LSB first)
                        rd_data  <= shift_reg(7 downto 0);
                        rd_valid <= '1';
                        if byte_cnt = to_unsigned(63, 6) then
                            -- Exhausted current word
                            word_loaded <= '0';
                            byte_cnt    <= (others => '0');
                        else
                            shift_reg <= x"00" & shift_reg(511 downto 8);
                            byte_cnt  <= byte_cnt + 1;
                        end if;
                    elsif count > 0 then
                        -- Pop next word from FIFO and output first byte
                        shift_reg   <= fifo_mem(to_integer(rd_ptr));
                        rd_data     <= fifo_mem(to_integer(rd_ptr))(7 downto 0);
                        rd_valid    <= '1';
                        shift_reg   <= x"00" & fifo_mem(to_integer(rd_ptr))(511 downto 8);
                        byte_cnt    <= to_unsigned(1, 6);
                        word_loaded <= '1';
                        rd_ptr      <= rd_ptr + 1;
                        count       <= count - 1;
                        -- Adjust count if simultaneous write
                        if wr_en = '1' and full_i = '0' then
                            count <= count;  -- +1 -1 = no change
                        end if;
                    end if;
                elsif word_loaded = '0' and count > 0 then
                    -- Auto-load next word from FIFO (no read requested yet)
                    shift_reg   <= fifo_mem(to_integer(rd_ptr));
                    word_loaded <= '1';
                    byte_cnt    <= (others => '0');
                    rd_ptr      <= rd_ptr + 1;
                    count       <= count - 1;
                    if wr_en = '1' and full_i = '0' then
                        count <= count;
                    end if;
                end if;
            end if;
        end if;
    end process;

end architecture rtl;
