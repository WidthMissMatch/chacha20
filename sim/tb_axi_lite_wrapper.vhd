-- Testbench for axi_lite_wrapper
-- Tests ChaCha20-Poly1305 encryption via AXI4-Lite register interface.
-- Test vector: RFC 8439 §2.4.2
--   Key:    00 01 02 ... 1F
--   Nonce:  00 00 00 00  00 00 00 4A  00 00 00 00
--   PT:     64 zero bytes
-- Expected ciphertext[0] = 0x22
-- Expected tag            = C6252E9A0A47711F9B0A26D9B516A4D1

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;

entity tb_axi_lite_wrapper is
end entity tb_axi_lite_wrapper;

architecture sim of tb_axi_lite_wrapper is

    -- Clock / reset
    signal clk    : std_logic := '0';
    signal resetn : std_logic := '0';

    -- AXI4-Lite signals
    signal awaddr  : std_logic_vector(8 downto 0) := (others => '0');
    signal awvalid : std_logic := '0';
    signal awready : std_logic;
    signal wdata   : std_logic_vector(31 downto 0) := (others => '0');
    signal wstrb   : std_logic_vector(3 downto 0)  := "1111";
    signal wvalid  : std_logic := '0';
    signal wready  : std_logic;
    signal bresp   : std_logic_vector(1 downto 0);
    signal bvalid  : std_logic;
    signal bready  : std_logic := '1';
    signal araddr  : std_logic_vector(8 downto 0) := (others => '0');
    signal arvalid : std_logic := '0';
    signal arready : std_logic;
    signal rdata   : std_logic_vector(31 downto 0);
    signal rresp   : std_logic_vector(1 downto 0);
    signal rvalid  : std_logic;
    signal rready  : std_logic := '1';

    constant CLK_PERIOD : time := 5 ns;   -- 200 MHz

    -- -----------------------------------------------------------------------
    -- BFM helpers
    -- -----------------------------------------------------------------------
    procedure axi_write(
        addr  : in integer;
        data  : in std_logic_vector(31 downto 0);
        signal awaddr_s  : out std_logic_vector(8 downto 0);
        signal awvalid_s : out std_logic;
        signal wdata_s   : out std_logic_vector(31 downto 0);
        signal wvalid_s  : out std_logic;
        signal awready_s : in  std_logic;
        signal wready_s  : in  std_logic;
        signal bvalid_s  : in  std_logic;
        signal clk_s     : in  std_logic
    ) is begin
        awaddr_s  <= std_logic_vector(to_unsigned(addr * 4, 9));
        awvalid_s <= '1';
        wdata_s   <= data;
        wvalid_s  <= '1';
        wait until rising_edge(clk_s) and awready_s = '1';
        awvalid_s <= '0';
        -- Keep wvalid HIGH until bvalid: the BFM fires at the sub-delta when awready
        -- is registered (rising_edge is still TRUE that time-step), so wvalid must remain
        -- asserted until the next clock edge where the slave latches aw_ready=1 & wvalid=1.
        wait until rising_edge(clk_s) and bvalid_s = '1';
        wvalid_s  <= '0';
        wait until rising_edge(clk_s);
    end procedure;

    procedure axi_read(
        addr   : in  integer;
        data   : out std_logic_vector(31 downto 0);
        signal araddr_s  : out std_logic_vector(8 downto 0);
        signal arvalid_s : out std_logic;
        signal arready_s : in  std_logic;
        signal rdata_s   : in  std_logic_vector(31 downto 0);
        signal rvalid_s  : in  std_logic;
        signal clk_s     : in  std_logic
    ) is begin
        araddr_s  <= std_logic_vector(to_unsigned(addr * 4, 9));
        arvalid_s <= '1';
        wait until rising_edge(clk_s) and arready_s = '1';
        arvalid_s <= '0';
        wait until rising_edge(clk_s) and rvalid_s = '1';
        data := rdata_s;
        wait until rising_edge(clk_s);
    end procedure;

