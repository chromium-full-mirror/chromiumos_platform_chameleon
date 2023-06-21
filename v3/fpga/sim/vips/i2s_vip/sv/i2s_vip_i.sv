/*
 * Copyright 2021-2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

interface i2s_vip_if #(
    parameter string Name           = "unnamed interface",
    parameter bit    IsTransmitter  = 1,
    parameter bit    IsMaster       = 1,
    parameter int    MaxChannelSize = 32,
    parameter int    InterfaceArraySize = 0
) (
    input logic clk,
    input logic reset
);

  localparam string NamePath = $sformatf("%s at %m", Name);
  localparam int VifSize = InterfaceArraySize ? InterfaceArraySize : 1;

  typedef i2s_vip_pkg::i2s_item#(MaxChannelSize) item_t;

  // i2s interface instance
  i2s_if inf();
  // i2s array interfaces instances
  i2s_if infa[VifSize-1:0]();

  // auxiliary class for hold interface references
  class vif_holder#(int VifsNo = 1);
    virtual i2s_if vif[VifsNo];
  endclass
  vif_holder#(VifSize) holder = new();

  if (InterfaceArraySize) begin
    for (genvar i = 0; i < InterfaceArraySize; ++i) begin : clock_assign
      assign infa[i].clk = clk;
      initial holder.vif[i] = infa[i];
    end
  end else begin
    assign inf.clk = clk;
    initial holder.vif[0] = inf;
  end

  gclk_if clock(clk, reset);

  i2s_vip_pkg::verification_handler #(MaxChannelSize) vh[VifSize-1:0];
  greporter_pkg::greporter msg_h = greporter_pkg::greporter::get();

  function automatic void init();
    msg_h.reporter_set_verbosity("I2S_VIP", greporter_pkg::LOW);
    if (InterfaceArraySize) begin
      for (int i = 0; i < InterfaceArraySize; ++i) begin
        vh[i] = new(holder.vif[i], clock, IsTransmitter, IsMaster,
                    $sformatf("%s : %0d", NamePath, i), msg_h);
      end
    end else begin
      vh[0] = new(inf, clock, IsTransmitter, IsMaster, NamePath, msg_h);
    end
  endfunction

  function automatic void run_phase();
    if (vh[0] != null) begin
      for (int i = 0; i < vh.size(); ++i) begin
        vh[i].run_phase();
      end
    end else begin
      i2s_vip_pkg::verification_handler#(MaxChannelSize)::missing_init_call(msg_h, NamePath);
    end
  endfunction

  function automatic void add_ap2mon(i2s_vip_pkg::i2s_analysis_port_ic ap, int inf_no = 0);
    if (vh[inf_no] != null) vh[inf_no].add_ap2mon(ap);
    else i2s_vip_pkg::verification_handler#(MaxChannelSize)::missing_init_call(msg_h, NamePath);
  endfunction

  task automatic write_item(item_t data, int inf_no = 0);
    if (vh[inf_no] != null) vh[inf_no].write_item(data);
    else i2s_vip_pkg::verification_handler#(MaxChannelSize)::missing_init_call(msg_h, NamePath);
  endtask

  function automatic void clear(int inf_no = -1);
    if (vh[0] == null) begin
      i2s_vip_pkg::verification_handler#(MaxChannelSize)::missing_init_call(msg_h, NamePath);
    end else if (inf_no == -1) begin
      for (int i = 0; i < vh.size(); ++i) begin
        vh[i].clear();
      end
    end else begin
      vh[inf_no].clear();
    end
  endfunction

endinterface : i2s_vip_if
