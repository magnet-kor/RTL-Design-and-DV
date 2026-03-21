`include "uvm_macros.svh"
package uvm_pkg;
  typedef enum int {
    UVM_NONE=0, UVM_LOW=100, UVM_MEDIUM=200,
    UVM_HIGH=400, UVM_FULL=500, UVM_DEBUG=600
  } uvm_verbosity;

  typedef enum int {
    UVM_INFO=0, UVM_WARNING=1, UVM_ERROR=2, UVM_FATAL=3
  } uvm_severity;
  typedef enum int { UVM_ACTIVE=1, UVM_PASSIVE=0 } uvm_active_passive_enum;
  class uvm_object;
    string m_name;
    function new(string name=""); m_name=name; endfunction
    virtual function string get_name(); return m_name; endfunction
    virtual function string get_type_name(); return "uvm_object"; endfunction
    virtual function string convert2string(); return m_name; endfunction
    virtual function void do_copy(uvm_object rhs); endfunction
    virtual function bit  do_compare(uvm_object rhs, uvm_object cmp=null); return 1; endfunction
  endclass
  class uvm_sequence_item extends uvm_object;
    function new(string name="uvm_sequence_item"); super.new(name); endfunction
  endclass
  class uvm_report_server;
    static uvm_report_server inst;
    static function uvm_report_server get_server();
      if (inst==null) inst=new(); return inst;
    endfunction
    function int get_severity_count(int sev); return 0; endfunction
  endclass
  class uvm_report_object extends uvm_object;
    function new(string name=""); super.new(name); endfunction
    function void uvm_report_info(string id,string msg,int v=200,string fn="",int ln=0);
      if(v<=200) $display("%0t [INFO][%s] %s",$time,id,msg);
    endfunction
    function void uvm_report_warning(string id,string msg);
      $display("%0t [WARN][%s] %s",$time,id,msg);
    endfunction
    function void uvm_report_error(string id,string msg);
      $display("%0t [ERROR][%s] %s",$time,id,msg);
    endfunction
    function void uvm_report_fatal(string id,string msg);
      $display("%0t [FATAL][%s] %s",$time,id,msg); $finish;
    endfunction
  endclass
  class uvm_component extends uvm_report_object;
    uvm_component m_parent;
    string        m_path;
    function new(string name="",uvm_component parent=null);
      super.new(name); m_parent=parent;
      m_path=(parent!=null)?{parent.get_full_name(),".",name}:name;
    endfunction
    virtual function string get_full_name(); return m_path; endfunction
    virtual function void build_phase(uvm_component ph); endfunction
    virtual function void connect_phase(uvm_component ph); endfunction
    virtual task          run_phase(uvm_component ph); endtask
    virtual function void extract_phase(uvm_component ph); endfunction
    virtual function void check_phase(uvm_component ph); endfunction
    virtual function void report_phase(uvm_component ph); endfunction
    function void raise_objection(uvm_component c); endfunction
    function void drop_objection(uvm_component c); endfunction
  endclass
  class uvm_driver #(type REQ=uvm_sequence_item,type RSP=uvm_sequence_item) extends uvm_component;
    REQ req; RSP rsp;

    function new(string name="",uvm_component parent=null); super.new(name,parent); endfunction
  endclass
  class uvm_monitor extends uvm_component;
    function new(string name="",uvm_component parent=null); super.new(name,parent); endfunction
  endclass
  class uvm_scoreboard extends uvm_component;
    function new(string name="",uvm_component parent=null); super.new(name,parent); endfunction
  endclass
  class uvm_agent extends uvm_component;
    uvm_active_passive_enum is_active;
    function new(string name="",uvm_component parent=null);
      super.new(name,parent); is_active=UVM_ACTIVE;
    endfunction
  endclass
  class uvm_env extends uvm_component;
    function new(string name="",uvm_component parent=null); super.new(name,parent); endfunction
  endclass
  class uvm_test extends uvm_component;
    function new(string name="",uvm_component parent=null); super.new(name,parent); endfunction
  endclass
  class uvm_sequence_base extends uvm_object;
    function new(string name=""); super.new(name); endfunction
    virtual task body(); endtask
    task start(uvm_component seqr=null,int prio=-1); body(); endtask
    task start_item(uvm_sequence_item it); endtask
    task finish_item(uvm_sequence_item it); endtask
  endclass
  class uvm_sequence #(type REQ=uvm_sequence_item,type RSP=uvm_sequence_item) extends uvm_sequence_base;
    REQ req; RSP rsp;
    function new(string name=""); super.new(name); endfunction
  endclass
  class uvm_sequencer #(type REQ=uvm_sequence_item,type RSP=uvm_sequence_item) extends uvm_component;
    // mailbox seq_export;  // typed as plain mailbox; VCS/Questa use // mailbox #(REQ)
    function new(string name="",uvm_component parent=null);
      super.new(name,parent); /* stub */;
    endfunction
    task get_next_item(output REQ req_arg); /* stub */; endtask
    function void item_done(); endfunction
  endclass
  class uvm_analysis_port #(type T=uvm_sequence_item);
    string m_name;
    function new(string name="",uvm_component p=null); m_name=name; endfunction
    function void write(T t); endfunction
    function void connect(uvm_analysis_port #(T) other); endfunction
  endclass
  class uvm_analysis_imp #(type T=uvm_sequence_item,type IMP=uvm_component);
    string m_name;
    function new(string name="",uvm_component imp=null); m_name=name; endfunction
  endclass
  class uvm_tlm_analysis_fifo #(type T=uvm_sequence_item);
    function new(string name="",uvm_component p=null); endfunction
    task get(output T item); endtask
    function int unsigned used(); return 0; endfunction
  endclass
  class uvm_config_db #(type T=int);
    static function void set(uvm_component ctx,string path,string name,T val); endfunction
    static function bit  get(uvm_component ctx,string path,string name,output T val); return 0; endfunction
  endclass
  function automatic void run_test(string test_name="");
    $display("[UVM] run_test: %s", test_name);
  endfunction
endpackage