begin

    -- Clock generation (200 MHz)
    clk <= not clk after CLK_PERIOD / 2;

    -- DUT
    dut: entity work.axi_lite_wrapper
        port map (
            s_axi_aclk    => clk,
            s_axi_aresetn => resetn,
            s_axi_awaddr  => awaddr,
            s_axi_awvalid => awvalid,
            s_axi_awready => awready,
            s_axi_wdata   => wdata,
            s_axi_wstrb   => wstrb,
            s_axi_wvalid  => wvalid,
            s_axi_wready  => wready,
            s_axi_bresp   => bresp,
            s_axi_bvalid  => bvalid,
            s_axi_bready  => bready,
            s_axi_araddr  => araddr,
            s_axi_arvalid => arvalid,
            s_axi_arready => arready,
            s_axi_rdata   => rdata,
            s_axi_rresp   => rresp,
            s_axi_rvalid  => rvalid,
            s_axi_rready  => rready
        );

    -- -----------------------------------------------------------------------
    -- Stimulus
    -- -----------------------------------------------------------------------
    process
        variable rd_data  : std_logic_vector(31 downto 0);
        variable status   : std_logic_vector(31 downto 0);
        variable ct0      : std_logic_vector(31 downto 0);
        variable tag0     : std_logic_vector(31 downto 0);
        variable timeout  : integer;
    begin
        -- Reset
        resetn <= '0';
        wait for 20 ns;
        resetn <= '1';
        wait for 10 ns;

        report "=== AXI Wrapper Test: RFC 8439 §2.4.2 ===";

        -- Write KEY = 00 01 02 ... 1F (8 x 32-bit words, little-endian)
        -- KEY[0] = word at bytes 0..3 = 0x03020100
        axi_write(8,  x"03020100", awaddr, awvalid, wdata, wvalid, awready, wready, bvalid, clk);
        axi_write(9,  x"07060504", awaddr, awvalid, wdata, wvalid, awready, wready, bvalid, clk);
        axi_write(10, x"0B0A0908", awaddr, awvalid, wdata, wvalid, awready, wready, bvalid, clk);
        axi_write(11, x"0F0E0D0C", awaddr, awvalid, wdata, wvalid, awready, wready, bvalid, clk);
        axi_write(12, x"13121110", awaddr, awvalid, wdata, wvalid, awready, wready, bvalid, clk);
        axi_write(13, x"17161514", awaddr, awvalid, wdata, wvalid, awready, wready, bvalid, clk);
        axi_write(14, x"1B1A1918", awaddr, awvalid, wdata, wvalid, awready, wready, bvalid, clk);
        axi_write(15, x"1F1E1D1C", awaddr, awvalid, wdata, wvalid, awready, wready, bvalid, clk);

        -- Write NONCE = 00 00 00 00  00 00 00 4A  00 00 00 00
        axi_write(16, x"00000000", awaddr, awvalid, wdata, wvalid, awready, wready, bvalid, clk);
        axi_write(17, x"4A000000", awaddr, awvalid, wdata, wvalid, awready, wready, bvalid, clk);
        axi_write(18, x"00000000", awaddr, awvalid, wdata, wvalid, awready, wready, bvalid, clk);

        -- Write PLAINTEXT = 64 zero bytes (already 0 from reset, but write anyway)
        for i in 0 to 15 loop
            axi_write(19 + i, x"00000000", awaddr, awvalid, wdata, wvalid, awready, wready, bvalid, clk);
        end loop;

        -- Trigger encryption: CTRL.bit0 = 1
        axi_write(0, x"00000001", awaddr, awvalid, wdata, wvalid, awready, wready, bvalid, clk);

        -- Poll STATUS until done (bit1 = 1), timeout after 50000 clocks
        timeout := 0;
        loop
            axi_read(1, status, araddr, arvalid, arready, rdata, rvalid, clk);
            exit when status(1) = '1';
            timeout := timeout + 1;
            if timeout > 50000 then
                report "TIMEOUT waiting for encryption done" severity failure;
            end if;
            wait for CLK_PERIOD;
        end loop;

        -- Read CIPHERTEXT[0] (word at offset 0x074 = register index 29)
        axi_read(29, ct0, araddr, arvalid, arready, rdata, rvalid, clk);

        -- Expected: ciphertext byte 0 = 0x22 -> ct0(7 downto 0) = x"22"
        if ct0(7 downto 0) = x"22" then
            report "PASSED: ciphertext[0] = 0x22";
        else
            report "FAILED: ciphertext[0] = 0x" &
                   to_hstring(ct0(7 downto 0)) &
                   " (expected 0x22)" severity error;
        end if;

        -- Read TAG[0] (register index 45, offset 0x0B4)
        axi_read(45, tag0, araddr, arvalid, arready, rdata, rvalid, clk);

        -- Expected tag[0..3] = C6252E9A (little-endian word) = 0x9A2E25C6
        if tag0 = x"9A2E25C6" then
            report "PASSED: tag[0] = 0x9A2E25C6";
        else
            report "FAILED: tag[0] = 0x" & to_hstring(tag0) &
                   " (expected 0x9A2E25C6)" severity error;
        end if;

        -- Check overall pass
        if ct0(7 downto 0) = x"22" and tag0 = x"9A2E25C6" then
            report "tb_axi_lite_wrapper: PASSED";
        else
            report "tb_axi_lite_wrapper: FAILED" severity error;
        end if;

        wait;
    end process;

end architecture sim;
