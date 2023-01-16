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
    local        int          verbosity_map[string]       = '{default: MEDIUM}; // id:verbosity
    local        int          counter_info_map[string]    = '{default: 0};
    local        int          counter_warning_map[string] = '{default: 0};
    local        int          counter_error_map[string]   = '{default: 0};
    local        int          counter_fatal_map[string]   = '{default: 0};

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


    // Static function: get_counter_info
    //
    // Returns number of info messages
    // id - message ID
    static function int get_counter_info(string id = "");
      greporter gr = greporter::get();
      return gr.counter_info(id);
    endfunction : get_counter_info


    // Static function: get_counter_warning
    //
    // Returns number of warning messages
    // id - message ID
    static function int get_counter_warning(string id = "");
      greporter gr = greporter::get();
      return gr.counter_warning(id);
    endfunction : get_counter_warning


    // Static function: get_counter_error
    //
    // Returns number of error messages
    // id - message ID
    static function int get_counter_error(string id = "");
      greporter gr = greporter::get();
      return gr.counter_error(id);
    endfunction : get_counter_error


    // Static function: get_counter_fatal
    //
    // Returns number of fatal messages
    // id - message ID
    static function int get_counter_fatal(string id = "");
      greporter gr = greporter::get();
      return gr.counter_fatal(id);
    endfunction : get_counter_fatal


    // Static function: clear_counters
    //
    // Clears message counters
    static function void clear_counters();
      greporter gr = greporter::get();
      gr.erase_counters();
    endfunction : clear_counters


    // Static function: convert2string
    //
    // Returns string with reporter's statistics
    static function string convert2string();
      greporter gr = greporter::get();
      return gr.counters2string();
    endfunction : convert2string

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
      if (verbosity <= verbosity_map[id]) begin
        counter_info_map[id]++;
        active_reporter.report_info(id, message, verbosity, filename, line);
      end
    endfunction : report_info

    virtual function void report_warning(string id, string message,
          int verbosity = MEDIUM, string filename = "", int line = 0);
      if (verbosity <= verbosity_map[id]) begin
        counter_warning_map[id]++;
        active_reporter.report_warning(id, message, verbosity, filename, line);
      end
    endfunction : report_warning

    virtual function void report_error(string id, string message,
          int verbosity = LOW, string filename = "", int line = 0);
      if (verbosity <= verbosity_map[id]) begin
        counter_error_map[id]++;
        active_reporter.report_error(id, message, verbosity, filename, line);
      end
    endfunction : report_error

    virtual function void report_fatal( string id, string message,
          int verbosity = NONE, string filename = "", int line = 0);
      if (verbosity <= verbosity_map[id]) begin
        counter_fatal_map[id]++;
        active_reporter.report_fatal(id, message, verbosity, filename, line);
      end
    endfunction : report_fatal


    // Function: counter_info
    //
    // Returns number of info messages
    // id - message ID
    function int counter_info(string id = "");
      return ((id == "") ? counter_info_map.sum() : counter_info_map[id]);
    endfunction : counter_info


    // Function: counter_warning
    //
    // Returns number of warning messages
    // id - message ID
    function int counter_warning(string id = "");
      return ((id == "") ? counter_warning_map.sum() : counter_warning_map[id]);
    endfunction : counter_warning


    // Function: counter_error
    //
    // Returns number of error messages
    // id - message ID
    function int counter_error(string id = "");
      return ((id == "") ? counter_error_map.sum() : counter_error_map[id]);
    endfunction : counter_error


    // Function: counter_fatal
    //
    // Returns number of fatal messages
    // id - message ID
    function int counter_fatal(string id = "");
      return ((id == "") ? counter_fatal_map.sum() : counter_fatal_map[id]);
    endfunction : counter_fatal


    // Function: erase_counters
    //
    // Clears message counters
    function void erase_counters();
      counter_info_map.delete();
      counter_warning_map.delete();
      counter_error_map.delete();
      counter_fatal_map.delete();
    endfunction : erase_counters


    // Function: convert2string
    //
    // Returns string with reporter's statistics
    function string counters2string();
      string output_string;
      string ids[$];
      ids = {counter_info_map.find_index() with (item),
             counter_warning_map.find_index() with (item),
             counter_error_map.find_index() with (item),
             counter_fatal_map.find_index() with (item)};
      ids = ids.unique();

      output_string =
        $sformatf("%s\nTotal", output_string);
      output_string =
        $sformatf("%s\n\tInfos num:    %0d", output_string, counter_info_map.sum());
      output_string =
        $sformatf("%s\n\tWarnings num: %0d", output_string, counter_warning_map.sum());
      output_string =
        $sformatf("%s\n\tErrors num:   %0d", output_string, counter_error_map.sum());
      output_string =
        $sformatf("%s\n\tFatals num:   %0d", output_string, counter_fatal_map.sum());

      foreach (ids[i]) begin
        output_string =
          $sformatf("%s\n%s", output_string, ids[i]);
        output_string =
          $sformatf("%s\n\tInfos num:    %0d", output_string, counter_info_map[ids[i]]);
        output_string =
          $sformatf("%s\n\tWarnings num: %0d", output_string, counter_warning_map[ids[i]]);
        output_string =
          $sformatf("%s\n\tErrors num:   %0d", output_string, counter_error_map[ids[i]]);
        output_string =
          $sformatf("%s\n\tFatals num:   %0d", output_string, counter_fatal_map[ids[i]]);
      end
      return output_string;
    endfunction : counters2string


  endclass : greporter


  // handy object to call warning in module context
  class build_warning;
    function new(string id, string message, int verbosity = MEDIUM,
                 string filename = "", int line = 0);
        greporter_pkg::greporter::warning(id, message, verbosity, filename, line);
    endfunction : new
  endclass : build_warning


endpackage : greporter_pkg
