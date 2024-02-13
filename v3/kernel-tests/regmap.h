struct reg ap_config_regs[] = {
	{ "cfg_guid",    0x0 },
	{ "cfg_chip_id", 0x4 },
	{ },
};

struct reg ap_port_regs[] = {
	{ "port_id",    0x0 },
	{ "vid_status", 0x4 },
	{ },
};

struct reg i2s_regs[] = {
	{ "tx_enable",      0x0 },
	{ "tx_base_addr",   0x4 },
	{ "tx_buffer_size", 0x8 },
	{ "tx_prod_idx",    0xc },
	{ "tx_cons_idx",    0x10 },
	{ "rx_enable",      0x14 },
	{ "rx_base_addr",   0x18 },
	{ "rx_buffer_size", 0x1c },
	{ "rx_prod_idx",    0x20 },
	{ "rx_cons_idx",    0x24 },
	{ "error",          0x28 },
	{ "soft_reset",     0x2c },
	{ "config_const",   0x30 },
	{ "rx_irq",         0x4c },
	{ "rx_irq_const",   0x50 },
	{ "tx_irq",         0x54 },
	{ "tx_irq_const",   0x58 },
	{ },
};

struct reg fb_regs[] = {
	{ "en",            0x00 },
	{ "height",        0x04, MODE_DEC },
	{ "width",         0x08, MODE_DEC },
	{ "buffer_addr_a", 0x0c },
	{ "buffer_addr_b", 0x10 },
	{ "buffer_size",   0x14, MODE_DEC },
	{ "reset_from_register", 0x18 },
	{ "errors",        0x1c },
	{ "io_color",      0x20 },
	{ "data_rate",     0x24 },
	{ "pixel_mode",    0x28 },
	{ "sync_polarity", 0x2c },
	{ "dma_format",    0x30 },
	{ "version",       0x34 },
	{ },
};

struct reg irq_regs[] = {
	{ "mask",  0x8 },
	{ "clear", 0xc },
	{ },
};

#define DPRX_SHIFT 2

