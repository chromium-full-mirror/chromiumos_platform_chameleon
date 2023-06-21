/*
 * Copyright 2021-2023 The Chromium OS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */



package i2s_vip_pkg;

  class i2s_item #(int MaxChannelSize = 32);

    typedef i2s_item #(MaxChannelSize) this_type;

    rand logic [MaxChannelSize-1:0] left;  // left channel sample
    rand logic [MaxChannelSize-1:0] right; // right channel sample
    rand int unsigned used_bits;           // number of used bits in each channel
    rand int unsigned ws_bclk_ratio;       // ws signal period in clocks cycles
    rand int unsigned repeat_this;         // repeating of this item (default: 1)

    constraint used_bits_range {
      used_bits inside {16, 20, 24, 32};
    }

    constraint ws_bclk_ratio_c {
      ws_bclk_ratio >= 64;
      ws_bclk_ratio <= 352;
      ws_bclk_ratio % 2 == 0;
    }

    constraint used_size_c {
      used_bits > 0;
      used_bits <= MaxChannelSize;
    }

    constraint mask_c {
      solve used_bits before left;
      solve used_bits before right;

      left  == (left & ({MaxChannelSize{1'b1}} << (MaxChannelSize-used_bits)));
      right == (right & ({MaxChannelSize{1'b1}} << (MaxChannelSize-used_bits)));
    }

    constraint repeat_c {
      soft repeat_this == 1;
    }

    extern         function           new();
    extern virtual function this_type clone();
    extern virtual function void      copy(this_type rhs);
    extern virtual function string    convert2string();

  endclass : i2s_item


  interface class i2s_analysis_port_ic #(int MaxChannelSize = 32);
    pure virtual task write (input i2s_item #(MaxChannelSize) item);
  endclass : i2s_analysis_port_ic


  //________________________________________________________________________________________________


  function i2s_item::new();
  endfunction : new


  function i2s_item::this_type i2s_item::clone();
    clone = new();
    clone.copy(this);
  endfunction : clone


  function void i2s_item::copy(i2s_item::this_type rhs);
    left = rhs.left;
    right = rhs.right;
    used_bits = rhs.used_bits;
    ws_bclk_ratio = rhs.ws_bclk_ratio;
    repeat_this = rhs.repeat_this;
  endfunction : copy


  function string i2s_item::convert2string();
    convert2string = $sformatf("i2s item {left: %h, right: %h, ub: %0d}", left, right, used_bits);
  endfunction : convert2string


  //________________________________________________________________________________________________


  class verification_handler #(int MaxChannelSize = 32);

    protected virtual i2s_if                            vif;
    protected virtual gclk_if                           clock;
    protected const bit                                 IsTransmiter;
    protected const bit                                 IsMaster;
    protected const string                              Name;
    protected const greporter_pkg::greporter_ic         MsgH;
    protected i2s_vip_pkg::i2s_analysis_port_ic         aps[$]; // analysis ports
    protected mailbox #(i2s_item #(MaxChannelSize))     to_transmit;
    protected process                                   single_run_process;

    typedef enum bit {
      kLeft,
      kRight
    } channel_e;


    function new(virtual i2s_if inf, virtual gclk_if clock, bit is_transmitter, bit is_master,
        string name, greporter_pkg::greporter_ic msg_h);
      this.vif = inf;
      this.clock = clock;
      this.IsTransmiter = is_transmitter;
      this.IsMaster = is_master;
      this.Name = name;
      this.MsgH = msg_h;
      this.to_transmit = new();
    endfunction : new


    virtual function void run_phase();
      fork // join_none - time consumption if function
        begin
          if (single_run_process == null || single_run_process.status() == process::KILLED
              || single_run_process.status() == process::FINISHED
            ) begin
            single_run_process = process::self();
            forever
              fork // disable fork guard
                begin
                  fork
                    bus_transactions_process();
                    waiting_for_reset_process();
                  join_any
                  disable fork;
                end
              join // disable fork guard
          end
        end
      join_none
    endfunction : run_phase


    local task bus_transactions_process();
      fork
        if (IsMaster) forever transmit();
        forever receive();
      join
    endtask : bus_transactions_process


    local task waiting_for_reset_process();
      @(posedge clock.clk);
      wait(clock.rst);
      vif.ws = '1;
      vif.data = 'x;
    endtask : waiting_for_reset_process


    virtual function void add_ap2mon(i2s_vip_pkg::i2s_analysis_port_ic ap);
      aps.push_back(ap);
    endfunction : add_ap2mon


    virtual task write_item(i2s_item #(MaxChannelSize) data);
      if (!to_transmit.try_put(data)) begin
        MsgH.report_error("I2S_VIP", $sformatf("[%s] Can't put to mailbox", Name),
            greporter_pkg::HIGH, `__FILE__, `__LINE__);
      end
    endtask : write_item


    virtual function void clear();
      i2s_item #(MaxChannelSize) dummy;
      while(to_transmit.try_get(dummy));
    endfunction : clear


    virtual task transmit();
      i2s_item #(MaxChannelSize) tr;
      bit                        first = 1;

      vif.ws = '1;
      forever begin
        if (!clock.rst) begin
          if (to_transmit.try_get(tr)) begin
            if (first) begin
              vif.ws = '0;
              @(negedge vif.clk);
              first = 0;
            end
            for (int jj = 0; jj < tr.repeat_this; ++jj) begin
              int unsigned transaction_bits = tr.used_bits > (tr.ws_bclk_ratio / 2)
                                            ? tr.used_bits : (tr.ws_bclk_ratio / 2);
              for (int i = 0; i < transaction_bits; ++i) begin
                if (IsTransmiter) vif.data = tr.left[tr.MaxChannelSize - i - 1];
                vif.ws = (i == transaction_bits - 1) ? '1 : '0;
                @(negedge vif.clk);
              end
              for (int i = 0; i < transaction_bits; ++i) begin
                if (IsTransmiter) vif.data = tr.right[tr.MaxChannelSize - i - 1];
                vif.ws = (i == transaction_bits - 1) ? '0 : '1;
                @(negedge vif.clk);
                vif.ws = '0;
              end
            end
          end else begin
            first = 1;
            if (IsTransmiter) vif.data = 'x;
            MsgH.report_info("I2S_VIP", $sformatf("[%s][%t] No transaction to send", Name, $time),
                greporter_pkg::MEDIUM, `__FILE__, `__LINE__);
            @(negedge vif.clk);
          end
        end else begin
          @(negedge vif.clk);
        end
      end
    endtask : transmit


    virtual task receive();
      i2s_item #(MaxChannelSize) item;
      i2s_item #(MaxChannelSize) item_fork;
      channel_e                  ws_d = kRight;
      logic                      buffer[$];

      forever begin
        @(posedge vif.clk);
        if (!clock.rst) begin
          buffer.push_back(vif.data);
          if (ws_d ^ vif.ws) begin
            buffer = buffer[0:MaxChannelSize-1]; // I2S Audio Input Mode - discard first bit
            if (ws_d == kLeft) begin
              item = new();
              item.left = {>>{buffer}};
            end else if (ws_d == kRight && item != null) begin
              item.right = {>>{buffer}};
              foreach (aps[i]) begin
                automatic int ii = i;
                item_fork = new();
                item_fork.copy(item);
                fork
                  aps[ii].write(item_fork.clone());
                join_none
              end
              item = null;
            end
            buffer.delete();
          end
          ws_d = vif.ws;
        end else begin
          ws_d = kRight;
          buffer.delete();
        end
      end
    endtask : receive


    static function void missing_init_call(greporter_pkg::greporter_ic rep, string id);
      rep.report_fatal("I2S_VIP", $sformatf("Call `init` first for `%s`", id));
    endfunction : missing_init_call

  endclass : verification_handler



endpackage : i2s_vip_pkg


