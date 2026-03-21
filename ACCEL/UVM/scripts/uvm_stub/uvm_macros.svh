`ifndef UVM_MACROS_SVH
`define UVM_MACROS_SVH
// UVM macro stubs for verilator lint-only verification
`define uvm_object_utils(T)
`define uvm_object_utils_begin(T)
`define uvm_field_int(F,FL)
`define uvm_field_string(F,FL)
`define uvm_field_enum(T,F,FL)
`define uvm_field_array_int(F,FL)
`define uvm_object_utils_end
`define uvm_component_utils(T)
`define uvm_component_utils_begin(T)
`define uvm_component_utils_end
`define uvm_info(ID,MSG,VB)   $display("%0t [INFO ][%s] %s",$time,ID,MSG);
`define uvm_warning(ID,MSG)   $display("%0t [WARN ][%s] %s",$time,ID,MSG);
`define uvm_error(ID,MSG)     $display("%0t [ERROR][%s] %s",$time,ID,MSG);
`define uvm_fatal(ID,MSG)     begin $display("%0t [FATAL][%s] %s",$time,ID,MSG);$finish;end
`define UVM_ALL_ON    0
`define UVM_DEFAULT   0
`define UVM_NOPRINT   0
`define UVM_NOCOMPARE 0
`define UVM_NOCOPY    0
`define UVM_NOPACK    0
`define UVM_HIGH      400
`define UVM_MEDIUM    200
`define UVM_LOW       100
`define UVM_NONE      0
`endif