struct reg dprx_regs[] = {
	{ "dprx_rx_control",  0x00 << DPRX_SHIFT },
	{ "dprx_rx_status",   0x01 << DPRX_SHIFT },
	{ "dprx_ber_control", 0x02 << DPRX_SHIFT },
	{ "dprx_ber_cnt0",    0x03 << DPRX_SHIFT },
	{ "dprx_ber_cnt1",    0x04 << DPRX_SHIFT },
	{ "dprx_timestamp",   0x05 << DPRX_SHIFT },
	{ "dprx_ber_cnti0",   0x06 << DPRX_SHIFT },
	{ "dprx_ber_cnti1",   0x07 << DPRX_SHIFT },
	{ "dprx_fec_config",  0x09 << DPRX_SHIFT },
	{ "dprx_fec_error_count",  0x0a << DPRX_SHIFT },
	{ "dprx_ber_test_pattern", 0x0b << DPRX_SHIFT },

#define DPRX_MSA_REGS(idx, base) \
	{ "dprx" #idx "_msa_mvid",    ((base) + 0x0) << DPRX_SHIFT, MODE_DEC }, \
	{ "dprx" #idx "_msa_nvid",    ((base) + 0x1) << DPRX_SHIFT, MODE_DEC }, \
	{ "dprx" #idx "_msa_htotal",  ((base) + 0x2) << DPRX_SHIFT, MODE_DEC }, \
	{ "dprx" #idx "_msa_vtotal",  ((base) + 0x3) << DPRX_SHIFT, MODE_DEC }, \
	{ "dprx" #idx "_msa_hsp",     ((base) + 0x4) << DPRX_SHIFT }, \
	{ "dprx" #idx "_msa_hsw",     ((base) + 0x5) << DPRX_SHIFT, MODE_DEC }, \
	{ "dprx" #idx "_msa_hstart",  ((base) + 0x6) << DPRX_SHIFT, MODE_DEC }, \
	{ "dprx" #idx "_msa_vstart",  ((base) + 0x7) << DPRX_SHIFT, MODE_DEC }, \
	{ "dprx" #idx "_msa_vsp",     ((base) + 0x8) << DPRX_SHIFT }, \
	{ "dprx" #idx "_msa_vsw",     ((base) + 0x9) << DPRX_SHIFT, MODE_DEC }, \
	{ "dprx" #idx "_msa_hwidth",  ((base) + 0xa) << DPRX_SHIFT, MODE_DEC }, \
	{ "dprx" #idx "_msa_vheight", ((base) + 0xb) << DPRX_SHIFT, MODE_DEC }, \
	{ "dprx" #idx "_msa_misc0",   ((base) + 0xc) << DPRX_SHIFT }, \
	{ "dprx" #idx "_msa_misc1",   ((base) + 0xd) << DPRX_SHIFT }, \
	{ "dprx" #idx "_msa_color",   ((base) + 0xe) << DPRX_SHIFT }, \
	{ "dprx" #idx "_vbid",        ((base) + 0xf) << DPRX_SHIFT }

#define DPRX_AUD_REGS(idx, base) \
	{ "dprx" #idx "_aud_maud", ((base) + 0x0) << DPRX_SHIFT }, \
	{ "dprx" #idx "_aud_naud", ((base) + 0x1) << DPRX_SHIFT }, \
	{ "dprx" #idx "_aud_aif0", ((base) + 0x2) << DPRX_SHIFT }, \
	{ "dprx" #idx "_aud_aif1", ((base) + 0x3) << DPRX_SHIFT }, \
	{ "dprx" #idx "_aud_aif2", ((base) + 0x4) << DPRX_SHIFT }, \
	{ "dprx" #idx "_aud_aif3", ((base) + 0x5) << DPRX_SHIFT }, \
	{ "dprx" #idx "_aud_aif4", ((base) + 0x6) << DPRX_SHIFT }

	DPRX_MSA_REGS(0, 0x20),
	DPRX_AUD_REGS(0, 0x30),
	DPRX_MSA_REGS(1, 0x40),
	DPRX_AUD_REGS(1, 0x50),
	DPRX_MSA_REGS(2, 0x60),
	DPRX_AUD_REGS(2, 0x70),
	DPRX_MSA_REGS(3, 0x80),
	DPRX_AUD_REGS(3, 0x90),

	{ "dprx_mst_control1", 0xa0 << DPRX_SHIFT },
	{ "dprx_mst_status1",  0xa1 << DPRX_SHIFT },
	{ "dprx_mst_vcptab0",  0xa2 << DPRX_SHIFT },
	{ "dprx_mst_vcptab1",  0xa3 << DPRX_SHIFT },
	{ "dprx_mst_vcptab2",  0xa4 << DPRX_SHIFT },
	{ "dprx_mst_vcptab3",  0xa5 << DPRX_SHIFT },
	{ "dprx_mst_vcptab4",  0xa6 << DPRX_SHIFT },
	{ "dprx_mst_vcptab5",  0xa7 << DPRX_SHIFT },
	{ "dprx_mst_vcptab6",  0xa8 << DPRX_SHIFT },
	{ "dprx_mst_vcptab7",  0xa9 << DPRX_SHIFT },

	{ "dprx_aux_control", 0x100 << DPRX_SHIFT },
	{ "dprx_aux_status",  0x101 << DPRX_SHIFT },
	{ "dprx_aux_command", 0x102 << DPRX_SHIFT },
	{ "dprx_aux_byte0",   0x103 << DPRX_SHIFT },
	{ "dprx_aux_byte1",   0x104 << DPRX_SHIFT },
	{ "dprx_aux_byte2",   0x105 << DPRX_SHIFT },
	{ "dprx_aux_byte3",   0x106 << DPRX_SHIFT },
	{ "dprx_aux_byte4",   0x107 << DPRX_SHIFT },
	{ "dprx_aux_byte5",   0x108 << DPRX_SHIFT },
	{ "dprx_aux_byte6",   0x109 << DPRX_SHIFT },
	{ "dprx_aux_byte7",   0x10a << DPRX_SHIFT },
	{ "dprx_aux_byte8",   0x10b << DPRX_SHIFT },
	{ "dprx_aux_byte9",   0x10c << DPRX_SHIFT },
	{ "dprx_aux_byte10",  0x10d << DPRX_SHIFT },
	{ "dprx_aux_byte11",  0x10e << DPRX_SHIFT },
	{ "dprx_aux_byte12",  0x10f << DPRX_SHIFT },
	{ "dprx_aux_byte13",  0x110 << DPRX_SHIFT },
	{ "dprx_aux_byte14",  0x111 << DPRX_SHIFT },
	{ "dprx_aux_byte15",  0x112 << DPRX_SHIFT },
	{ "dprx_aux_byte16",  0x113 << DPRX_SHIFT },
	{ "dprx_aux_byte17",  0x114 << DPRX_SHIFT },
	{ "dprx_aux_byte18",  0x115 << DPRX_SHIFT },
	{ "dprx_aux_i2c0",    0x116 << DPRX_SHIFT },
	{ "dprx_aux_i2c1",    0x117 << DPRX_SHIFT },
	{ "dprx_aux_reset",   0x118 << DPRX_SHIFT },
	{ "dprx_aux_hpd",     0x119 << DPRX_SHIFT },

	{ "dprx0_crc_r", 0x120 << DPRX_SHIFT },
	{ "dprx0_crc_g", 0x121 << DPRX_SHIFT },
	{ "dprx0_crc_b", 0x122 << DPRX_SHIFT },
	{ "dprx1_crc_r", 0x123 << DPRX_SHIFT },
	{ "dprx1_crc_g", 0x124 << DPRX_SHIFT },
	{ "dprx1_crc_b", 0x125 << DPRX_SHIFT },
	{ "dprx2_crc_r", 0x126 << DPRX_SHIFT },
	{ "dprx2_crc_g", 0x127 << DPRX_SHIFT },
	{ "dprx2_crc_b", 0x128 << DPRX_SHIFT },
	{ "dprx3_crc_r", 0x129 << DPRX_SHIFT },
	{ "dprx3_crc_g", 0x12a << DPRX_SHIFT },
	{ "dprx3_crc_b", 0x12b << DPRX_SHIFT },

	{ },
};

struct regmap regmaps[] = {
	{ "ap_config", ap_config_regs, 0xc0060000, 0x100 },

	{ "ap_port0", ap_port_regs, 0xc0060100, 0x100 },
	{ "ap_port1", ap_port_regs, 0xc0060200, 0x100 },

	{ "i2s_it",      i2s_regs, 0xc0060300, 0x100 },
	{ "i2s_ssm",     i2s_regs, 0xc0060400, 0x100 },
	{ "i2s_dp_mst0", i2s_regs, 0xc0061100, 0x100 },
	{ "i2s_dp_mst1", i2s_regs, 0xc0061200, 0x100 },
	{ "i2s_dp_mst2", i2s_regs, 0xc0061300, 0x100 },
	{ "i2s_dp_mst3", i2s_regs, 0xc0061400, 0x100 },
	{ "i2s_dp_sst",  i2s_regs, 0xc0061500, 0x100 },

	{ "fb_it",      fb_regs, 0xc0060500, 0x100 },
	{ "fb_dp_mst0", fb_regs, 0xc0060600, 0x100 },
	{ "fb_dp_mst1", fb_regs, 0xc0060700, 0x100 },
	{ "fb_dp_mst2", fb_regs, 0xc0060800, 0x100 },
	{ "fb_dp_mst3", fb_regs, 0xc0060900, 0x100 },
	{ "fb_dp_sst",  fb_regs, 0xc0060a00, 0x100 },

	{ "irq_i2s_it",      irq_regs, 0xc0060f00, 0x10 },
	{ "irq_i2s_ssm",     irq_regs, 0xc0060f10, 0x10 },
	{ "irq_fb_it",       irq_regs, 0xc0060f20, 0x10 },
	{ "irq_fb_dp_mst0",  irq_regs, 0xc0060f30, 0x10 },
	{ "irq_fb_dp_mst1",  irq_regs, 0xc0060f40, 0x10 },
	{ "irq_fb_dp_mst2",  irq_regs, 0xc0060f50, 0x10 },
	{ "irq_fb_dp_mst3",  irq_regs, 0xc0060f60, 0x10 },
	{ "irq_fb_dp_sst",   irq_regs, 0xc0060f70, 0x10 },
	{ "irq_dp_mgmt_mst", irq_regs, 0xc0060f80, 0x10 },
	{ "irq_i2s_dp_mst0", irq_regs, 0xc0060f90, 0x10 },
	{ "irq_i2s_dp_mst1", irq_regs, 0xc0060fa0, 0x10 },
	{ "irq_i2s_dp_mst2", irq_regs, 0xc0060fb0, 0x10 },
	{ "irq_i2s_dp_mst3", irq_regs, 0xc0060fc0, 0x10 },
	{ "irq_i2s_dp_sst",  irq_regs, 0xc0060fd0, 0x10 },
	{ "irq_dp_mgmt_sst", irq_regs, 0xc0060fe0, 0x10 },

	{ "dp_mgmt_mst", dprx_regs, 0xc0062000, 0x2000 },
	{ "dp_mgmt_sst", dprx_regs, 0xc0064000, 0x2000 },

	{ },
};
