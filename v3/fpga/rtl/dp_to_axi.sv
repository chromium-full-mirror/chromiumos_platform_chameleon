/*
 * Copyright 2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

/*
 * Convert DisplayPort interface to AXI4Stream
 */
module dp_to_axi (
    dp_video_i.agent i_dp_vid_in,
    axis_i.host      i_axis_dp_vid
);

  always_comb begin
    i_axis_dp_vid.tvalid                = |i_dp_vid_in.valid && i_dp_vid_in.locked;
    i_axis_dp_vid.tdata                 = i_dp_vid_in.data;
    i_axis_dp_vid.tkeep                 = i_dp_vid_in.valid;
    i_axis_dp_vid.tuser.vid.data_valid  = |i_dp_vid_in.valid;
    i_axis_dp_vid.tuser.vid.sof         = i_dp_vid_in.sof;
    i_axis_dp_vid.tuser.vid.sol         = i_dp_vid_in.sol;
    i_axis_dp_vid.tuser.vid.eof         = i_dp_vid_in.eof;
    i_axis_dp_vid.tuser.vid.eol         = i_dp_vid_in.eol;
    i_axis_dp_vid.tuser.vid.interlace   = i_dp_vid_in.interlace;
    i_axis_dp_vid.tuser.vid.error       = i_dp_vid_in.overflow;
    i_axis_dp_vid.tlast                 = i_dp_vid_in.eof;
    i_axis_dp_vid.tuser.aud             = '0;
  end

endmodule : dp_to_axi
