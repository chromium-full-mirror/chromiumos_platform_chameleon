/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2023 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

package svunit_greporter_pkg;

  `include "svunit_defines.svh"

  import greporter_pkg::*;


  // Class: svunit_reporter
  //
  // Global reporter implementation for SvUnit environment
  // Self registered, just make import this package in SvUnit env
  //
  class svunit_reporter implements greporter_ic;

    static svunit_reporter me = get();

    virtual function void report_info(string id, string message,
                                    int verbosity = MEDIUM, string filename = "", int line = 0);
      string name = id;
      `INFO(message);
    endfunction : report_info

    virtual function void report_warning(string id, string message,
                                    int verbosity = MEDIUM, string filename = "", int line = 0);
      string name = id;
      `INFO(message);
    endfunction : report_warning

    virtual function void report_error(string id, string message,
                                    int verbosity = LOW, string filename = "", int line = 0);
      string name = id;
      `ERROR(message);
    endfunction : report_error

    virtual function void report_fatal( string id, string message,
                                    int verbosity = NONE, string filename = "", int line = 0);
      string name = id;
      `ERROR(message);
    endfunction : report_fatal

    static function svunit_reporter get();
      if (me == null) begin
        greporter gr = greporter_pkg::greporter::get();
        me = new();
        gr.reporter_update(me);
      end
      return me;
    endfunction : get

  endclass : svunit_reporter


endpackage : svunit_greporter_pkg
