/*
 * Copyright 2021-2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

package frame_pkg;

  interface class ic_picture_t;
    pure virtual function int get_pixels_num();
  endclass

  /**
    Video frame class build on axis_item_t
    base type (axis_item_t or extension) must be pass as T parameter
    this parameterization allow to put object to write_item method of VIP
   */
  class frame_tmds_t#(
    int Vactive,        // vertical resolution
    int Hactive,        // horizontal resolution
    int Vbp,            // vertical back porch
    int Vfp,            // vertical front porch
    int Vslen,          // vertical sync length
    int Hbp,            // horizontal back porch
    int Hfp,            // horizontal front porch
    int Hslen,          // horizontal sync length
    type T,
    bit InvPolarity = 0 // inverted polarity of VSYNC and HSYNC
  ) extends T implements ic_picture_t;

    localparam int unsigned Width = Hbp + Hactive + Hfp + Hslen;
    localparam int unsigned High = Vbp + Vactive + Vfp + Vslen;

    function void pre_randomize();
      tuser = new[Width * High];
      tkeep = new[Width * High];
      tdata = new[Width * High];

      size_max_c.constraint_mode(0);
      size_c.constraint_mode(0);
    endfunction

    function void post_randomize();
      int dbg_idx = 0;
      tkeep = '{default:'1};

      foreach (tuser[i]) begin
        tuser[i].vsync = InvPolarity;

        if (((i / Width) >= Vbp) && (i / Width < Vbp + Vactive)) begin
          if (i % Width == Width-1) tuser[i].hsync = ~InvPolarity;
          else tuser[i].hsync = InvPolarity;

          if ((i % Width >= Hbp) && (i % Width < Hbp + Hactive)) begin
            tuser[i].de = 1;
            tuser[i].dbg_idx = dbg_idx;
            dbg_idx++;
          end
          else tuser[i].de = 0;
        end else begin
          tuser[i].de = 0;
          tuser[i].hsync = InvPolarity;
        end
      end
      tuser[tuser.size()-1].vsync = ~InvPolarity;
      super.post_randomize();
    endfunction

    virtual function int get_pixels_num();
      return (Hactive * Vactive);
    endfunction

  endclass : frame_tmds_t



  class frame_dpm_t #(
    int Vactive,        // vertical resolution
    int Hactive,        // horizontal resolution
    int Vbp,            // vertical back porch
    int Vfp,            // vertical front porch
    int Vslen,          // vertical sync length
    int Hbp,            // horizontal back porch
    int Hfp,            // horizontal front porch
    int Hslen,          // horizontal sync length
    type T,
    bit InvPolarity = 0 // inverted polarity of VSYNC and HSYNC
  ) extends frame_tmds_t#(Vactive, Hactive/2, Vbp, Vfp, Vslen, Hbp/2, Hfp/2, Hslen/2, T, InvPolarity);

    virtual function int get_pixels_num();
      return (Hactive * Vactive);
    endfunction

  endclass : frame_dpm_t

  class frame_axis_t#(
    int Vactive,          // vertical resolution
    int Hactive,          // horizontal resolution
    type T,
    int PixelsInBeat = 4, // number of px in single beat
    bit Interlace = 0     // Interlaced frame
  ) extends T implements ic_picture_t;

    localparam int unsigned Width = Hactive/PixelsInBeat;
    localparam int unsigned High = Vactive;

    function void pre_randomize();
      tuser = new[Width * High];
      tkeep = new[Width * High];
      tdata = new[Width * High];

      size_max_c.constraint_mode(0);
      size_c.constraint_mode(0);
    endfunction

    function void post_randomize();
      tkeep = '{default:'1};

      foreach (tuser[i]) begin
        tuser[i].vid = '0;

        if (i % Width == (Width - 1)) begin
          tuser[i].vid.eol = 1'b1;
        end
        if (i % Width == 0) begin
          tuser[i].vid.sol = 1'b1;
        end
      end

      tuser[0].vid.sof = 1'b1;
      tuser[0].vid.sol = 1'b1;
      tuser[tuser.size()-1].vid.eol = 1'b1;
      tuser[tuser.size()-1].vid.eof = 1'b1;
      super.post_randomize();
    endfunction

    virtual function int get_pixels_num();
      return (Hactive * Vactive);
    endfunction

  endclass : frame_axis_t

endpackage : frame_pkg
