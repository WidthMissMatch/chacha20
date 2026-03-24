# ZCU106 Evaluation Board Constraints for ChaCha20-Poly1305
# Board: Xilinx ZCU106 (xczu7ev-ffvc1156-2-e)
# NOTE: Update chacha20_top generic CLK_FREQ to 125_000_000 for board deployment

# ==============================================================================
# Clock — 200 MHz target clock (P6 stretch goal; ZCU106 deployment uses 125 MHz -> period 8.000)
# ==============================================================================
set_property PACKAGE_PIN AH18 [get_ports clk]
set_property IOSTANDARD LVDS [get_ports clk]
create_clock -period 5.000 -name sys_clk [get_ports clk]

# ==============================================================================
# Reset — Active-low push button (GPIO_SW_C, center button)
# ==============================================================================
set_property PACKAGE_PIN AG13 [get_ports rst_n]
set_property IOSTANDARD LVCMOS18 [get_ports rst_n]
set_false_path -from [get_ports rst_n]

# ==============================================================================
# UART — PMOD J55 Header (directly under PL, VCCO 3.3V bank)
#   Pin 1 (J55.1) = UART RX (FPGA input)
#   Pin 2 (J55.2) = UART TX (FPGA output)
# ==============================================================================
set_property PACKAGE_PIN A20 [get_ports uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx]

set_property PACKAGE_PIN B20 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]

# ==============================================================================
# Status LEDs — 4 GPIO LEDs on ZCU106
#   LED0 = RX activity
#   LED1 = Encryption in progress
#   LED2 = Poly1305 in progress
#   LED3 = Heartbeat (~1.5 Hz)
# ==============================================================================
set_property PACKAGE_PIN AL11 [get_ports {led_status[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {led_status[0]}]

set_property PACKAGE_PIN AL13 [get_ports {led_status[1]}]
set_property IOSTANDARD LVCMOS18 [get_ports {led_status[1]}]

set_property PACKAGE_PIN AK13 [get_ports {led_status[2]}]
set_property IOSTANDARD LVCMOS18 [get_ports {led_status[2]}]

set_property PACKAGE_PIN AE15 [get_ports {led_status[3]}]
set_property IOSTANDARD LVCMOS18 [get_ports {led_status[3]}]

# ==============================================================================
# SPI — PMOD J87 Header (for QRNG interface)
#   Pin 1 = SPI SCLK (FPGA output)
#   Pin 2 = SPI MOSI (FPGA output)
#   Pin 3 = SPI MISO (FPGA input)
#   Pin 4 = SPI CS_N (FPGA output)
# ==============================================================================
set_property PACKAGE_PIN D20 [get_ports spi_sclk]
set_property IOSTANDARD LVCMOS33 [get_ports spi_sclk]

set_property PACKAGE_PIN E20 [get_ports spi_mosi]
set_property IOSTANDARD LVCMOS33 [get_ports spi_mosi]

set_property PACKAGE_PIN D22 [get_ports spi_miso]
set_property IOSTANDARD LVCMOS33 [get_ports spi_miso]

set_property PACKAGE_PIN E22 [get_ports spi_cs_n]
set_property IOSTANDARD LVCMOS33 [get_ports spi_cs_n]
