/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Copyright 2023 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

//////////////////////
// Reporter package //
//////////////////////

// Package delivered implementation of reporting mechanism which
// ensure message consistency with simulation environment.
package greporter_pkg;


  // Enum: uvm_verbosity
  //
  // Defines standard verbosity levels for reports
  // as in UVM
  //
  typedef enum {
    NONE   = 0,
    LOW    = 100,
    MEDIUM = 200,
    HIGH   = 300,
    FULL   = 400,
    DEBUG  = 500
  } verbosity_t;


  // Interface Class: greporter_ic
  //
  // Each reporter class must implement this interface
  // Global default reporter can be then replaced with user defined reporter
  //
  interface class greporter_ic;
    pure virtual function void report_info(string id, string message,
                                    int verbosity = MEDIUM, string filename = "", int line = 0);
    pure virtual function void report_warning(string id, string message,
                                    int verbosity = MEDIUM, string filename = "", int line = 0);
    pure virtual function void report_error(string id, string message,
                                    int verbosity = LOW, string filename = "", int line = 0);
    pure virtual function void report_fatal( string id, string message,
                                    int verbosity = NONE, string filename = "", int line = 0);
  endclass : greporter_ic


  // Class: greporter
  //
  // Global reporter singleton used by GVIPs to communicate with user
  // greporter implements default communication channel based on system tasks
  //
  class greporter implements greporter_ic;

    // Class default_reporter
    //
    // Default reporter implementation
    //
    class default_reporter implements greporter_ic;

      // Function: where
      //
      // Adds filename or line number to message
      //
      function string where(string filename = "", int line = 0);
        return filename.len() ?
                  $sformatf(" {%s%s}", filename, (line ? $sformatf("@%0d", line) : "")) :
                  "";
      endfunction : where

      virtual function void report_info(string id, string message,
                              int verbosity = MEDIUM, string filename = "", int line = 0);
        $display("%s : %s%s", id, message, where(filename, line));
      endfunction : report_info

      virtual function void report_warning(string id, string message,
                              int verbosity = MEDIUM, string filename = "", int line = 0);
        $warning("%s : %s%s", id, message, where(filename, line));
      endfunction : report_warning

      virtual function void report_error(string id, string message,
                              int verbosity = LOW, string filename = "", int line = 0);
        $error("%s : %s%s", id, message, where(filename, line));
      endfunction : report_error

      virtual function void report_fatal( string id, string message,
                              int verbosity = NONE, string filename = "", int line = 0);
        $fatal(1, $sformatf("%s : %s%s", id, message, where(filename, line)));
      endfunction : report_fatal
    endclass : default_reporter


    ////////////
    // Locals //
    ////////////

    local static greporter    _this; // singleton handler
    local        greporter_ic active_reporter; // current reporter used implementation
    local        int          verbosity_map[string] = '{default: MEDIUM}; // map of id:verbosity

    local function new();
      default_reporter dr = new();
      active_reporter = dr;
    endfunction : new


    //////////////////////
    // Static interface //
    //////////////////////

    static function greporter get();
      if (_this == null)
        _this = new();
      return _this;
    endfunction : get

    // Static function: info
    //
    // Use this function to report info using current active reporter
    //
    // id        - message id
    // message   - message text
    // verbosity - verbosity level
    // filename  - name of file where info is called (use macro `__FILE__)
    // line      - line number of file where info is called (use macro `__LINE__)
    static function void info(string id, string message,
          int verbosity = MEDIUM, string filename = "", int line = 0);
      greporter gr = greporter::get();
      gr.report_info(id, message, verbosity, filename, line);
    endfunction : info

    // Static function: warning
    //
    // Use this function to report warning using current active reporter
    //
    // id        - message id
    // message   - message text
    // verbosity - verbosity level
    // filename  - name of file where info is called (use macro `__FILE__)
    // line      - line number of file where info is called (use macro `__LINE__)
    static function void warning(string id, string message,
          int verbosity = MEDIUM, string filename = "", int line = 0);
      greporter gr = greporter::get();
      gr.report_warning(id, message, verbosity, filename, line);
    endfunction : warning

    // Static function: error
    //
    // Use this function to report error using current active reporter
    //
    // id        - message id
    // message   - message text
    // verbosity - verbosity level
    // filename  - name of file where info is called (use macro `__FILE__)
    // line      - line number of file where info is called (use macro `__LINE__)
    static function void error(string id, string message,
          int verbosity = LOW, string filename = "", int line = 0);
      greporter gr = greporter::get();
      gr.report_error(id, message, verbosity, filename, line);
    endfunction : error

    // Static function: fatal
    //
    // Use this function to report fatal using current active reporter
    //
    // id        - message id
    // message   - message text
    // verbosity - verbosity level
    // filename  - name of file where info is called (use macro `__FILE__)
    // line      - line number of file where info is called (use macro `__LINE__)
    static function void fatal( string id, string message,
          int verbosity = NONE, string filename = "", int line = 0);
      greporter gr = greporter::get();
      gr.report_fatal(id, message, verbosity, filename, line);
    endfunction : fatal


    // Static function: update
    //
    // Use this function to register new active reporter implementation
    //
    // new_greporter - class with greporter_ic implementation
    //
    static function void update(greporter_ic new_greporter);
      greporter gr = greporter::get();
      gr.reporter_update(new_greporter);
    endfunction : update


    // Static function: set_verbosity
    //
    // Set verbosity level for ID
    //
    // id        - message ID
    // verbosity - verbosity level (e.g. verbosity_t)
    //
    static function void set_verbosity(string id, int unsigned verbosity);
      greporter gr = greporter::get();
      gr.reporter_set_verbosity(id, verbosity);
    endfunction : set_verbosity


    // Static function: set_default_verbosity
    //
    // Set default verbosity for all IDs which will not be set
    // Removes all previous verbosity sets
    //
    // verbosity - verbosity level (e.g. verbosity_t)
    static function void set_default_verbosity(int unsigned verbosity);
      greporter gr = greporter::get();
      gr.reporter_set_default_verbosity(verbosity);
    endfunction : set_default_verbosity


    /////////////
    // Methods //
    /////////////

    function void reporter_update(greporter_ic new_greporter);
      active_reporter = new_greporter;
    endfunction : reporter_update

    function void reporter_set_verbosity(string id, int unsigned verbosity);
      verbosity_map[id] = verbosity;
    endfunction : reporter_set_verbosity

    function void reporter_set_default_verbosity(int unsigned verbosity);
      verbosity_map = '{default: verbosity};
    endfunction : reporter_set_default_verbosity

    virtual function void report_info(string id, string message,
          int verbosity = MEDIUM, string filename = "", int line = 0);
      if (verbosity <= verbosity_map[id])
        active_reporter.report_info(id, message, verbosity, filename, line);
    endfunction : report_info

    virtual function void report_warning(string id, string message,
          int verbosity = MEDIUM, string filename = "", int line = 0);
      if (verbosity <= verbosity_map[id])
        active_reporter.report_warning(id, message, verbosity, filename, line);
    endfunction : report_warning

    virtual function void report_error(string id, string message,
          int verbosity = LOW, string filename = "", int line = 0);
      if (verbosity <= verbosity_map[id])
        active_reporter.report_error(id, message, verbosity, filename, line);
    endfunction : report_error

    virtual function void report_fatal( string id, string message,
          int verbosity = NONE, string filename = "", int line = 0);
      if (verbosity <= verbosity_map[id])
        active_reporter.report_fatal(id, message, verbosity, filename, line);
    endfunction : report_fatal

  endclass : greporter


  // handy object to call warning in module context
  class build_warning;
    function new(string id, string message, int verbosity = MEDIUM,
                 string filename = "", int line = 0);
        greporter_pkg::greporter::warning(id, message, verbosity, filename, line);
    endfunction : new
  endclass : build_warning


endpackage : greporter_pkg
