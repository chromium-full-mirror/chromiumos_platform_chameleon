# Chameleon v3 FPGA register map

## Overview
This document describes the FPGA register map of the Chameleon v3 FPGA implementation.
It’s valid and up to date with Chameleon v3 MP build.
Chameleon v3 uses Arria10 SX FPGA family to implement the logic.
SX means that along with the FPGA, the chip includes Hard Processor Subsystem
(HPS) which allows accessing FPGA resources directly from this subsystem.
All FPGA address space is a subset of [SoC-to-FPGA address space](https://www.intel.com/content/www/us/en/programmable/hps/arria-10/hps.html#topic/sfo1429889289369.html).
All registers are 32-bit wide. Register fields marked as “Reserved” shall be
accessed by software only in read-modify-write manner.

## Register groups
The register groups of particular FPGA subsystems are shown below. The registers with following prefixes:
* i2s_*
* fb_*
* irq_*
* ap_port*

share the same bit-field layout (presented in next chapters of this document).

| Register group name  | Registers       | Start address | End address|
|----------------------|-----------------|---------------|------------|
| AP_CONFIG            |                 |               |            |
|                      | ap_config       | 0xC0060000    | 0xC00600FF |
| AP_PORT              |                 |               |            |
|                      | ap_port0        | 0xC0060100    | 0xC00601FF |
|                      | ap_port1        | 0xC0060200    | 0xC00602FF |
| I2S                  |                 |               |            |
|                      | i2s_it          | 0xC0060300    | 0xC00603FF |
|                      | i2s_ssm         | 0xC0060400    | 0xC00604FF |
|                      | i2s_dp_mst0     | 0xC0061100    | 0xC00611FF |
|                      | i2s_dp_mst1     | 0xC0061200    | 0xC00612FF |
|                      | i2s_dp_mst2     | 0xC0061300    | 0xC00613FF |
|                      | i2s_dp_mst3     | 0xC0061400    | 0xC00614FF |
|                      | i2s_dp_sst      | 0xC0061500    | 0xC00615FF |
| FB                   |                 |               |            |
|                      | fb_it           | 0xC0060500    | 0xC00605FF |
|                      | fb_dp_mst0      | 0xC0060600    | 0xC00606FF |
|                      | fb_dp_mst1      | 0xC0060700    | 0xC00607FF |
|                      | fb_dp_mst2      | 0xC0060800    | 0xC00608FF |
|                      | fb_dp_mst3      | 0xC0060900    | 0xC00609FF |
|                      | fb_dp_sst       | 0xC0060A00    | 0xC0060AFF |
| IRQ                  |                 |               |            |
|                      | irq_i2s_it      | 0xC0060F00    | 0xC0060F0F |
|                      | irq_i2s_ssm     | 0xC0060F10    | 0xC0060F1F |
|                      | irq_fb_it       | 0xC0060F20    | 0xC0060F2F |
|                      | irq_fb_dp_mst0  | 0xC0060F30    | 0xC0060F3F |
|                      | irq_fb_dp_mst1  | 0xC0060F40    | 0xC0060F4F |
|                      | irq_fb_dp_mst2  | 0xC0060F50    | 0xC0060F5F |
|                      | irq_fb_dp_mst3  | 0xC0060F60    | 0xC0060F6F |
|                      | irq_fb_dp_sst   | 0xC0060F70    | 0xC0060F7F |
|                      | irq_dp_mgmt_mst | 0xC0060F80    | 0xC0060F8F |
|                      | irq_i2s_dp_mst0 | 0xC0060F90    | 0xC0060F9F |
|                      | irq_i2s_dp_mst1 | 0xC0060FA0    | 0xC0060FAF |
|                      | irq_i2s_dp_mst2 | 0xC0060FB0    | 0xC0060FBF |
|                      | irq_i2s_dp_mst3 | 0xC0060FC0    | 0xC0060FCF |
|                      | irq_i2s_dp_sst  | 0xC0060FD0    | 0xC0060FDF |
|                      | irq_dp_mgmt_sst | 0xC0060FE0    | 0xC0060FEF |
| DP_MGMT              |                 |               |            |
|                      | dp_mgmt_mst     | 0xC0062000    | 0xC0063FFF |
|                      | dp_mgmt_sst     | 0xC0064000    | 0xC0065FFF |

## AP_CONFIG registers
| Register name | Access | Address offset | Description |
|---------------|--------|----------------|-------------|
| CFG_GUID      | RO     | 0x0            | Global unique identifier of the FPGA bitstream. Contains 4 bytes of the Gerrit Change-Id tag from which a given bitstream was built. |
| CFG_CHIP_ID   | RO     | 0x4            | [15:0]: Chip register model, available values: 270, 480<br>[23:16]: Chip speed grade, available values: 2,3 |

## AP_PORT registers
This register set applies to following register groups:
* ap_port0
* ap_port1

RTL source:
* port_registers.sv
* port_registers_pkg.sv

| Register name | Access | Address | Description |
|---------------|--------|---------|-------------|
| port_id       | RO     | 0x0     | Reserved    |
| vid_status    | RO     | 0x4     | [1:0]: Sink type, values:<br> 0 - DisplayPort MST<br> 1 - HDMI<br> 2 - DisplayPort SST<br> 3 - reserved<br>[5:2]: Overflow indication of given channel. For HDMI/DisplayPort SST, only [2] bit is valid. |

## I2S registers
This register set applies to following register groups:
* i2s_it
* i2s_ssm
* i2s_dp_mst0
* i2s_dp_mst1
* i2s_dp_mst2
* i2s_dp_mst3
* I2s_dp_sst

RTL source:
* i2s_registers.sv
* i2s_registers_pkg.sv

| Register name  | Access | Address | Description |
|----------------|--------|---------|-------------|
| tx_enable      | RW     | 0x0     | [0]: Enable TX path. Shall be set only after tx_base_addr, tx_buffer_size and tx_prod_idx were configured. Has effect only in the i2s_ssm module where TX path is available.<br>[31:1]: Reserved |
| tx_base_addr   | RW     | 0x4     | Physical base address of TX ring buffer. Has effect only in the i2s_ssm module where TX path is available. |
| tx_buffer_size | RW     | 0x8     | Buffer size of TX ring buffer. Value must be a power of two. Value in bytes. Has effect only in the i2s_ssm module where TX path is available. |
| tx_prod_idx    | RW     | 0xC     | Producer index for ring buffer. Has effect only in the i2s_ssm module where TX path is available. |
| tx_cons_idx    | RO     | 0x10    | Consumer index updated by hardware. Fully controlled by hardware, RO for software. Has effect only in the i2s_ssm module where TX path is available. |
| rx_enable      | RW     | 0x14    | [0]: Enable RX path.<br>[31:1]: Reserved |
| rx_base_addr   | RW     | 0x18    | Physical base address of RX ring buffer. Shall be set only after rx_base_addr, rx_buffer_size and rx_cons_idx were configured. |
| rx_buffer_size | RW     | 0x1C    | Buffer size of RX ring buffer.  Value must be a power of two. Value in bytes. |
| rx_prod_idx    | RO     | 0x20    | Producer index for ring buffer. Ring is full when (assuming rx_cons_idx = 0):<br><br>rx_prod_idx = rx_buffer_size - 8<br><br>Fully controlled by hardware, RO for software. |
| rx_cons_idx    | RW     | 0x24    | Consumer index updated by software. |
| error          | RO     | 0x28    | [0]: Overflow<br>[31:1]: Reserved |
| soft_reset     | WO     | 0x2C    | [0]: Reset RX path.<br>[1]: Reset TX path.<br>[31:2]: Reserved |
| config_const   | RO     | 0x30    | [7:0] Number of supported channels.<br>[31:8]: Reserved. |
| rx_irq         | RW     | 0x4C    | [0]: Enable interrupt<br>[7:1]: Reserved<br>[31:8]: Frames count - module generates interrupt after receiving given number of frames |
| rx_irq_const   | RO     | 0x50    | [7:0]: Frame size in bytes<br>[31:8]: Reserved |
| tx_irq         | RW     | 0x54    | [0]: Enable interrupt<br>[7:1]: Reserved<br>[31:8]: Frames count - module generates interrupt after receiving given number of frames |
| tx_irq_const   | RO     | 0x58    | [7:0]: Frame size in bytes<br>[23:8]: Bytes to fetch - how many bytes are fetched from the ring in single AXI transaction<br>[31:24]: Reserved |

## FB registers
This register set applies to following register groups:
* fb_it
* fb_dp_mst0
* fb_dp_mst1
* fb_dp_mst2
* fb_dp_mst3
* fb_dp_sst

RTL source:
* framebuffer_registers.sv
* framebuffer_registers_pkg.sv

| Register name       | Access | Address | Description |
|---------------------|--------|---------|-------------|
| en                  | RW     | 0x0     | [0]: Enable framebuffer processing. Shall be set only after:<br>* reading height and width<br>* setting buffer_size according to dim_height and dim_width,<br>* setting dma_format |
| height              | RO     | 0x4     | [13:0]: Height of image, in pixels count. |
| width               | RO     | 0x8     | [13:0]: Width of image, in pixels count. |
| buffer_addr_a       | RW     | 0xC     | Physical address of buffer where frame N shall be stored. Framebuffer module generates an interrupt after receiving the whole frame. Interrupt status contains the index of the buffer (A = 0, B = 1). |
| buffer_addr_b       | RW     | 0x10    | Physical address of buffer where frame N+1 shall be stored. Framebuffer module generates an interrupt after receiving the whole frame. Interrupt status contains the index of the buffer (A = 0, B = 1). |
| buffer_size         | RW     | 0x14    | Size of each of two buffers (BUFFER_A, BUFFER_B). Value in bytes. |
| reset_from_register | RW     | 0x18    | [0]: Reset framebuffer module.<br>[31:1]: Reserved. |
| errors              | RO     | 0x1C    | [0]: Overflow of DMA FIFO - value of 1 means that FSDRAM interfaces of HPS couldn’t handle traffic. Set reset_from_register[0] to recover from this state.<br>[1]: Adapter error - value of 1 means that path prior to clock-domain-crossing occurred overflow. Set reset_from_register[0] to recover from this state. |
| io_color            | RW     | 0x20    | Has effect only in the fb_it register set. Specific to IT68051 chip. Ignored in other modules. <br>IO color depth. Values:<br>0 - 24bpp (bits per pixel)<br>1 - 30bpp (bits per pixel)<br><br>Has to be set to the exact same parameters as the IT68051 chip was configured. |
| data_rate           | RW     | 0x24    | Has effect only in the fb_it register set. Specific to IT68051 chip. Ignored in other modules.<br>IO data rate. Values:<br>0 - single data rate<br>1- double data rate<br><br>Has to be set to the exact same parameters as the IT68051 chip was configured. |
| pixel_mode          | RW     | 0x28    | Has effect only in the fb_it register set. Specific to IT68051 chip. Ignored in other modules.<br>IO pixel rate. Values:<br>0 - single pixel mode<br>1- double pixel mode<br><br>Has to be set to the exact same parameters as the IT68051 chip was configured. |
| sync_polarity       | RW     | 0x2C    | Has effect only in the fb_it register set. Specific to IT68051 chip. Ignored in other modules.<br>[0]: Force inverted hsync polarity<br>[1]: Force inverted vsync polarity<br>[2]: Polarity state, values:<br>  0 - framebuffer module automatically detects polarity of VSYNC/HSYNC signals  <br>  1 - framebuffer uses values from sync_polarity[0] and sync_polarity[1] to invert polarity of SYNC signals regardless of the detection algorithm - user is able to force given polarity. |
| dma_format          | WO     | 0x30    | [2:0] Format of frame stored in host memory. Values:<br> 0 - 8bpc (bits per color), no padding<br> 1 - 10bpc (bits per color), aligned to 48bits, formatted as follows:<br>R[9:0], R_PAD[15:10]<br>G[25:16], G_PAD[31:26]<br>B[41:32], B_PAD[47:42], <br><br>where x_PAD is zeroed. Such format is later called UpperPadding.<br><br> 2 - 10bpc (bits per color), aligned to 48bits, formatted as follows:<br><br>R_PAD[5:0], R[15:6]<br>G_PAD[21:16], G[31:22]<br>B_PAD[37:32], B[47:38], <br>where x_PAD is zeroed. Such format is later called LowerPadding.<br> 3 - 12bpc aligned to 48bits with UpperPadding<br> 4 - 12bpc aligned to 48bits with LowerPadding<br> 5 - 16bpc (48bits total)<br> 6 - Raw format, aligned to 48bits<br> 7 - 8bpc legacy format. Has to be set for IT68051. |
| version             | RO     | 0x34    | Framebuffer module version. Const value to identify by software driver. Value: 0xc0fb0001 |

## IRQ registers

This register set applies to following register groups:
* irq_i2s_it
* irq_i2s_ssm
* irq_fb_it
* irq_fb_dp_mst0
* irq_fb_dp_mst1
* irq_fb_dp_mst2
* irq_fb_dp_mst3
* irq_fb_dp_sst
* irq_dp_mgmt_mst
* irq_i2s_dp_mst0
* irq_i2s_dp_mst1
* irq_i2s_dp_mst2
* irq_i2s_dp_mst3
* irq_i2s_dp_sst
* irq_dp_mgmt_sst

For details about the register map, please refer to the [PIO Intel FPGA IP register map](https://www.intel.com/content/www/us/en/docs/programmable/683130/21-4/register-map-33025.html).

## DP_MGMT registers

This register set applies to following register groups:
* dp_mgmt_sst
* dp_mgmt_mst

For details about the register map, please refer to [DisplayPort FPGA IP register map](https://www.intel.com/content/www/us/en/docs/programmable/683273/22-3-20-0-1/displayport-sink-register-map-and-dpcd.html).
