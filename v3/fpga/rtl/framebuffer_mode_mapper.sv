/*
 * Copyright 2021 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

// Pixel mapper from various it68051 formats
// (spm(mode-1)/dpm/sdr/ddr/12-bit/15-bit/18-bit/24-bit/30-bit/36-bit)
// combinatorial block

module framebuffer_mode_mapper (
    input  framebuffer_registers_pkg::color_depth_e color_depth,
    input  framebuffer_registers_pkg::data_rate_e   ddr,
    input  framebuffer_registers_pkg::pixel_mode_e  dpm,
    input  framebuffer_pkg::io_map_t                input_word,
    output framebuffer_pkg::pixel_word_t            repacked
);

  import framebuffer_registers_pkg::*;

  always_comb begin
    repacked.pixel = '0;

    unique case ({dpm, ddr, color_depth})
      // TODO: {kSpm, kSdr, k36b}: repacked =
      // TODO: {kSpm, kDdr, k36b}: repacked =
      {kSpm, kSdr, k30b}: begin
        repacked.pixel[0] = { 2'b0,
                              input_word.spm_sdr_30b.bits.r,
                              input_word.spm_sdr_30b.bits.g,
                              input_word.spm_sdr_30b.bits.b
                            };
      end
      {kSpm, kSdr, k24b}: begin
        repacked.pixel[0] = { 8'b0,
                              input_word.spm_sdr_24b.bits.r,
                              input_word.spm_sdr_24b.bits.g,
                              input_word.spm_sdr_24b.bits.b
                            };
      end
      {kSpm, kDdr, k30b}: begin
        repacked.pixel[0] = { 2'b0,
                              input_word.spm_ddr_30b.edge_1.r,
                              input_word.spm_ddr_30b.edge_1.g,
                              input_word.spm_ddr_30b.edge_1.b
                            };
        repacked.pixel[1] = { 2'b0,
                              input_word.spm_ddr_30b.edge_2.r,
                              input_word.spm_ddr_30b.edge_2.g,
                              input_word.spm_ddr_30b.edge_2.b
                            };
      end
      {kSpm, kDdr, k24b}: begin
        repacked.pixel[0] = { 8'b0,
                              input_word.spm_ddr_24b.edge_1.r,
                              input_word.spm_ddr_24b.edge_1.g,
                              input_word.spm_ddr_24b.edge_1.b
                            };
        repacked.pixel[1] = { 8'b0,
                              input_word.spm_ddr_24b.edge_2.r,
                              input_word.spm_ddr_24b.edge_2.g,
                              input_word.spm_ddr_24b.edge_2.b
                            };
      end
      {kDpm, kSdr, k24b}: begin
        repacked.pixel[0] = { 8'b0,
                              input_word.dpm_sdr_24b.bits.r_a,
                              input_word.dpm_sdr_24b.bits.g_a,
                              input_word.dpm_sdr_24b.bits.b_a
                            };
        repacked.pixel[2] = { 8'b0,
                              input_word.dpm_sdr_24b.bits.r_b,
                              input_word.dpm_sdr_24b.bits.g_b,
                              input_word.dpm_sdr_24b.bits.b_b
                            };
      end
      {kDpm, kSdr, k30b}: begin
        repacked.pixel[0] = { 2'b0,
                              input_word.dpm_sdr_30b.bits.r_a,
                              input_word.dpm_sdr_30b.bits.g_a,
                              input_word.dpm_sdr_30b.bits.b_a
                            };
        repacked.pixel[2] = { 2'b0,
                              input_word.dpm_sdr_30b.bits.r_b,
                              input_word.dpm_sdr_30b.bits.g_b,
                              input_word.dpm_sdr_30b.bits.b_b
                            };
      end
      {kDpm, kDdr, k24b}: begin
        repacked.pixel[0] = { 8'b0,
                              input_word.dpm_ddr_24b.edge_1.r_a,
                              input_word.dpm_ddr_24b.edge_1.g_a,
                              input_word.dpm_ddr_24b.edge_1.b_a
                            };
        repacked.pixel[1] = { 8'b0,
                              input_word.dpm_ddr_24b.edge_2.r_a,
                              input_word.dpm_ddr_24b.edge_2.g_a,
                              input_word.dpm_ddr_24b.edge_2.b_a
                            };
        repacked.pixel[2] = { 8'b0,
                              input_word.dpm_ddr_24b.edge_1.r_b,
                              input_word.dpm_ddr_24b.edge_1.g_b,
                              input_word.dpm_ddr_24b.edge_1.b_b
                            };
        repacked.pixel[3] = { 8'b0,
                              input_word.dpm_ddr_24b.edge_2.r_b,
                              input_word.dpm_ddr_24b.edge_2.g_b,
                              input_word.dpm_ddr_24b.edge_2.b_b
                            };
      end
      {kDpm, kDdr, k30b}: begin
        repacked.pixel[0] = { 2'b0,
                              input_word.dpm_ddr_30b.edge_1.r_a,
                              input_word.dpm_ddr_30b.edge_1.g_a,
                              input_word.dpm_ddr_30b.edge_1.b_a
                            };
        repacked.pixel[1] = { 2'b0,
                              input_word.dpm_ddr_30b.edge_2.r_a,
                              input_word.dpm_ddr_30b.edge_2.g_a,
                              input_word.dpm_ddr_30b.edge_2.b_a
                            };
        repacked.pixel[2] = { 2'b0,
                              input_word.dpm_ddr_30b.edge_1.r_b,
                              input_word.dpm_ddr_30b.edge_1.g_b,
                              input_word.dpm_ddr_30b.edge_1.b_b
                            };
        repacked.pixel[3] = { 2'b0,
                              input_word.dpm_ddr_30b.edge_2.r_b,
                              input_word.dpm_ddr_30b.edge_2.g_b,
                              input_word.dpm_ddr_30b.edge_2.b_b
                            };
      end
      default: begin
        repacked.pixel[0] = { 8'b0,
                              input_word.spm_sdr_24b.bits.r,
                              input_word.spm_sdr_24b.bits.g,
                              input_word.spm_sdr_24b.bits.b
                            };
      end
    endcase
  end

endmodule : framebuffer_mode_mapper
