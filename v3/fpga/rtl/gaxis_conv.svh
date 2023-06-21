/*
 * Copyright 2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

// Macros to handy convert VIP AXIS interface to/from AXI4Stream RTL interface

`define GAXIS_VIP_TO_AXIS(INF, U_T) \
    \
    axis_i #(.Tdata(logic[INF.N*8-1:0]), .Tkeep(logic[INF.N-1:0]), .Tuser(U_T)) axis_``INF(); \
    assign axis_``INF.tvalid = INF.axis.tvalid; \
    assign INF.axis.tready   = axis_``INF.tready; \
    assign axis_``INF.tdata  = INF.axis.tdata; \
    assign axis_``INF.tkeep  = INF.axis.tkeep; \
    assign axis_``INF.tuser  = INF.axis.tuser; \
    assign axis_``INF.tlast  = INF.axis.tlast;

`define AXIS_TO_GAXIS_VIP(INF, U_T) \
	\
    axis_i #(.Tdata(logic[INF.N*8-1:0]), .Tkeep(logic[INF.N-1:0]), .Tuser(U_T)) axis_``INF(); \
    assign INF.axis.tvalid   = axis_``INF.tvalid; \
    assign axis_``INF.tready = INF.axis.tready  ; \
    assign INF.axis.tdata    = axis_``INF.tdata ; \
    assign INF.axis.tkeep    = axis_``INF.tkeep ; \
    assign INF.axis.tuser    = axis_``INF.tuser ; \
    assign INF.axis.tlast    = axis_``INF.tlast ;

`define GAXIS_VIP_ARRAY_TO_AXIS_ARRAY(INF, U_T, NUM) \
  \
    axis_i #(.Tdata(logic[INF.N*8-1:0]), .Tkeep(logic[INF.N-1:0]), .Tuser(U_T)) axis_``INF[NUM](); \
    generate                                                \
      for (genvar i = 0; i < NUM; i++) begin                \
        assign axis_``INF[i].tvalid = INF.axis[i].tvalid;   \
        assign INF.axis[i].tready   = axis_``INF[i].tready; \
        assign axis_``INF[i].tdata  = INF.axis[i].tdata;    \
        assign axis_``INF[i].tkeep  = INF.axis[i].tkeep;    \
        assign axis_``INF[i].tuser  = INF.axis[i].tuser;    \
        assign axis_``INF[i].tlast  = INF.axis[i].tlast;    \
      end                                                   \
    endgenerate

`define AXIS_ARRAY_TO_GAXIS_VIP_ARRAY(INF, U_T, NUM) \
	\
    axis_i #(.Tdata(logic[INF.N*8-1:0]), .Tkeep(logic[INF.N-1:0]), .Tuser(U_T)) axis_``INF[NUM](); \
    generate                                              \
    for (genvar i = 0; i < NUM; i++) begin                \
      assign INF.axis[i].tvalid   = axis_``INF[i].tvalid; \
      assign axis_``INF[i].tready = INF.axis[i].tready  ; \
      assign INF.axis[i].tdata    = axis_``INF[i].tdata ; \
      assign INF.axis[i].tkeep    = axis_``INF[i].tkeep ; \
      assign INF.axis[i].tuser    = axis_``INF[i].tuser ; \
      assign INF.axis[i].tlast    = axis_``INF[i].tlast ; \
    end                                                   \
    endgenerate

