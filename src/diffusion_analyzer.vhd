-- Diffusion Analyzer (simulation-only)
-- Computes avalanche coefficient: Hamming distance / 512 for each round
-- Latches reference state when round_num=0
-- avalanche_coeff is Q16.16 fixed-point: count * 2^16 / 512 = count << 7
-- VHDL-2008

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity diffusion_analyzer is
    port (
        clk             : in  std_logic;
        rst             : in  std_logic;
        state_round_in  : in  std_logic_vector(511 downto 0);
        round_num       : in  unsigned(3 downto 0);
        avalanche_coeff : out unsigned(31 downto 0);  -- Q16.16 fixed-point
        influence_valid : out std_logic
    );
end entity diffusion_analyzer;

architecture rtl of diffusion_analyzer is

    signal reference_state : std_logic_vector(511 downto 0) := (others => '0');
    signal prev_round_num  : unsigned(3 downto 0) := (others => '0');

begin

    process(clk)
        variable xor_result    : std_logic_vector(511 downto 0);
        variable hamming_count : unsigned(9 downto 0);  -- max 512
    begin
        if rising_edge(clk) then
            if rst = '1' then
                reference_state <= (others => '0');
                prev_round_num  <= (others => '0');
                avalanche_coeff <= (others => '0');
                influence_valid <= '0';
            else
                influence_valid <= '0';
                prev_round_num  <= round_num;

                if round_num = to_unsigned(0, 4) then
                    -- Latch reference state at round 0
                    reference_state <= state_round_in;

                elsif round_num /= prev_round_num and round_num > to_unsigned(0, 4) then
                    -- New round detected, compute Hamming distance
                    xor_result := state_round_in xor reference_state;

                    -- Popcount: count set bits in 512-bit XOR result
                    hamming_count := (others => '0');
                    for i in 0 to 511 loop
                        if xor_result(i) = '1' then
                            hamming_count := hamming_count + 1;
                        end if;
                    end loop;

                    -- Convert to Q16.16: coeff = count/512 * 2^16 = count * 128 = count << 7
                    avalanche_coeff <= resize(hamming_count & "0000000", 32);
                    influence_valid <= '1';
                end if;
            end if;
        end if;
    end process;

end architecture rtl;
