-- Poly1305 MAC Top-Level
-- FSM: IDLE -> CLAMP_R -> WAIT_BLOCK -> PROCESS_BLOCK -> FINALIZE -> DONE
-- Streams 16-byte message blocks, outputs 128-bit authentication tag
-- Per RFC 8439 Section 2.5

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.poly1305_pkg.all;

entity poly1305_mac is
    port (
        clk        : in  std_logic;
        rst        : in  std_logic;
        -- Key: r[127:0] || s[127:0] = 256 bits
        poly_key   : in  std_logic_vector(255 downto 0);
        -- Message block interface
        msg_block  : in  std_logic_vector(127 downto 0);
        msg_valid  : in  std_logic;  -- Block is valid
        msg_last   : in  std_logic;  -- Last block
        byte_count : in  std_logic_vector(4 downto 0);  -- Valid bytes (1-16)
        -- Output
        tag_out    : out std_logic_vector(127 downto 0);
        tag_valid  : out std_logic;
        ready      : out std_logic   -- Ready for next block
    );
end entity poly1305_mac;

architecture rtl of poly1305_mac is

    type fsm_state is (IDLE, CLAMP_R, WAIT_BLOCK, PROCESS_BLOCK,
                        WAIT_PROCESS, FINALIZE, DONE_STATE);
    signal state : fsm_state := IDLE;

    -- Internal registers
    signal r_clamped  : poly_word;
    signal s_key      : unsigned(127 downto 0);
    signal accumulator : poly_word;

    -- Block processor interface
    signal blk_acc_in   : poly_word;
    signal blk_block    : std_logic_vector(127 downto 0);
    signal blk_bytes    : natural range 0 to 16;
    signal blk_r        : poly_word;
    signal blk_start    : std_logic;
    signal blk_acc_out  : poly_word;
    signal blk_done     : std_logic;

    signal is_last      : std_logic;

begin

    -- Block processor
    block_proc: entity work.poly1305_block
        port map (
            clk        => clk,
            rst        => rst,
            acc_in     => blk_acc_in,
            block_in   => blk_block,
            byte_count => blk_bytes,
            r_clamped  => blk_r,
            start      => blk_start,
            acc_out    => blk_acc_out,
            done       => blk_done
        );

    blk_acc_in <= accumulator;
    blk_r      <= r_clamped;

    process(clk)
        variable tag_sum : unsigned(130 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state       <= IDLE;
                tag_valid   <= '0';
                ready       <= '0';
                blk_start   <= '0';
                accumulator <= (others => '0');
                is_last     <= '0';
            else
                tag_valid <= '0';
                blk_start <= '0';

                case state is
                    when IDLE =>
                        ready <= '0';
                        if msg_valid = '1' then
                            -- Latch key material
                            state <= CLAMP_R;
                        end if;

                    when CLAMP_R =>
                        -- r = key[127:0], s = key[255:128] (little-endian)
                        r_clamped   <= poly_clamp_r(poly_key(127 downto 0));
                        s_key       <= unsigned(poly_key(255 downto 128));
                        accumulator <= (others => '0');
                        -- Process the first block that triggered us
                        blk_block  <= msg_block;
                        blk_bytes  <= to_integer(unsigned(byte_count));
                        is_last    <= msg_last;
                        state      <= PROCESS_BLOCK;

                    when WAIT_BLOCK =>
                        ready <= '1';
                        if msg_valid = '1' then
                            blk_block <= msg_block;
                            blk_bytes <= to_integer(unsigned(byte_count));
                            is_last   <= msg_last;
                            ready     <= '0';
                            state     <= PROCESS_BLOCK;
                        end if;

                    when PROCESS_BLOCK =>
                        blk_start <= '1';
                        state     <= WAIT_PROCESS;

                    when WAIT_PROCESS =>
                        if blk_done = '1' then
                            accumulator <= blk_acc_out;
                            if is_last = '1' then
                                state <= FINALIZE;
                            else
                                state <= WAIT_BLOCK;
                            end if;
                        end if;

                    when FINALIZE =>
                        -- tag = (acc + s) mod 2^128  (simple truncation)
                        tag_sum := resize(accumulator, 131) + resize(s_key, 131);
                        tag_out <= std_logic_vector(tag_sum(127 downto 0));
                        state   <= DONE_STATE;

                    when DONE_STATE =>
                        tag_valid <= '1';
                        ready     <= '0';
                        state     <= IDLE;
                end case;
            end if;
        end if;
    end process;

end architecture rtl;
